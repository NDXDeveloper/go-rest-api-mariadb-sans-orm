-- =============================================================================
-- 07_triggers.sql — Triggers (déclencheurs)
-- -----------------------------------------------------------------------------
-- QU'EST-CE QU'UN TRIGGER ?
--
-- Un trigger est un bloc de code exécuté AUTOMATIQUEMENT par la base lorsqu'un
-- événement survient sur une table (INSERT, UPDATE ou DELETE), soit AVANT
-- (BEFORE), soit APRÈS (AFTER) l'opération.
--
--   - BEFORE : idéal pour NORMALISER ou VALIDER une donnée avant écriture
--     (on peut modifier NEW.*). Ex. : générer un UUID, mettre un e-mail en
--     minuscules, refuser une opération avec SIGNAL.
--   - AFTER : idéal pour des EFFETS DE BORD une fois l'écriture confirmée
--     (on ne peut plus modifier NEW.*). Ex. : écrire une ligne d'audit.
--
-- Pseudo-lignes disponibles :
--   - NEW : la nouvelle version de la ligne (INSERT, UPDATE) ;
--   - OLD : l'ancienne version de la ligne (UPDATE, DELETE).
--
-- CHOIX D'ARCHITECTURE DE CE PROJET
--   Les triggers NE gèrent PAS le stock (décrément/incrément des exemplaires) :
--   cette logique métier vit dans la procédure d'emprunt et la transaction de
--   retour (côté Go), pour éviter tout double comptage. Ici, les triggers se
--   limitent à : générer des UUID, normaliser des champs, VALIDER des règles
--   (SIGNAL) et JOURNALISER les changements (table journal_audit).
--
-- PIÈGE CLASSIQUE : un trigger doit rester léger. Une logique lourde ou des
-- effets « invisibles » compliquent le débogage. On documente donc chaque trigger.
-- =============================================================================

USE bibliotheque;

DELIMITER //

-- =========================== TABLE utilisateurs ==============================

-- BEFORE INSERT : normalisation avant écriture.
--   - génère un UUID si l'application n'en a pas fourni ;
--   - met l'e-mail en minuscules et sans espaces superflus (unicité fiable).
DROP TRIGGER IF EXISTS trg_utilisateurs_avant_insert //
CREATE TRIGGER trg_utilisateurs_avant_insert
    BEFORE INSERT ON utilisateurs
    FOR EACH ROW
BEGIN
    IF NEW.uuid IS NULL OR NEW.uuid = '' THEN
        SET NEW.uuid = UUID();
    END IF;
    SET NEW.email = LOWER(TRIM(NEW.email));
END //

-- AFTER INSERT : trace la création dans le journal d'audit.
-- On n'enregistre JAMAIS le mot de passe haché dans l'audit (donnée sensible).
DROP TRIGGER IF EXISTS trg_utilisateurs_apres_insert //
CREATE TRIGGER trg_utilisateurs_apres_insert
    AFTER INSERT ON utilisateurs
    FOR EACH ROW
BEGIN
    INSERT INTO journal_audit (table_concernee, operation, cle_enregistrement, nouvelles_valeurs, acteur_sql)
    VALUES ('utilisateurs', 'INSERT', NEW.id,
            JSON_OBJECT('uuid', NEW.uuid, 'email', NEW.email, 'role', NEW.role, 'actif', NEW.actif),
            CURRENT_USER());
END //

-- AFTER UPDATE : trace la modification (photo avant/après), hors mot de passe.
DROP TRIGGER IF EXISTS trg_utilisateurs_apres_update //
CREATE TRIGGER trg_utilisateurs_apres_update
    AFTER UPDATE ON utilisateurs
    FOR EACH ROW
BEGIN
    INSERT INTO journal_audit (table_concernee, operation, cle_enregistrement, anciennes_valeurs, nouvelles_valeurs, acteur_sql)
    VALUES ('utilisateurs', 'UPDATE', NEW.id,
            JSON_OBJECT('email', OLD.email, 'role', OLD.role, 'actif', OLD.actif, 'supprime_le', OLD.supprime_le),
            JSON_OBJECT('email', NEW.email, 'role', NEW.role, 'actif', NEW.actif, 'supprime_le', NEW.supprime_le),
            CURRENT_USER());
END //

-- AFTER DELETE : trace la suppression PHYSIQUE (rare : on privilégie la
-- suppression logique via supprime_le, mais on audite quand même).
DROP TRIGGER IF EXISTS trg_utilisateurs_apres_delete //
CREATE TRIGGER trg_utilisateurs_apres_delete
    AFTER DELETE ON utilisateurs
    FOR EACH ROW
BEGIN
    INSERT INTO journal_audit (table_concernee, operation, cle_enregistrement, anciennes_valeurs, acteur_sql)
    VALUES ('utilisateurs', 'DELETE', OLD.id,
            JSON_OBJECT('uuid', OLD.uuid, 'email', OLD.email, 'role', OLD.role),
            CURRENT_USER());
END //

-- ============================== TABLE livres =================================

-- BEFORE INSERT : génère l'UUID et normalise l'ISBN (retrait des tirets/espaces).
DROP TRIGGER IF EXISTS trg_livres_avant_insert //
CREATE TRIGGER trg_livres_avant_insert
    BEFORE INSERT ON livres
    FOR EACH ROW
BEGIN
    IF NEW.uuid IS NULL OR NEW.uuid = '' THEN
        SET NEW.uuid = UUID();
    END IF;
    SET NEW.isbn = REPLACE(REPLACE(NEW.isbn, '-', ''), ' ', '');
END //

-- BEFORE UPDATE : VALIDATION métier avec SIGNAL.
--   On refuse qu'un ajustement de stock rende exemplaires_disponibles supérieur
--   au nombre total d'exemplaires. La contrainte CHECK le garantit déjà, mais le
--   trigger fournit un MESSAGE D'ERREUR MÉTIER clair (SIGNAL SQLSTATE '45000').
DROP TRIGGER IF EXISTS trg_livres_avant_update //
CREATE TRIGGER trg_livres_avant_update
    BEFORE UPDATE ON livres
    FOR EACH ROW
BEGIN
    IF NEW.exemplaires_disponibles > NEW.nombre_exemplaires THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Incohérence de stock : exemplaires disponibles > total.';
    END IF;
    SET NEW.isbn = REPLACE(REPLACE(NEW.isbn, '-', ''), ' ', '');
END //

-- AFTER UPDATE : audit des changements de stock/prix d'un livre.
DROP TRIGGER IF EXISTS trg_livres_apres_update //
CREATE TRIGGER trg_livres_apres_update
    AFTER UPDATE ON livres
    FOR EACH ROW
BEGIN
    INSERT INTO journal_audit (table_concernee, operation, cle_enregistrement, anciennes_valeurs, nouvelles_valeurs, acteur_sql)
    VALUES ('livres', 'UPDATE', NEW.id,
            JSON_OBJECT('titre', OLD.titre, 'exemplaires_disponibles', OLD.exemplaires_disponibles, 'prix', OLD.prix),
            JSON_OBJECT('titre', NEW.titre, 'exemplaires_disponibles', NEW.exemplaires_disponibles, 'prix', NEW.prix),
            CURRENT_USER());
END //

-- ============================= TABLE emprunts ================================

-- BEFORE INSERT : génère l'UUID et CALCULE une date de retour par défaut.
--   Si l'appelant n'a pas fourni date_retour_prevue (NULL), on la fixe à
--   date_emprunt + 14 jours. Bel exemple de valeur calculée par un trigger.
DROP TRIGGER IF EXISTS trg_emprunts_avant_insert //
CREATE TRIGGER trg_emprunts_avant_insert
    BEFORE INSERT ON emprunts
    FOR EACH ROW
BEGIN
    IF NEW.uuid IS NULL OR NEW.uuid = '' THEN
        SET NEW.uuid = UUID();
    END IF;
    IF NEW.date_retour_prevue IS NULL THEN
        SET NEW.date_retour_prevue = DATE_ADD(NEW.date_emprunt, INTERVAL 14 DAY);
    END IF;
END //

-- AFTER INSERT : audit de la création d'un emprunt.
DROP TRIGGER IF EXISTS trg_emprunts_apres_insert //
CREATE TRIGGER trg_emprunts_apres_insert
    AFTER INSERT ON emprunts
    FOR EACH ROW
BEGIN
    INSERT INTO journal_audit (table_concernee, operation, cle_enregistrement, nouvelles_valeurs, acteur_sql)
    VALUES ('emprunts', 'INSERT', NEW.id,
            JSON_OBJECT('uuid', NEW.uuid, 'utilisateur_id', NEW.utilisateur_id, 'livre_id', NEW.livre_id, 'statut', NEW.statut),
            CURRENT_USER());
END //

-- AFTER UPDATE : audit des changements de statut (ex. passage à « rendu »).
DROP TRIGGER IF EXISTS trg_emprunts_apres_update //
CREATE TRIGGER trg_emprunts_apres_update
    AFTER UPDATE ON emprunts
    FOR EACH ROW
BEGIN
    INSERT INTO journal_audit (table_concernee, operation, cle_enregistrement, anciennes_valeurs, nouvelles_valeurs, acteur_sql)
    VALUES ('emprunts', 'UPDATE', NEW.id,
            JSON_OBJECT('statut', OLD.statut, 'date_retour_effective', OLD.date_retour_effective, 'penalite', OLD.penalite),
            JSON_OBJECT('statut', NEW.statut, 'date_retour_effective', NEW.date_retour_effective, 'penalite', NEW.penalite),
            CURRENT_USER());
END //

-- BEFORE DELETE : RÈGLE MÉTIER — on interdit de supprimer un emprunt encore actif.
--   Un livre non rendu ne doit pas disparaître de l'historique. On bloque avec SIGNAL.
DROP TRIGGER IF EXISTS trg_emprunts_avant_delete //
CREATE TRIGGER trg_emprunts_avant_delete
    BEFORE DELETE ON emprunts
    FOR EACH ROW
BEGIN
    IF OLD.statut IN ('en_cours', 'en_retard') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Suppression interdite : cet emprunt est encore actif.';
    END IF;
END //

DELIMITER ;
