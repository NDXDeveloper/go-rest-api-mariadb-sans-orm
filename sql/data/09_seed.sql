-- =============================================================================
-- 09_seed.sql — Jeu de données de démonstration
-- -----------------------------------------------------------------------------
-- OBJECTIF
--   Peupler la base avec des données réalistes et cohérentes pour pouvoir tester
--   l'API immédiatement après « docker compose up » : catégories, auteurs,
--   livres, utilisateurs et emprunts (dans divers statuts).
--
-- MOT DE PASSE DE DÉMONSTRATION
--   Tous les comptes ci-dessous partagent le mot de passe : MotDePasse123!
--   Le champ mot_de_passe_hash contient son haché bcrypt (coût 12). En pratique,
--   chaque utilisateur aurait un sel/haché distinct ; on réutilise le même ici
--   par simplicité de démonstration.
--
-- IDENTIFIANTS EXPLICITES
--   On insère des « id » explicites (1, 2, 3...) pour maîtriser les clés
--   étrangères entre tables. Les « uuid » sont générés par UUID().
--
-- REJOUABILITÉ
--   On vide d'abord les tables avec TRUNCATE (rapide, réinitialise l'AUTO_INCREMENT
--   et ne déclenche pas les triggers). FOREIGN_KEY_CHECKS=0 lève temporairement
--   le contrôle des clés étrangères le temps du nettoyage.
-- =============================================================================

USE bibliotheque;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE emprunts_archive;
TRUNCATE TABLE statistiques_quotidiennes;
TRUNCATE TABLE journal_audit;
TRUNCATE TABLE jetons_rafraichissement;
TRUNCATE TABLE emprunts;
TRUNCATE TABLE livres;
TRUNCATE TABLE auteurs;
TRUNCATE TABLE categories;
TRUNCATE TABLE utilisateurs;
SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------------------------------------------
-- CATÉGORIES
-- -----------------------------------------------------------------------------
INSERT INTO categories (id, uuid, nom, description) VALUES
    (1, UUID(), 'Roman',            'Œuvres de fiction narrative en prose'),
    (2, UUID(), 'Science-fiction',  'Anticipation, mondes imaginaires et technologies'),
    (3, UUID(), 'Policier',         'Enquêtes, thrillers et romans à suspense'),
    (4, UUID(), 'Histoire',         'Essais et récits historiques'),
    (5, UUID(), 'Informatique',     'Programmation, systèmes et réseaux'),
    (6, UUID(), 'Jeunesse',         'Ouvrages destinés au jeune public'),
    (7, UUID(), 'Poésie',           'Recueils de poèmes'),
    (8, UUID(), 'Biographie',       'Récits de vie et mémoires');

-- -----------------------------------------------------------------------------
-- AUTEURS
-- -----------------------------------------------------------------------------
INSERT INTO auteurs (id, uuid, nom, prenom, nationalite, date_naissance, biographie) VALUES
    (1,  UUID(), 'Hugo',            'Victor',      'française',    '1802-02-26', 'Écrivain majeur du romantisme français.'),
    (2,  UUID(), 'Verne',           'Jules',       'française',    '1828-02-08', 'Pionnier de la science-fiction et du roman d''aventures.'),
    (3,  UUID(), 'Christie',        'Agatha',      'britannique',  '1890-09-15', 'Reine du roman policier.'),
    (4,  UUID(), 'Asimov',          'Isaac',       'américaine',   '1920-01-02', 'Auteur prolifique de science-fiction.'),
    (5,  UUID(), 'Camus',           'Albert',      'française',    '1913-11-07', 'Écrivain et philosophe, prix Nobel 1957.'),
    (6,  UUID(), 'Orwell',          'George',      'britannique',  '1903-06-25', 'Auteur de récits politiques et dystopiques.'),
    (7,  UUID(), 'Saint-Exupéry',   'Antoine de',  'française',    '1900-06-29', 'Aviateur et écrivain.'),
    (8,  UUID(), 'Herbert',         'Frank',       'américaine',   '1920-10-08', 'Créateur du cycle de Dune.'),
    (9,  UUID(), 'Yourcenar',       'Marguerite',  'française',    '1903-06-08', 'Première femme élue à l''Académie française.'),
    (10, UUID(), 'Dostoïevski',     'Fiodor',      'russe',        '1821-11-11', 'Romancier russe majeur du XIXe siècle.'),
    (11, UUID(), 'Tolkien',         'J.R.R.',      'britannique',  '1892-01-03', 'Père de la fantasy moderne.'),
    (12, UUID(), 'de Beauvoir',     'Simone',      'française',    '1908-01-09', 'Philosophe et figure du féminisme.');

-- -----------------------------------------------------------------------------
-- LIVRES
--   exemplaires_disponibles est initialisé égal à nombre_exemplaires ; il sera
--   ajusté plus bas en fonction des emprunts actifs.
--   Les ISBN sont des ISBN-13 valides (clé de contrôle correcte).
-- -----------------------------------------------------------------------------
INSERT INTO livres (id, uuid, titre, isbn, auteur_id, categorie_id, annee_publication, nombre_exemplaires, exemplaires_disponibles, prix, langue, resume) VALUES
    (1,  UUID(), 'Les Misérables',                 '9782010000003', 1,  1, 1862, 4, 4, 12.90, 'français', 'Le destin de Jean Valjean dans la France du XIXe siècle.'),
    (2,  UUID(), 'Notre-Dame de Paris',            '9782010000010', 1,  1, 1831, 3, 3, 10.50, 'français', 'Quasimodo, Esmeralda et la cathédrale.'),
    (3,  UUID(), 'Vingt mille lieues sous les mers','9782010000027', 2,  2, 1870, 5, 5,  9.90, 'français', 'Le capitaine Nemo et le Nautilus.'),
    (4,  UUID(), 'Le Tour du monde en 80 jours',   '9782010000034', 2,  1, 1872, 4, 4,  8.90, 'français', 'Le pari de Phileas Fogg.'),
    (5,  UUID(), 'De la Terre à la Lune',          '9782010000041', 2,  2, 1865, 2, 2,  7.50, 'français', 'Un voyage spatial visionnaire.'),
    (6,  UUID(), 'Le Crime de l''Orient-Express',  '9782010000058', 3,  3, 1934, 3, 3, 11.00, 'français', 'Hercule Poirot mène l''enquête.'),
    (7,  UUID(), 'Dix petits nègres',              '9782010000065', 3,  3, 1939, 3, 3, 10.90, 'français', 'Dix inconnus sur une île.'),
    (8,  UUID(), 'Fondation',                       '9782010000072', 4,  2, 1951, 4, 4, 13.50, 'français', 'La psychohistoire et la chute d''un empire galactique.'),
    (9,  UUID(), 'Les Robots',                      '9782010000089', 4,  2, 1950, 3, 3, 12.00, 'français', 'Les trois lois de la robotique.'),
    (10, UUID(), 'L''Étranger',                     '9782010000096', 5,  1, 1942, 5, 5,  7.90, 'français', 'Meursault face à l''absurde.'),
    (11, UUID(), 'La Peste',                        '9782010000102', 5,  1, 1947, 4, 4,  9.20, 'français', 'Oran frappée par l''épidémie.'),
    (12, UUID(), '1984',                            '9782010000119', 6,  2, 1949, 6, 6, 10.00, 'français', 'Big Brother vous regarde.'),
    (13, UUID(), 'La Ferme des animaux',            '9782010000126', 6,  1, 1945, 4, 4,  8.50, 'français', 'Une fable politique.'),
    (14, UUID(), 'Le Petit Prince',                 '9782010000133', 7,  6, 1943, 8, 8,  6.90, 'français', 'Un aviateur rencontre un petit prince.'),
    (15, UUID(), 'Vol de nuit',                     '9782010000140', 7,  1, 1931, 2, 2,  7.20, 'français', 'L''aéropostale et le courage des pilotes.'),
    (16, UUID(), 'Dune',                            '9782010000157', 8,  2, 1965, 5, 5, 15.90, 'français', 'Paul Atréides sur la planète Arrakis.'),
    (17, UUID(), 'Le Messie de Dune',               '9782010000164', 8,  2, 1969, 3, 3, 14.50, 'français', 'La suite de l''épopée de Dune.'),
    (18, UUID(), 'Mémoires d''Hadrien',             '9782010000171', 9,  1, 1951, 3, 3, 11.90, 'français', 'Les mémoires imaginaires de l''empereur romain.'),
    (19, UUID(), 'Crime et Châtiment',              '9782010000188', 10, 1, 1866, 4, 4, 12.50, 'français', 'Raskolnikov et sa conscience.'),
    (20, UUID(), 'Les Frères Karamazov',            '9782010000195', 10, 1, 1880, 3, 3, 14.00, 'français', 'Une fresque familiale et philosophique.'),
    (21, UUID(), 'Le Seigneur des anneaux',         '9782010000201', 11, 2, 1954, 6, 6, 24.90, 'français', 'La quête de l''anneau unique.'),
    (22, UUID(), 'Le Hobbit',                        '9782010000218', 11, 6, 1937, 5, 5, 13.90, 'français', 'Les aventures de Bilbo.'),
    (23, UUID(), 'Le Deuxième Sexe',                '9782010000225', 12, 4, 1949, 2, 2, 16.50, 'français', 'Essai fondateur du féminisme.'),
    (24, UUID(), 'Le Programmeur pragmatique',      '9782010000232', 4,  5, 1999, 3, 3, 39.90, 'français', 'Bonnes pratiques du développement logiciel.'),
    (25, UUID(), 'Introduction aux algorithmes',    '9782010000249', 4,  5, 2009, 2, 2, 79.00, 'français', 'Référence sur les algorithmes.'),
    (26, UUID(), 'Le Langage Go',                   '9782010000256', 4,  5, 2015, 4, 4, 42.00, 'français', 'Guide du langage Go.'),
    (27, UUID(), 'Contes du soir',                  '9782010000263', 7,  6, 1998, 5, 5,  9.50, 'français', 'Recueil d''histoires pour enfants.'),
    (28, UUID(), 'Recueil de poèmes',               '9782010000270', 1,  7, 1856, 3, 3,  8.00, 'français', 'Sélection de poèmes du XIXe siècle.');

-- -----------------------------------------------------------------------------
-- UTILISATEURS
--   Rôles : 1 admin, 1 bibliothécaire, 6 membres. Mot de passe : MotDePasse123!
-- -----------------------------------------------------------------------------
INSERT INTO utilisateurs (id, uuid, email, mot_de_passe_hash, nom, prenom, role, actif) VALUES
    (1, UUID(), 'admin@bibliotheque.fr',          '$2a$12$yT9vOdQVzElpmOmuxIuQVedExe66QZ6GroshqHR5gkP4cAYA9I.CG', 'Martin',   'Alice',    'admin',          TRUE),
    (2, UUID(), 'bibliothecaire@bibliotheque.fr', '$2a$12$yT9vOdQVzElpmOmuxIuQVedExe66QZ6GroshqHR5gkP4cAYA9I.CG', 'Bernard',  'Bruno',    'bibliothecaire', TRUE),
    (3, UUID(), 'chloe.durand@exemple.fr',        '$2a$12$yT9vOdQVzElpmOmuxIuQVedExe66QZ6GroshqHR5gkP4cAYA9I.CG', 'Durand',   'Chloé',    'membre',         TRUE),
    (4, UUID(), 'david.petit@exemple.fr',         '$2a$12$yT9vOdQVzElpmOmuxIuQVedExe66QZ6GroshqHR5gkP4cAYA9I.CG', 'Petit',    'David',    'membre',         TRUE),
    (5, UUID(), 'emma.roux@exemple.fr',           '$2a$12$yT9vOdQVzElpmOmuxIuQVedExe66QZ6GroshqHR5gkP4cAYA9I.CG', 'Roux',     'Emma',     'membre',         TRUE),
    (6, UUID(), 'farid.benali@exemple.fr',        '$2a$12$yT9vOdQVzElpmOmuxIuQVedExe66QZ6GroshqHR5gkP4cAYA9I.CG', 'Benali',   'Farid',    'membre',         TRUE),
    (7, UUID(), 'gwen.leroy@exemple.fr',          '$2a$12$yT9vOdQVzElpmOmuxIuQVedExe66QZ6GroshqHR5gkP4cAYA9I.CG', 'Leroy',    'Gwendal',  'membre',         TRUE),
    (8, UUID(), 'hugo.moreau@exemple.fr',         '$2a$12$yT9vOdQVzElpmOmuxIuQVedExe66QZ6GroshqHR5gkP4cAYA9I.CG', 'Moreau',   'Hugo',     'membre',         FALSE);

-- -----------------------------------------------------------------------------
-- EMPRUNTS
--   Statuts variés pour illustrer l'API et les vues :
--     - 'rendu'    : rendus, certains avec pénalité de retard ;
--     - 'en_cours' : en cours, dans les délais ;
--     - 'en_retard': échéance dépassée, pénalité en cours.
--   Les dates sont relatives à la date du jour (CURRENT_DATE).
--   Certains laissent date_retour_prevue à NULL pour démontrer le trigger
--   BEFORE INSERT qui la calcule (date_emprunt + 14 jours).
-- -----------------------------------------------------------------------------
INSERT INTO emprunts (id, uuid, utilisateur_id, livre_id, date_emprunt, date_retour_prevue, date_retour_effective, statut, penalite) VALUES
    -- Emprunts rendus (historique)
    (1,  UUID(), 3, 1,  DATE_SUB(CURRENT_DATE, INTERVAL 40 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 26 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 28 DAY), 'rendu',     0.00),
    (2,  UUID(), 4, 10, DATE_SUB(CURRENT_DATE, INTERVAL 35 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 21 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 15 DAY), 'rendu',     3.00),
    (3,  UUID(), 5, 16, DATE_SUB(CURRENT_DATE, INTERVAL 50 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 36 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 40 DAY), 'rendu',     0.00),
    (4,  UUID(), 6, 12, DATE_SUB(CURRENT_DATE, INTERVAL 25 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 11 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 12 DAY), 'rendu',     0.00),
    -- Emprunts en cours (dans les délais)
    (5,  UUID(), 3, 21, DATE_SUB(CURRENT_DATE, INTERVAL 5  DAY), DATE_ADD(CURRENT_DATE, INTERVAL 9  DAY), NULL, 'en_cours', 0.00),
    (6,  UUID(), 4, 8,  DATE_SUB(CURRENT_DATE, INTERVAL 3  DAY), DATE_ADD(CURRENT_DATE, INTERVAL 11 DAY), NULL, 'en_cours', 0.00),
    (7,  UUID(), 5, 3,  DATE_SUB(CURRENT_DATE, INTERVAL 7  DAY), DATE_ADD(CURRENT_DATE, INTERVAL 7  DAY), NULL, 'en_cours', 0.00),
    (8,  UUID(), 7, 26, DATE_SUB(CURRENT_DATE, INTERVAL 2  DAY), NULL,                                    NULL, 'en_cours', 0.00),
    (9,  UUID(), 6, 14, DATE_SUB(CURRENT_DATE, INTERVAL 1  DAY), DATE_ADD(CURRENT_DATE, INTERVAL 13 DAY), NULL, 'en_cours', 0.00),
    -- Emprunts en retard (échéance dépassée)
    (10, UUID(), 4, 19, DATE_SUB(CURRENT_DATE, INTERVAL 30 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 16 DAY), NULL, 'en_retard', 8.00),
    (11, UUID(), 7, 6,  DATE_SUB(CURRENT_DATE, INTERVAL 28 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 14 DAY), NULL, 'en_retard', 7.00),
    (12, UUID(), 5, 1,  DATE_SUB(CURRENT_DATE, INTERVAL 20 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 6  DAY), NULL, 'en_retard', 3.00);

-- -----------------------------------------------------------------------------
-- SYNCHRONISATION DU STOCK
--   Pour chaque livre, exemplaires_disponibles = nombre_exemplaires moins le
--   nombre d'emprunts actifs (en cours ou en retard). Sous-requête corrélée.
-- -----------------------------------------------------------------------------
UPDATE livres l
SET l.exemplaires_disponibles = l.nombre_exemplaires - (
    SELECT COUNT(*)
    FROM emprunts e
    WHERE e.livre_id = l.id
      AND e.statut IN ('en_cours', 'en_retard')
);

-- -----------------------------------------------------------------------------
-- REMISE À NIVEAU DES SÉQUENCES AUTO_INCREMENT
--   Après des insertions à id explicites, on repositionne l'AUTO_INCREMENT
--   au-dessus du plus grand id pour éviter tout conflit lors des prochains INSERT.
-- -----------------------------------------------------------------------------
ALTER TABLE categories   AUTO_INCREMENT = 100;
ALTER TABLE auteurs      AUTO_INCREMENT = 100;
ALTER TABLE livres       AUTO_INCREMENT = 100;
ALTER TABLE utilisateurs AUTO_INCREMENT = 100;
ALTER TABLE emprunts     AUTO_INCREMENT = 100;
