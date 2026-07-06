-- =============================================================================
-- 03_index.sql — Index additionnels (démonstration de CREATE INDEX)
-- -----------------------------------------------------------------------------
-- La plupart des index ont déjà été déclarés DANS les tables (02_tables.sql),
-- ce qui est la pratique recommandée (l'index est documenté au plus près de la
-- colonne). Ce fichier illustre la création d'index APRÈS coup, avec CREATE
-- INDEX, et introduit deux notions avancées : l'index composé « couvrant » et
-- l'index FULLTEXT.
--
-- RAPPEL — à quoi sert un index ?
--   Un index est une structure (arbre B) qui permet à la base de retrouver des
--   lignes sans parcourir toute la table. Il ACCÉLÈRE les lectures (WHERE, JOIN,
--   ORDER BY) mais RALENTIT légèrement les écritures (il faut le maintenir) et
--   occupe de l'espace. On indexe donc les colonnes réellement filtrées/triées,
--   pas toutes les colonnes.
--
--   Pour vérifier qu'un index est utilisé, préfixez votre requête par EXPLAIN :
--       EXPLAIN SELECT ... ;
--   et regardez les colonnes « type » (évitez « ALL » = scan complet) et « key ».
-- =============================================================================

USE bibliotheque;

-- -----------------------------------------------------------------------------
-- INDEX COMPOSÉ : lister les livres d'une catégorie, triés par titre.
--
-- L'ordre des colonnes (categorie_id d'abord, titre ensuite) est choisi pour la
-- requête « WHERE categorie_id = ? ORDER BY titre ». La base peut alors filtrer
-- ET trier en s'appuyant sur le seul index, sans tri supplémentaire coûteux.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_livres_categorie_titre
    ON livres (categorie_id, titre);

-- -----------------------------------------------------------------------------
-- INDEX COMPOSÉ pour l'EVENT de détection des retards.
--
-- L'event quotidien recherche « statut = 'en_cours' AND date_retour_prevue < ? ».
-- Cet index rend ce balayage efficace même avec des millions d'emprunts.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_emprunts_statut_retour
    ON emprunts (statut, date_retour_prevue);

-- -----------------------------------------------------------------------------
-- INDEX FULLTEXT : recherche plein texte sur le titre et le résumé.
--
-- Un index FULLTEXT permet des recherches en langage naturel via MATCH ... AGAINST,
-- bien plus pertinentes et rapides qu'un « LIKE '%mot%' » sur de gros volumes
-- (LIKE avec joker en tête ne peut PAS utiliser d'index B-arbre classique).
--
-- Exemple d'utilisation :
--   SELECT titre FROM livres
--   WHERE MATCH(titre, resume) AGAINST('aventure' IN NATURAL LANGUAGE MODE);
--
-- NB : dans ce projet, la recherche exposée par l'API reste volontairement en
-- LIKE (plus simple à comprendre) ; cet index est fourni pour montrer l'option
-- performante et vous permettre d'expérimenter.
-- -----------------------------------------------------------------------------
CREATE FULLTEXT INDEX ft_livres_recherche
    ON livres (titre, resume);

-- -----------------------------------------------------------------------------
-- Pour SUPPRIMER un index (exemple, à ne pas exécuter ici) :
--   DROP INDEX idx_livres_categorie_titre ON livres;
-- -----------------------------------------------------------------------------
