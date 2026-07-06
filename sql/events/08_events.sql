-- =============================================================================
-- 08_events.sql — Événements planifiés (MariaDB Event Scheduler)
-- -----------------------------------------------------------------------------
-- QU'EST-CE QU'UN EVENT ?
--
-- Un EVENT est une tâche SQL exécutée AUTOMATIQUEMENT selon une planification
-- (toutes les heures, tous les jours...), directement par le serveur MariaDB.
-- C'est l'équivalent d'un « cron », mais intégré à la base : pas besoin de
-- service externe pour les tâches de maintenance des données.
--
-- CONDITION INDISPENSABLE : l'ordonnanceur doit être actif. Il l'est via :
--   - SET GLOBAL event_scheduler = ON  (voir 01_privileges.sql), et
--   - l'option serveur --event-scheduler=ON (voir docker-compose.yml).
-- Vérification :  SHOW VARIABLES LIKE 'event_scheduler';
-- Lister les events :  SHOW EVENTS;
--
-- ON COMPLETION PRESERVE : conserve l'event après exécution (sinon un event
-- serait supprimé une fois terminé). Indispensable pour les tâches récurrentes.
--
-- POUR TESTER SANS ATTENDRE : on peut exécuter le corps d'un event à la main,
-- ou forcer son exécution en modifiant temporairement sa planification. Les
-- STARTS ci-dessous sont décalés de quelques heures pour ne pas se déclencher
-- pendant l'initialisation de la base.
-- =============================================================================

USE bibliotheque;

DELIMITER //

-- -----------------------------------------------------------------------------
-- EVENT 1 — Détection des retards (maintenance métier quotidienne)
--
-- Chaque jour, les emprunts « en_cours » dont la date de retour prévue est
-- dépassée passent au statut « en_retard ». C'est ce qui alimente la vue des
-- retards et le calcul des pénalités.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS ev_marquer_emprunts_en_retard //
CREATE EVENT ev_marquer_emprunts_en_retard
    ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_TIMESTAMP + INTERVAL 1 HOUR)
    ON COMPLETION PRESERVE
    COMMENT 'Passe en retard les emprunts dont l échéance est dépassée'
    DO
        UPDATE emprunts
           SET statut = 'en_retard'
         WHERE statut = 'en_cours'
           AND date_retour_prevue < CURRENT_DATE //

-- -----------------------------------------------------------------------------
-- EVENT 2 — Purge des jetons de rafraîchissement (nettoyage, toutes les heures)
--
-- On supprime les refresh tokens expirés ou révoqués. Cela évite que la table
-- ne gonfle indéfiniment et réduit la surface d'attaque.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS ev_purger_jetons_expires //
CREATE EVENT ev_purger_jetons_expires
    ON SCHEDULE EVERY 1 HOUR STARTS (CURRENT_TIMESTAMP + INTERVAL 10 MINUTE)
    ON COMPLETION PRESERVE
    COMMENT 'Supprime les jetons de rafraîchissement expirés ou révoqués'
    DO
        DELETE FROM jetons_rafraichissement
         WHERE expire_le < NOW() OR revoque = TRUE //

-- -----------------------------------------------------------------------------
-- EVENT 3 — Archivage des emprunts anciens (maintenance, quotidien)
--
-- Les emprunts rendus depuis plus d'un an sont DÉPLACÉS vers emprunts_archive
-- (INSERT puis DELETE). La table « emprunts » reste ainsi compacte et rapide,
-- tout en conservant l'historique. Corps multi-instructions => BEGIN ... END.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS ev_archiver_emprunts_anciens //
CREATE EVENT ev_archiver_emprunts_anciens
    ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_TIMESTAMP + INTERVAL 2 HOUR)
    ON COMPLETION PRESERVE
    COMMENT 'Déplace les emprunts rendus depuis plus d un an vers l archive'
    DO
    BEGIN
        INSERT INTO emprunts_archive
            (id, uuid, utilisateur_id, livre_id, date_emprunt, date_retour_prevue,
             date_retour_effective, statut, penalite, cree_le)
        SELECT
            id, uuid, utilisateur_id, livre_id, date_emprunt, date_retour_prevue,
            date_retour_effective, statut, penalite, cree_le
        FROM emprunts
        WHERE statut = 'rendu'
          AND date_retour_effective < DATE_SUB(CURRENT_DATE, INTERVAL 1 YEAR);

        DELETE FROM emprunts
        WHERE statut = 'rendu'
          AND date_retour_effective < DATE_SUB(CURRENT_DATE, INTERVAL 1 YEAR);
    END //

-- -----------------------------------------------------------------------------
-- EVENT 4 — Calcul des statistiques quotidiennes (agrégation, quotidien)
--
-- Écrit (ou met à jour) une ligne d'indicateurs pour la journée dans
-- statistiques_quotidiennes. « ON DUPLICATE KEY UPDATE » réalise un « upsert » :
-- insertion si la date n'existe pas encore, mise à jour sinon.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS ev_calculer_statistiques_quotidiennes //
CREATE EVENT ev_calculer_statistiques_quotidiennes
    ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_TIMESTAMP + INTERVAL 3 HOUR)
    ON COMPLETION PRESERVE
    COMMENT 'Agrège les indicateurs du jour dans statistiques_quotidiennes'
    DO
        INSERT INTO statistiques_quotidiennes
            (date_statistique, nb_emprunts_actifs, nb_emprunts_en_retard,
             nb_livres, nb_exemplaires_dispo, nb_utilisateurs_actifs)
        SELECT
            CURRENT_DATE,
            (SELECT COUNT(*) FROM emprunts WHERE statut IN ('en_cours','en_retard')),
            (SELECT COUNT(*) FROM emprunts WHERE statut = 'en_retard'),
            (SELECT COUNT(*) FROM livres WHERE supprime_le IS NULL),
            (SELECT IFNULL(SUM(exemplaires_disponibles), 0) FROM livres WHERE supprime_le IS NULL),
            (SELECT COUNT(*) FROM utilisateurs WHERE actif = TRUE AND supprime_le IS NULL)
        ON DUPLICATE KEY UPDATE
            nb_emprunts_actifs     = VALUES(nb_emprunts_actifs),
            nb_emprunts_en_retard  = VALUES(nb_emprunts_en_retard),
            nb_livres              = VALUES(nb_livres),
            nb_exemplaires_dispo   = VALUES(nb_exemplaires_dispo),
            nb_utilisateurs_actifs = VALUES(nb_utilisateurs_actifs) //

-- -----------------------------------------------------------------------------
-- EVENT 5 — Nettoyage du journal d'audit (rétention, hebdomadaire)
--
-- On conserve 90 jours d'audit. Au-delà, les entrées sont supprimées pour
-- respecter une politique de rétention et limiter la taille de la table.
-- -----------------------------------------------------------------------------
DROP EVENT IF EXISTS ev_nettoyer_journal_audit //
CREATE EVENT ev_nettoyer_journal_audit
    ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_TIMESTAMP + INTERVAL 4 HOUR)
    ON COMPLETION PRESERVE
    COMMENT 'Supprime les entrées du journal d audit de plus de 90 jours'
    DO
        DELETE FROM journal_audit
         WHERE cree_le < DATE_SUB(NOW(), INTERVAL 90 DAY) //

DELIMITER ;
