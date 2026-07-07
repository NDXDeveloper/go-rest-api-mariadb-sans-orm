-- =============================================================================
-- 01_privileges.sql — Durcissement des droits (exécuté automatiquement au 1er démarrage)
-- -----------------------------------------------------------------------------
-- CONTEXTE
--
-- Avec Docker, l'image MariaDB a déjà :
--   - créé la base « bibliotheque » (variable MARIADB_DATABASE) ;
--   - créé l'utilisateur applicatif (variables MARIADB_USER / MARIADB_PASSWORD) ;
--   - accordé à cet utilisateur TOUS les droits sur la base (GRANT ALL).
--
-- « GRANT ALL » est trop permissif. Ce script applique le principe du MOINDRE
-- PRIVILÈGE : on retire tout, puis on ne redonne que le strict nécessaire.
--
-- REMARQUE : le nom d'utilisateur ci-dessous doit correspondre à la variable
-- BDD_UTILISATEUR de votre fichier .env (valeur par défaut : app_bibliotheque).
-- Si vous le changez, adaptez aussi ce fichier. Un nom d'utilisateur n'est pas
-- un secret ; le mot de passe, lui, reste dans l'environnement, jamais ici.
-- =============================================================================

USE bibliotheque;

-- -----------------------------------------------------------------------------
-- 0) COHÉRENCE DE COLLATION (défense en profondeur, indépendante du serveur)
--
-- On force la base en utf8mb4_unicode_ci. C'est CRUCIAL : sur un serveur MariaDB
-- 11.4+ dont la collation par défaut est « utf8mb4_uca1400_ai_ci » (par exemple
-- un service MariaDB en intégration continue, sans fichier de configuration monté),
-- les PARAMÈTRES des procédures stockées héritent de la collation de la base. S'ils
-- diffèrent de celle des tables (utf8mb4_unicode_ci), toute comparaison
-- « colonne = paramètre » échoue avec l'erreur « Illegal mix of collations », ce
-- qui casse les procédures (emprunt, statistiques...).
--
-- En fixant explicitement la collation de la base ICI, AVANT la création des
-- tables et des procédures, on garantit la cohérence quel que soit le réglage du
-- serveur (le fichier docker/mariadb/conf.d/charset.cnf reste la solution
-- privilégiée pour Docker, ceci en est le complément robuste).
-- -----------------------------------------------------------------------------
ALTER DATABASE bibliotheque CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 1) On repart d'une ardoise vierge : suppression de TOUS les privilèges hérités.
-- -----------------------------------------------------------------------------
REVOKE ALL PRIVILEGES ON bibliotheque.* FROM 'app_bibliotheque'@'%';

-- -----------------------------------------------------------------------------
-- 2) Attribution ciblée : uniquement ce dont l'API a besoin.
--
--   - SELECT/INSERT/UPDATE/DELETE : CRUD sur les tables et les vues ;
--   - EXECUTE                     : appel des procédures et fonctions stockées ;
--   - SHOW VIEW                   : introspection des vues (débogage).
--
-- Volontairement ABSENTS : DROP, ALTER, CREATE, GRANT, INDEX, REFERENCES...
-- Conséquence : même en cas d'injection SQL, l'attaquant ne peut ni détruire le
-- schéma, ni s'octroyer de nouveaux droits. Défense en profondeur.
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE, SHOW VIEW
    ON bibliotheque.*
    TO 'app_bibliotheque'@'%';

FLUSH PRIVILEGES;

-- -----------------------------------------------------------------------------
-- 3) Activation de l'ordonnanceur d'événements (voir sql/events).
--
-- Sans cette activation, les EVENTS existeraient mais ne se déclencheraient
-- jamais. Le conteneur est aussi lancé avec --event-scheduler=ON (docker-compose)
-- pour que le réglage persiste au redémarrage.
-- -----------------------------------------------------------------------------
SET GLOBAL event_scheduler = ON;
