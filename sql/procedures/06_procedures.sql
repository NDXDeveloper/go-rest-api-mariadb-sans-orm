-- =============================================================================
-- 06_procedures.sql — Procédures stockées
-- -----------------------------------------------------------------------------
-- PROCÉDURE vs FONCTION
--   - Une FONCTION renvoie UNE valeur et s'utilise dans une expression SQL.
--   - Une PROCÉDURE peut modifier des données, gérer une TRANSACTION, renvoyer
--     plusieurs valeurs via des paramètres OUT, et s'appelle avec CALL.
--
-- CE QUE CE FICHIER DÉMONTRE
--   - paramètres IN / OUT / INOUT ;
--   - transaction (START TRANSACTION / COMMIT / ROLLBACK) DANS une procédure ;
--   - gestion des erreurs avec un HANDLER (DECLARE ... HANDLER) ;
--   - verrouillage de ligne (SELECT ... FOR UPDATE) pour la concurrence ;
--   - codes de retour applicatifs pour que l'appelant Go réagisse finement.
--
-- APPEL DEPUIS Go (voir internal/repository/emprunt_repository.go)
--   Les paramètres OUT se récupèrent via des variables de session :
--       CALL pr_emprunter_livre(?, ?, ?, @uuid, @code, @message);
--       SELECT @uuid, @code, @message;
--   Les deux requêtes DOIVENT passer par la MÊME connexion (sql.Conn).
-- =============================================================================

USE bibliotheque;

DELIMITER //

-- -----------------------------------------------------------------------------
-- pr_emprunter_livre : enregistre un emprunt de manière ATOMIQUE et sûre.
--
-- Entrées (IN)
--   p_utilisateur_uuid : identifiant public de l'emprunteur ;
--   p_livre_uuid       : identifiant public du livre ;
--   p_duree_jours      : durée du prêt (0 ou NULL => 14 jours par défaut).
-- Sorties (OUT)
--   p_emprunt_uuid  : UUID de l'emprunt créé (NULL en cas d'échec) ;
--   p_code_resultat : 0 = succès ; 1 = livre introuvable ; 2 = utilisateur
--                     introuvable/inactif ; 3 = indisponible ; 4 = quota atteint ;
--                     99 = erreur SQL inattendue ;
--   p_message       : message explicatif en français.
--
-- Déroulé : on verrouille le livre (FOR UPDATE), on vérifie disponibilité et
-- quota, on insère l'emprunt et on décrémente le stock — le tout dans UNE
-- transaction. À la moindre anomalie, ROLLBACK : aucune modification partielle.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_emprunter_livre //
CREATE PROCEDURE pr_emprunter_livre(
    IN  p_utilisateur_uuid CHAR(36),
    IN  p_livre_uuid       CHAR(36),
    IN  p_duree_jours      INT,
    OUT p_emprunt_uuid     CHAR(36),
    OUT p_code_resultat    INT,
    OUT p_message          VARCHAR(255)
)
BEGIN
    DECLARE v_utilisateur_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_livre_id       BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_dispo          INT DEFAULT 0;
    DECLARE v_nb_actifs      INT DEFAULT 0;
    DECLARE v_quota_max      INT DEFAULT 5;   -- quota d'emprunts simultanés (paramètre métier)
    DECLARE v_duree          INT DEFAULT 14;
    DECLARE v_uuid           CHAR(36);

    -- HANDLER : en cas d'exception SQL non prévue (deadlock, contrainte...), on
    -- annule la transaction et on remonte un code d'erreur générique plutôt que
    -- de laisser filtrer un message technique.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_emprunt_uuid  = NULL;
        SET p_code_resultat = 99;
        SET p_message       = 'Erreur inattendue : l''emprunt a été annulé.';
    END;

    -- Normalisation de la durée demandée (bornes de sécurité).
    SET v_duree = IFNULL(NULLIF(p_duree_jours, 0), 14);
    IF v_duree < 1  THEN SET v_duree = 14; END IF;
    IF v_duree > 90 THEN SET v_duree = 90; END IF;

    START TRANSACTION;

    -- 1) L'utilisateur existe-t-il et est-il actif ?
    SELECT id INTO v_utilisateur_id
        FROM utilisateurs
        WHERE uuid = p_utilisateur_uuid AND supprime_le IS NULL AND actif = TRUE
        LIMIT 1;

    IF v_utilisateur_id IS NULL THEN
        ROLLBACK;
        SET p_code_resultat = 2;
        SET p_message = 'Utilisateur introuvable ou inactif.';
    ELSE
        -- 2) Verrouillage du livre pour la durée de la transaction. Deux emprunts
        --    concurrents du dernier exemplaire seront ainsi sérialisés : le second
        --    attendra puis verra exemplaires_disponibles = 0.
        SELECT id, exemplaires_disponibles
            INTO v_livre_id, v_dispo
            FROM livres
            WHERE uuid = p_livre_uuid AND supprime_le IS NULL
            FOR UPDATE;

        IF v_livre_id IS NULL THEN
            ROLLBACK;
            SET p_code_resultat = 1;
            SET p_message = 'Livre introuvable.';
        ELSEIF v_dispo <= 0 THEN
            ROLLBACK;
            SET p_code_resultat = 3;
            SET p_message = 'Aucun exemplaire disponible actuellement.';
        ELSE
            -- 3) Respect du quota d'emprunts simultanés.
            SET v_nb_actifs = fn_nb_emprunts_actifs(v_utilisateur_id);
            IF v_nb_actifs >= v_quota_max THEN
                ROLLBACK;
                SET p_code_resultat = 4;
                SET p_message = CONCAT('Quota d''emprunts simultanés atteint (', v_quota_max, ').');
            ELSE
                -- 4) Création de l'emprunt et décrément du stock (2 tables, 1 transaction).
                SET v_uuid = UUID();
                INSERT INTO emprunts (uuid, utilisateur_id, livre_id, date_emprunt, date_retour_prevue, statut)
                    VALUES (v_uuid, v_utilisateur_id, v_livre_id, CURRENT_DATE,
                            DATE_ADD(CURRENT_DATE, INTERVAL v_duree DAY), 'en_cours');

                UPDATE livres
                    SET exemplaires_disponibles = exemplaires_disponibles - 1
                    WHERE id = v_livre_id;

                COMMIT;
                SET p_emprunt_uuid  = v_uuid;
                SET p_code_resultat = 0;
                SET p_message       = 'Emprunt enregistré avec succès.';
            END IF;
        END IF;
    END IF;
END //

-- -----------------------------------------------------------------------------
-- pr_statistiques_utilisateur : renvoie plusieurs indicateurs via des OUT.
--
-- Illustre le retour de PLUSIEURS valeurs par une procédure (là où une fonction
-- n'en renverrait qu'une seule).
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_statistiques_utilisateur //
CREATE PROCEDURE pr_statistiques_utilisateur(
    IN  p_utilisateur_uuid CHAR(36),
    OUT p_nb_total         INT,
    OUT p_nb_en_cours      INT,
    OUT p_nb_en_retard     INT,
    OUT p_total_penalites  DECIMAL(10,2)
)
BEGIN
    DECLARE v_id BIGINT UNSIGNED DEFAULT NULL;

    SELECT id INTO v_id
        FROM utilisateurs
        WHERE uuid = p_utilisateur_uuid
        LIMIT 1;

    -- Une seule requête agrégée alimente les quatre paramètres OUT.
    SELECT
        COUNT(*),
        IFNULL(SUM(statut = 'en_cours'), 0),
        IFNULL(SUM(statut = 'en_retard'), 0),
        IFNULL(SUM(penalite), 0)
    INTO p_nb_total, p_nb_en_cours, p_nb_en_retard, p_total_penalites
    FROM emprunts
    WHERE utilisateur_id = v_id;
END //

-- -----------------------------------------------------------------------------
-- pr_ajuster_disponibilite : exemple minimal de paramètre INOUT.
--
-- Un paramètre INOUT sert à la fois d'entrée ET de sortie : la valeur fournie
-- par l'appelant est modifiée « sur place ». Ici, on ajoute un delta au stock
-- courant en interdisant de passer sous zéro.
--
--   SET @stock = 3;
--   CALL pr_ajuster_disponibilite(@stock, -1);  -- @stock vaut désormais 2
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS pr_ajuster_disponibilite //
CREATE PROCEDURE pr_ajuster_disponibilite(
    INOUT p_disponibles INT,
    IN    p_delta       INT
)
BEGIN
    SET p_disponibles = GREATEST(p_disponibles + p_delta, 0);
END //

DELIMITER ;
