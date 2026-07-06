-- =============================================================================
-- 04_fonctions.sql — Fonctions SQL stockées
-- -----------------------------------------------------------------------------
-- INTÉRÊT DES FONCTIONS STOCKÉES
--
-- Une fonction stockée encapsule un calcul RÉUTILISABLE directement dans le SQL.
-- Avantages :
--   - on écrit la règle UNE fois, on la réutilise dans des vues, des procédures,
--     des requêtes ad hoc (cohérence garantie) ;
--   - le calcul s'exécute au plus près des données (pas d'aller-retour réseau).
-- Limite : une fonction ne doit pas être trop lourde (elle peut être appelée
-- pour chaque ligne). Pour de la logique complexe/transactionnelle, on préfère
-- une PROCÉDURE (voir 06_procedures.sql).
--
-- À PROPOS DE « DELIMITER »
--   Le corps d'une routine contient des « ; » internes. Si le client interprétait
--   chaque « ; » comme la fin de l'instruction, il couperait la définition en
--   morceaux. On change donc temporairement le délimiteur de fin d'instruction
--   en « // » le temps de définir la routine, puis on le remet à « ; ».
--
-- log_bin_trust_function_creators : autorise la création de fonctions même quand
--   la journalisation binaire est active (sinon MariaDB peut refuser, par
--   prudence, une fonction non déclarée déterministe). Sans effet si le binlog
--   est désactivé (cas par défaut du conteneur).
-- =============================================================================

USE bibliotheque;
SET GLOBAL log_bin_trust_function_creators = 1;

DELIMITER //

-- -----------------------------------------------------------------------------
-- fn_est_disponible : un livre a-t-il au moins un exemplaire disponible ?
--
-- Paramètre  : p_livre_id — clé technique du livre.
-- Retour     : TRUE (1) si exemplaires_disponibles > 0, FALSE (0) sinon.
-- Caractéristiques : READS SQL DATA (elle lit la base mais ne la modifie pas).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_est_disponible //
CREATE FUNCTION fn_est_disponible(p_livre_id BIGINT UNSIGNED)
    RETURNS BOOLEAN
    READS SQL DATA
BEGIN
    DECLARE v_dispo INT DEFAULT 0;

    SELECT exemplaires_disponibles
        INTO v_dispo
        FROM livres
        WHERE id = p_livre_id AND supprime_le IS NULL;

    -- Si le livre n'existe pas, v_dispo reste 0 → on renvoie FALSE.
    RETURN v_dispo > 0;
END //

-- -----------------------------------------------------------------------------
-- fn_calculer_penalite : montant dû pour un retour, selon le retard.
--
-- Règle métier : 0,50 € par jour de retard entamé. Aucun retard => 0 €.
-- Si p_date_effective est NULL (livre pas encore rendu), on calcule le retard
-- « à aujourd'hui » (utile pour afficher la pénalité courante d'un emprunt actif).
--
-- NOT DETERMINISTIC car le résultat peut dépendre de la date du jour (CURRENT_DATE).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_calculer_penalite //
CREATE FUNCTION fn_calculer_penalite(p_date_prevue DATE, p_date_effective DATE)
    RETURNS DECIMAL(8,2)
    NOT DETERMINISTIC
    READS SQL DATA
BEGIN
    -- Tarif journalier (paramètre métier, documenté et centralisé ici).
    DECLARE c_tarif_jour DECIMAL(8,2) DEFAULT 0.50;
    DECLARE v_reference DATE;
    DECLARE v_jours_retard INT;

    -- Date de référence : la date de retour réelle, ou aujourd'hui si non rendu.
    SET v_reference = IFNULL(p_date_effective, CURRENT_DATE);

    -- DATEDIFF renvoie le nombre de jours entre deux dates (peut être négatif si
    -- rendu en avance). On borne à 0 : pas de « bonus » pour une avance.
    SET v_jours_retard = GREATEST(DATEDIFF(v_reference, p_date_prevue), 0);

    RETURN v_jours_retard * c_tarif_jour;
END //

-- -----------------------------------------------------------------------------
-- fn_nb_emprunts_actifs : nombre d'emprunts en cours ou en retard d'un membre.
--
-- Sert à faire respecter un QUOTA d'emprunts simultanés (voir pr_emprunter_livre).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_nb_emprunts_actifs //
CREATE FUNCTION fn_nb_emprunts_actifs(p_utilisateur_id BIGINT UNSIGNED)
    RETURNS INT
    READS SQL DATA
BEGIN
    DECLARE v_nb INT DEFAULT 0;

    SELECT COUNT(*)
        INTO v_nb
        FROM emprunts
        WHERE utilisateur_id = p_utilisateur_id
          AND statut IN ('en_cours', 'en_retard');

    RETURN v_nb;
END //

DELIMITER ;
