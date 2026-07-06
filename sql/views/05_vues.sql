-- =============================================================================
-- 05_vues.sql — Vues (requêtes nommées réutilisables)
-- -----------------------------------------------------------------------------
-- INTÉRÊT DES VUES
--
-- Une vue est une requête SELECT enregistrée sous un nom, que l'on interroge
-- ensuite comme une table. Avantages :
--   - on masque la complexité des jointures derrière un nom simple ;
--   - on centralise une règle de lecture (ex. « livre disponible ») pour éviter
--     de la réécrire partout ;
--   - on peut restreindre les colonnes exposées (sécurité/lisibilité).
--
-- Ce ne sont PAS des tables : une vue ne stocke rien, elle est recalculée à
-- chaque interrogation à partir des tables sous-jacentes.
-- =============================================================================

USE bibliotheque;

-- -----------------------------------------------------------------------------
-- vue_livres_details : le catalogue « prêt à afficher », enrichi du nom de
-- l'auteur, du nom de la catégorie et d'un indicateur de disponibilité.
--
-- On exclut les livres supprimés logiquement (supprime_le IS NULL).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vue_livres_details AS
SELECT
    l.id,
    l.uuid,
    l.titre,
    l.isbn,
    l.annee_publication,
    l.nombre_exemplaires,
    l.exemplaires_disponibles,
    -- Appel de notre fonction stockée : cohérence garantie avec le reste du code.
    fn_est_disponible(l.id)                       AS disponible,
    l.prix,
    l.langue,
    l.resume,
    a.uuid                                        AS auteur_uuid,
    CONCAT_WS(' ', a.prenom, a.nom)               AS auteur_nom_complet,
    c.uuid                                        AS categorie_uuid,
    c.nom                                         AS categorie_nom,
    l.cree_le,
    l.modifie_le
FROM livres l
    INNER JOIN auteurs    a ON a.id = l.auteur_id
    INNER JOIN categories c ON c.id = l.categorie_id
WHERE l.supprime_le IS NULL;

-- -----------------------------------------------------------------------------
-- vue_emprunts_en_cours : tous les emprunts non rendus (en_cours ou en_retard),
-- avec le nom de l'emprunteur et le titre du livre.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vue_emprunts_en_cours AS
SELECT
    e.id,
    e.uuid,
    e.date_emprunt,
    e.date_retour_prevue,
    e.statut,
    u.uuid                             AS utilisateur_uuid,
    CONCAT_WS(' ', u.prenom, u.nom)    AS utilisateur_nom_complet,
    u.email                            AS utilisateur_email,
    l.uuid                             AS livre_uuid,
    l.titre                            AS livre_titre
FROM emprunts e
    INNER JOIN utilisateurs u ON u.id = e.utilisateur_id
    INNER JOIN livres       l ON l.id = e.livre_id
WHERE e.statut IN ('en_cours', 'en_retard');

-- -----------------------------------------------------------------------------
-- vue_emprunts_en_retard : uniquement les emprunts en retard, avec la pénalité
-- courante calculée « à aujourd'hui » par la fonction fn_calculer_penalite, et
-- le nombre de jours de retard.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vue_emprunts_en_retard AS
SELECT
    e.id,
    e.uuid,
    e.date_emprunt,
    e.date_retour_prevue,
    DATEDIFF(CURRENT_DATE, e.date_retour_prevue)  AS jours_de_retard,
    fn_calculer_penalite(e.date_retour_prevue, NULL) AS penalite_courante,
    u.uuid                                        AS utilisateur_uuid,
    CONCAT_WS(' ', u.prenom, u.nom)               AS utilisateur_nom_complet,
    u.email                                       AS utilisateur_email,
    l.uuid                                        AS livre_uuid,
    l.titre                                       AS livre_titre
FROM emprunts e
    INNER JOIN utilisateurs u ON u.id = e.utilisateur_id
    INNER JOIN livres       l ON l.id = e.livre_id
WHERE e.statut = 'en_retard'
   OR (e.statut = 'en_cours' AND e.date_retour_prevue < CURRENT_DATE);

-- -----------------------------------------------------------------------------
-- vue_statistiques_livres : popularité de chaque livre (nombre total d'emprunts,
-- tous statuts confondus). Utile pour un tableau de bord.
--
-- LEFT JOIN pour inclure aussi les livres jamais empruntés (compte = 0).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vue_statistiques_livres AS
SELECT
    l.id,
    l.uuid,
    l.titre,
    COUNT(e.id)                                   AS nombre_emprunts_total,
    SUM(CASE WHEN e.statut IN ('en_cours','en_retard') THEN 1 ELSE 0 END) AS nombre_emprunts_actifs
FROM livres l
    LEFT JOIN emprunts e ON e.livre_id = l.id
WHERE l.supprime_le IS NULL
GROUP BY l.id, l.uuid, l.titre;
