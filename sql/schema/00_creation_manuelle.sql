-- =============================================================================
-- 00_creation_manuelle.sql
-- -----------------------------------------------------------------------------
-- OBJECTIF PÉDAGOGIQUE
--
-- Ce fichier montre, PAS À PAS, comment créer « à la main » la base de données
-- et son utilisateur applicatif, comme si vous n'utilisiez pas Docker.
--
-- ATTENTION : ce script est DESTRUCTIF (il commence par DROP DATABASE). Il n'est
-- donc PAS exécuté automatiquement au démarrage du conteneur Docker. Avec Docker,
-- c'est l'image MariaDB qui crée la base et l'utilisateur à partir des variables
-- d'environnement (voir docker-compose.yml), puis les scripts 01 à 09 se
-- chargent du schéma et des données.
--
-- Vous pouvez exécuter ce fichier manuellement pour comprendre le cycle complet :
--
--     mariadb -u root -p < sql/schema/00_creation_manuelle.sql
--
-- Chaque instruction est expliquée : ce que l'on fait, pourquoi, et les pièges.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) SUPPRESSION DE L'EXISTANT
--
-- « IF EXISTS » évite une erreur si la base n'existe pas encore : le script
-- reste ainsi rejouable (idempotent) sans planter au premier lancement.
--
-- PIÈGE : DROP DATABASE supprime DÉFINITIVEMENT toutes les données. À ne jamais
-- exécuter en production sans sauvegarde. On ne l'utilise ici que pour repartir
-- d'un état propre en environnement de formation/développement.
-- -----------------------------------------------------------------------------
DROP DATABASE IF EXISTS bibliotheque;

-- -----------------------------------------------------------------------------
-- 2) CRÉATION DE LA BASE
--
-- On force le jeu de caractères utf8mb4 (vrai UTF-8 sur 4 octets, gère les
-- accents ET les émojis) et une collation « unicode_ci » (comparaison insensible
-- à la casse et aux accents, adaptée au français).
--
-- PIÈGE HISTORIQUE : l'ancien jeu « utf8 » de MySQL/MariaDB ne stocke que 3 octets
-- et ne gère pas tous les caractères. Toujours préférer utf8mb4.
-- -----------------------------------------------------------------------------
CREATE DATABASE bibliotheque
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 3) CRÉATION DE L'UTILISATEUR APPLICATIF
--
-- Principe de SÉCURITÉ fondamental : l'application NE se connecte JAMAIS en root.
-- On crée un utilisateur dédié, au périmètre limité à la seule base bibliotheque.
--
-- '%' signifie « depuis n'importe quel hôte » : pratique avec Docker où le nom
-- d'hôte du conteneur applicatif est imprévisible. En production sur un réseau
-- maîtrisé, on restreindrait à un hôte/sous-réseau précis.
--
-- Le mot de passe ci-dessous est un EXEMPLE de développement. En condition réelle,
-- il provient d'un secret/variable d'environnement, jamais d'un fichier versionné.
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'app_bibliotheque'@'%'
    IDENTIFIED BY 'motdepasse_app_dev';

-- -----------------------------------------------------------------------------
-- 4) ATTRIBUTION DES PRIVILÈGES (principe du MOINDRE PRIVILÈGE)
--
-- On n'accorde QUE ce dont l'application a besoin :
--   - SELECT/INSERT/UPDATE/DELETE : les opérations CRUD sur les tables/vues ;
--   - EXECUTE : pour appeler les procédures et fonctions stockées ;
--   - SHOW VIEW : confort de débogage sur les vues.
--
-- On N'accorde PAS : DROP, ALTER, CREATE, GRANT... Ainsi, même en cas
-- d'injection SQL réussie, l'attaquant ne pourrait pas supprimer une table ni
-- créer un nouvel utilisateur. C'est une défense en profondeur essentielle.
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE, SHOW VIEW
    ON bibliotheque.*
    TO 'app_bibliotheque'@'%';

-- -----------------------------------------------------------------------------
-- 5) EXEMPLE DE REVOKE
--
-- Illustration : imaginons qu'on ait accordé trop de droits par erreur. REVOKE
-- permet de les retirer. Ici, on s'assure explicitement que l'application ne
-- peut pas modifier la structure (au cas où un GRANT ALL traînerait).
--
-- (Ces REVOKE sont sans effet si le privilège n'était pas accordé : c'est normal
-- et sans danger.)
-- -----------------------------------------------------------------------------
REVOKE DROP, ALTER, CREATE, INDEX, REFERENCES
    ON bibliotheque.*
    FROM 'app_bibliotheque'@'%';

-- -----------------------------------------------------------------------------
-- 6) UTILISATEUR EN LECTURE SEULE (exemple pour des besoins d'analyse/reporting)
--
-- On crée un second compte qui ne peut QUE lire les données. Utile pour brancher
-- un outil de statistiques sans risque d'altération.
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'lecteur_bibliotheque'@'%'
    IDENTIFIED BY 'motdepasse_lecteur_dev';

GRANT SELECT ON bibliotheque.* TO 'lecteur_bibliotheque'@'%';

-- -----------------------------------------------------------------------------
-- 7) APPLICATION DES CHANGEMENTS
--
-- FLUSH PRIVILEGES recharge les tables de droits. Nécessaire surtout après des
-- modifications directes des tables système ; après GRANT/REVOKE, MariaDB
-- recharge en général automatiquement, mais on l'appelle par prudence.
-- -----------------------------------------------------------------------------
FLUSH PRIVILEGES;

-- -----------------------------------------------------------------------------
-- 8) ACTIVATION DE L'ORDONNANCEUR D'ÉVÉNEMENTS
--
-- Les EVENTS (tâches planifiées côté base) ne s'exécutent que si l'ordonnanceur
-- est actif. On l'active globalement. En complément, le conteneur est lancé avec
-- l'option serveur --event-scheduler=ON (voir docker-compose.yml) pour que ce
-- réglage survive à un redémarrage.
-- -----------------------------------------------------------------------------
SET GLOBAL event_scheduler = ON;

-- On bascule sur la base fraîchement créée pour la suite (tables, etc.).
USE bibliotheque;
