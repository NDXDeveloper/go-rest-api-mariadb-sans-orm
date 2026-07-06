-- =============================================================================
-- V002__ajout_colonne_langue_par_defaut.sql — Exemple de migration incrémentale
-- -----------------------------------------------------------------------------
-- SCÉNARIO : la base tourne déjà en production. On souhaite ajouter une colonne
-- « edition » (numéro d'édition) à la table livres, sans perdre les données.
--
-- Une migration se veut :
--   - SÛRE      : ne détruit aucune donnée existante ;
--   - IDEMPOTENTE si possible : ré-exécutable sans erreur (IF NOT EXISTS) ;
--   - RÉVERSIBLE : on documente comment revenir en arrière (rollback).
--
-- MariaDB supporte « ADD COLUMN IF NOT EXISTS », ce qui rend la migration
-- rejouable sans planter si elle a déjà été appliquée.
-- =============================================================================

USE bibliotheque;

-- Ajout de la colonne avec une valeur par défaut : les lignes existantes
-- reçoivent automatiquement la valeur par défaut (1re édition).
ALTER TABLE livres
    ADD COLUMN IF NOT EXISTS edition SMALLINT UNSIGNED NOT NULL DEFAULT 1
    COMMENT 'Numéro d''édition de l''ouvrage'
    AFTER annee_publication;

-- -----------------------------------------------------------------------------
-- ROLLBACK (à exécuter manuellement pour annuler cette migration) :
--
--     ALTER TABLE livres DROP COLUMN IF EXISTS edition;
--
-- REMARQUE : ce projet n'utilise pas la colonne « edition » dans le code Go ;
-- elle sert uniquement d'exemple de migration. Vous pouvez donc l'appliquer et
-- la rétablir sans impact sur l'API.
-- -----------------------------------------------------------------------------
