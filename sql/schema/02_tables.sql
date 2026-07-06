-- =============================================================================
-- 02_tables.sql — Création de toutes les tables du domaine « Bibliothèque »
-- -----------------------------------------------------------------------------
-- MODÈLE DE DONNÉES (relations principales) :
--
--   auteurs 1 ───< livres >─── 1 categories
--                    │
--                    │ 1
--                    ^
--                    │ N
--   utilisateurs 1 ──< emprunts
--
--   utilisateurs 1 ──< jetons_rafraichissement
--   (tables techniques : journal_audit, emprunts_archive, statistiques_quotidiennes)
--
-- CONVENTIONS APPLIQUÉES PARTOUT :
--   - Clé primaire technique « id » BIGINT AUTO_INCREMENT (jamais exposée à l'API).
--   - Identifiant public « uuid » CHAR(36) UNIQUE (exposé à la place de l'id, pour
--     éviter l'énumération des ressources / faille IDOR).
--   - Horodatage « cree_le » / « modifie_le » automatiques.
--   - Moteur InnoDB (transactions, clés étrangères) et charset utf8mb4.
-- =============================================================================

USE bibliotheque;

-- Sécurité d'exécution : on désactive temporairement les vérifications de clés
-- étrangères pour pouvoir (ré)exécuter le script quel que soit l'ordre, puis on
-- les réactive. En init Docker c'est inutile (base vierge) mais cela rend le
-- script rejouable manuellement sans erreur.
SET FOREIGN_KEY_CHECKS = 0;

-- -----------------------------------------------------------------------------
-- TABLE utilisateurs
-- Comptes de l'application (authentification, rôles, suppression logique).
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS utilisateurs;
CREATE TABLE utilisateurs (
    -- Clé technique : BIGINT UNSIGNED AUTO_INCREMENT. UNSIGNED car un identifiant
    -- n'est jamais négatif, ce qui double la plage de valeurs positives.
    id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    -- Identifiant public non devinable. Rempli par le trigger BEFORE INSERT s'il
    -- n'est pas fourni (voir 07_triggers.sql).
    uuid              CHAR(36)        NOT NULL,

    -- 254 = longueur maximale d'une adresse e-mail selon la RFC 5321.
    email             VARCHAR(254)    NOT NULL,

    -- On stocke le HACHÉ bcrypt (jamais le mot de passe en clair). 255 caractères
    -- suffisent largement (un hash bcrypt fait 60 caractères).
    mot_de_passe_hash VARCHAR(255)    NOT NULL,

    nom               VARCHAR(100)    NOT NULL,
    prenom            VARCHAR(100)    NOT NULL,

    -- ENUM = liste fermée de valeurs. La base refuse toute autre valeur : c'est
    -- une contrainte d'intégrité « gratuite » et lisible.
    role              ENUM('admin','bibliothecaire','membre') NOT NULL DEFAULT 'membre',

    -- BOOLEAN est un alias de TINYINT(1) en MariaDB. Un compte inactif ne peut
    -- pas se connecter (vérifié côté application).
    actif             BOOLEAN         NOT NULL DEFAULT TRUE,

    cree_le           TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- ON UPDATE CURRENT_TIMESTAMP : MariaDB met à jour ce champ automatiquement
    -- à chaque modification de la ligne. Pratique et fiable.
    modifie_le        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- Suppression LOGIQUE : au lieu d'effacer la ligne (DELETE physique), on
    -- horodate sa « disparition ». Les données restent pour l'historique/l'audit.
    -- NULL = actif ; non NULL = supprimé.
    supprime_le       TIMESTAMP       NULL DEFAULT NULL,

    PRIMARY KEY (id),

    -- Contraintes d'UNICITÉ : deux comptes ne peuvent partager le même uuid ni
    -- le même e-mail. La base garantit cette règle même en cas de concurrence.
    UNIQUE KEY uq_utilisateurs_uuid  (uuid),
    UNIQUE KEY uq_utilisateurs_email (email),

    -- Contrainte CHECK : filet de sécurité sur la forme de l'e-mail. Le motif
    -- '_%@_%.__%' impose : au moins 1 caractère, un « @ », au moins 1 caractère,
    -- un « . » puis au moins 2 caractères (le TLD). La validation fine est faite
    -- côté Go ; ceci n'est qu'une défense en profondeur.
    CONSTRAINT chk_utilisateurs_email CHECK (email LIKE '_%@_%.__%'),

    -- INDEX simples pour accélérer les filtres fréquents.
    KEY idx_utilisateurs_role        (role),
    KEY idx_utilisateurs_supprime_le (supprime_le)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Comptes applicatifs (authentification, rôles, suppression logique)';

-- -----------------------------------------------------------------------------
-- TABLE categories
-- Regroupement thématique des livres (Roman, Histoire, Informatique...).
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS categories;
CREATE TABLE categories (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid        CHAR(36)        NOT NULL,
    nom         VARCHAR(100)    NOT NULL,
    description VARCHAR(500)    NOT NULL DEFAULT '',
    cree_le     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modifie_le  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_categories_uuid (uuid),
    -- Le nom d'une catégorie est unique (pas deux fois « Roman »).
    UNIQUE KEY uq_categories_nom  (nom)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Catégories thématiques des livres';

-- -----------------------------------------------------------------------------
-- TABLE auteurs
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS auteurs;
CREATE TABLE auteurs (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid           CHAR(36)        NOT NULL,
    nom            VARCHAR(100)    NOT NULL,
    prenom         VARCHAR(100)    NOT NULL DEFAULT '',
    nationalite    VARCHAR(100)    NOT NULL DEFAULT '',
    -- DATE (sans heure). NULL autorisé : la date de naissance peut être inconnue.
    date_naissance DATE            NULL DEFAULT NULL,
    biographie     TEXT            NULL,
    cree_le        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modifie_le     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_auteurs_uuid (uuid),
    -- INDEX COMPOSÉ (nom, prenom) : accélère la recherche/tri par nom complet.
    -- L'ordre des colonnes compte : cet index sert les requêtes filtrant sur
    -- « nom » seul, ou sur « nom » ET « prenom », mais pas sur « prenom » seul.
    KEY idx_auteurs_nom_prenom (nom, prenom)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Auteurs des ouvrages';

-- -----------------------------------------------------------------------------
-- TABLE livres
-- Catalogue. Porte les clés étrangères vers auteurs et categories, ainsi que la
-- gestion du stock (nombre_exemplaires / exemplaires_disponibles).
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS livres;
CREATE TABLE livres (
    id                      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid                    CHAR(36)        NOT NULL,
    titre                   VARCHAR(255)    NOT NULL,
    -- ISBN-13 stocké sous forme canonique (13 chiffres, sans tirets).
    isbn                    CHAR(13)        NOT NULL,

    -- Clés étrangères (voir contraintes plus bas).
    auteur_id               BIGINT UNSIGNED NOT NULL,
    categorie_id            BIGINT UNSIGNED NOT NULL,

    annee_publication       SMALLINT UNSIGNED NOT NULL,

    -- Gestion du stock. exemplaires_disponibles varie à chaque emprunt/retour.
    nombre_exemplaires      INT UNSIGNED    NOT NULL DEFAULT 1,
    exemplaires_disponibles INT UNSIGNED    NOT NULL DEFAULT 1,

    resume                  TEXT            NULL,
    -- DECIMAL(8,2) : montant exact (pas de flottant) jusqu'à 999 999.99.
    prix                    DECIMAL(8,2)    NOT NULL DEFAULT 0.00,
    langue                  VARCHAR(50)     NOT NULL DEFAULT 'français',

    cree_le                 TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modifie_le              TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    supprime_le             TIMESTAMP       NULL DEFAULT NULL,

    PRIMARY KEY (id),
    UNIQUE KEY uq_livres_uuid (uuid),
    UNIQUE KEY uq_livres_isbn (isbn),

    -- CLÉS ÉTRANGÈRES : garantissent l'intégrité référentielle.
    --   ON DELETE RESTRICT : on refuse de supprimer un auteur/une catégorie
    --     encore référencé par un livre (évite les livres « orphelins »).
    --   ON UPDATE CASCADE : si l'id parent changeait, il serait répercuté (rare
    --     car les id sont stables, mais c'est la bonne pratique par défaut).
    CONSTRAINT fk_livres_auteur
        FOREIGN KEY (auteur_id)    REFERENCES auteurs(id)    ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_livres_categorie
        FOREIGN KEY (categorie_id) REFERENCES categories(id) ON DELETE RESTRICT ON UPDATE CASCADE,

    -- CONTRAINTES CHECK : invariants métier garantis par la base.
    CONSTRAINT chk_livres_stock CHECK (exemplaires_disponibles <= nombre_exemplaires),
    CONSTRAINT chk_livres_annee CHECK (annee_publication BETWEEN 1400 AND 2200),
    CONSTRAINT chk_livres_prix  CHECK (prix >= 0),

    -- INDEX simples et composé pour les recherches et jointures fréquentes.
    KEY idx_livres_titre     (titre),
    KEY idx_livres_auteur    (auteur_id),
    KEY idx_livres_categorie (categorie_id),
    KEY idx_livres_dispo     (exemplaires_disponibles)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Catalogue des ouvrages et gestion du stock';

-- -----------------------------------------------------------------------------
-- TABLE emprunts
-- Cœur métier : le prêt d'un livre à un utilisateur.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS emprunts;
CREATE TABLE emprunts (
    id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid                  CHAR(36)        NOT NULL,
    utilisateur_id        BIGINT UNSIGNED NOT NULL,
    livre_id              BIGINT UNSIGNED NOT NULL,

    -- DEFAULT (CURRENT_DATE) : date du jour si non précisée (expression par
    -- défaut, entre parenthèses, supportée par MariaDB).
    date_emprunt          DATE            NOT NULL DEFAULT (CURRENT_DATE),
    -- NULLable À DESSEIN : si l'appelant ne fournit pas la date de retour prévue,
    -- le trigger BEFORE INSERT la calcule (date_emprunt + 14 jours). Voir 07.
    date_retour_prevue    DATE            NULL DEFAULT NULL,
    -- NULL tant que le livre n'est pas rendu.
    date_retour_effective DATE            NULL DEFAULT NULL,

    statut                ENUM('en_cours','rendu','en_retard') NOT NULL DEFAULT 'en_cours',
    penalite              DECIMAL(8,2)    NOT NULL DEFAULT 0.00,

    cree_le               TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modifie_le            TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_emprunts_uuid (uuid),

    -- ON DELETE CASCADE pour l'utilisateur : si un compte est supprimé
    -- physiquement, ses emprunts partent avec (ici on privilégie plutôt la
    -- suppression logique, mais la contrainte protège l'intégrité).
    CONSTRAINT fk_emprunts_utilisateur
        FOREIGN KEY (utilisateur_id) REFERENCES utilisateurs(id) ON DELETE CASCADE ON UPDATE CASCADE,
    -- ON DELETE RESTRICT pour le livre : on ne supprime pas un livre encore emprunté.
    CONSTRAINT fk_emprunts_livre
        FOREIGN KEY (livre_id)       REFERENCES livres(id)       ON DELETE RESTRICT ON UPDATE CASCADE,

    CONSTRAINT chk_emprunts_dates    CHECK (date_retour_prevue >= date_emprunt),
    CONSTRAINT chk_emprunts_penalite CHECK (penalite >= 0),

    KEY idx_emprunts_utilisateur   (utilisateur_id),
    KEY idx_emprunts_livre         (livre_id),
    KEY idx_emprunts_statut        (statut),
    KEY idx_emprunts_retour_prevue (date_retour_prevue),
    -- INDEX COMPOSÉ : requête très fréquente « les emprunts actifs d'un membre ».
    KEY idx_emprunts_util_statut   (utilisateur_id, statut)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Prêts de livres aux utilisateurs';

-- -----------------------------------------------------------------------------
-- TABLE jetons_rafraichissement
-- Stocke les « refresh tokens » permettant de renouveler un jeton d'accès JWT.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS jetons_rafraichissement;
CREATE TABLE jetons_rafraichissement (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    utilisateur_id BIGINT UNSIGNED NOT NULL,

    -- On stocke le HACHÉ SHA-256 (64 caractères hex) du jeton, jamais le jeton
    -- lui-même. Ainsi, une fuite de la base ne révèle aucun refresh token
    -- réutilisable. Même philosophie que pour les mots de passe.
    jeton_hash     CHAR(64)        NOT NULL,
    expire_le      DATETIME        NOT NULL,
    revoque        BOOLEAN         NOT NULL DEFAULT FALSE,
    cree_le        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_jetons_hash (jeton_hash),
    CONSTRAINT fk_jetons_utilisateur
        FOREIGN KEY (utilisateur_id) REFERENCES utilisateurs(id) ON DELETE CASCADE ON UPDATE CASCADE,

    KEY idx_jetons_utilisateur (utilisateur_id),
    KEY idx_jetons_expire      (expire_le)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Jetons de rafraîchissement (hachés) pour renouveler les JWT';

-- -----------------------------------------------------------------------------
-- TABLE journal_audit
-- Table technique alimentée UNIQUEMENT par des triggers (voir 07_triggers.sql).
-- Trace qui a fait quoi, avant/après, sur les tables sensibles.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS journal_audit;
CREATE TABLE journal_audit (
    id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    table_concernee    VARCHAR(64)     NOT NULL,
    operation          ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    cle_enregistrement BIGINT UNSIGNED NULL,
    -- Type JSON natif : on y stocke une photo des valeurs avant/après.
    anciennes_valeurs  JSON            NULL,
    nouvelles_valeurs  JSON            NULL,
    -- Compte MariaDB à l'origine de l'opération (rempli par le trigger via CURRENT_USER()).
    acteur_sql         VARCHAR(128)    NOT NULL DEFAULT '',
    cree_le            TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    KEY idx_audit_table   (table_concernee),
    KEY idx_audit_cree_le (cree_le),
    -- INDEX COMPOSÉ pour filtrer « les opérations X sur la table Y ».
    KEY idx_audit_table_op (table_concernee, operation)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Journal d''audit alimenté par les triggers';

-- -----------------------------------------------------------------------------
-- TABLE emprunts_archive
-- Reçoit les emprunts anciens (rendus depuis plus d'un an), déplacés par un EVENT.
-- Pas de clés étrangères : ce sont des données historiques figées.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS emprunts_archive;
CREATE TABLE emprunts_archive (
    id                    BIGINT UNSIGNED NOT NULL,
    uuid                  CHAR(36)        NOT NULL,
    utilisateur_id        BIGINT UNSIGNED NOT NULL,
    livre_id              BIGINT UNSIGNED NOT NULL,
    date_emprunt          DATE            NOT NULL,
    date_retour_prevue    DATE            NOT NULL,
    date_retour_effective DATE            NULL,
    statut                VARCHAR(20)     NOT NULL,
    penalite              DECIMAL(8,2)    NOT NULL DEFAULT 0.00,
    cree_le               TIMESTAMP       NOT NULL,
    archive_le            TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    KEY idx_archive_utilisateur (utilisateur_id),
    KEY idx_archive_livre       (livre_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Archive des emprunts anciens (déplacés par un event de maintenance)';

-- -----------------------------------------------------------------------------
-- TABLE statistiques_quotidiennes
-- Instantané journalier calculé par un EVENT (voir 08_events.sql).
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS statistiques_quotidiennes;
CREATE TABLE statistiques_quotidiennes (
    id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    date_statistique       DATE            NOT NULL,
    nb_emprunts_actifs     INT UNSIGNED    NOT NULL DEFAULT 0,
    nb_emprunts_en_retard  INT UNSIGNED    NOT NULL DEFAULT 0,
    nb_livres              INT UNSIGNED    NOT NULL DEFAULT 0,
    nb_exemplaires_dispo   INT UNSIGNED    NOT NULL DEFAULT 0,
    nb_utilisateurs_actifs INT UNSIGNED    NOT NULL DEFAULT 0,
    cree_le                TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    -- Une seule ligne de statistiques par jour (l'event fait un « upsert »).
    UNIQUE KEY uq_stats_date (date_statistique)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Statistiques agrégées calculées quotidiennement par un event';

-- Réactivation des vérifications de clés étrangères.
SET FOREIGN_KEY_CHECKS = 1;
