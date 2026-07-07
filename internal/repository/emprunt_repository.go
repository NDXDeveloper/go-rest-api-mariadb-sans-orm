package repository

import (
	"context"
	"database/sql"
	"errors"

	"github.com/exemple/api-bibliotheque/internal/apperreur"
	"github.com/exemple/api-bibliotheque/internal/database"
	"github.com/exemple/api-bibliotheque/internal/models"
)

// EmpruntRepository gère les accès SQL liés aux emprunts. Il illustre DEUX
// techniques avancées :
//
//   - Emprunter : appel d'une PROCÉDURE STOCKÉE avec paramètres OUT, via une
//     connexion dédiée et des variables de session ;
//   - Rendre    : une TRANSACTION écrite en Go (verrou FOR UPDATE, mise à jour de
//     deux tables, commit/rollback automatique).
type EmpruntRepository struct {
	db *sql.DB
}

// NouveauEmpruntRepository construit le repository avec sa dépendance.
func NouveauEmpruntRepository(db *sql.DB) *EmpruntRepository {
	return &EmpruntRepository{db: db}
}

// Emprunter appelle la procédure stockée pr_emprunter_livre.
//
// # Pourquoi une connexion dédiée (sql.Conn) ?
//
// La procédure renvoie ses résultats dans des VARIABLES DE SESSION (@emprunt_uuid,
// @code, @message). Or ces variables ne vivent que sur UNE connexion. Comme
// *sql.DB est un pool, deux requêtes successives peuvent emprunter des connexions
// différentes. On réserve donc une connexion avec db.Conn(), on l'utilise pour le
// CALL PUIS pour lire les variables, et on la libère. C'est le point subtil à
// retenir pour appeler une procédure à paramètres OUT depuis Go.
func (r *EmpruntRepository) Emprunter(ctx context.Context, utilisateurUUID, livreUUID string, dureeJours int) (string, error) {
	conn, err := r.db.Conn(ctx)
	if err != nil {
		return "", apperreur.Interne("réservation d'une connexion").AvecCause(err)
	}
	defer conn.Close() // rend la connexion au pool

	// 1) Appel de la procédure. Les 3 derniers arguments sont des variables de
	//    session qui recevront les valeurs de sortie.
	_, err = conn.ExecContext(ctx,
		"CALL pr_emprunter_livre(?, ?, ?, @emprunt_uuid, @code, @message)",
		utilisateurUUID, livreUUID, dureeJours)
	if err != nil {
		return "", apperreur.Interne("appel de la procédure d'emprunt").AvecCause(err)
	}

	// 2) Lecture des variables de session (sur la MÊME connexion).
	var empruntUUID sql.NullString
	var code int
	var message string
	if err := conn.QueryRowContext(ctx, "SELECT @emprunt_uuid, @code, @message").
		Scan(&empruntUUID, &code, &message); err != nil {
		return "", apperreur.Interne("lecture du résultat de la procédure").AvecCause(err)
	}

	// 3) Traduction du code de retour applicatif en erreur métier explicite.
	switch code {
	case 0:
		return empruntUUID.String, nil
	case 1:
		return "", apperreur.NonTrouve("Livre introuvable.")
	case 2:
		return "", apperreur.NonTrouve("Utilisateur introuvable ou inactif.")
	case 3:
		return "", apperreur.Conflit("Aucun exemplaire disponible actuellement.")
	case 4:
		return "", apperreur.Conflit(message) // quota atteint : message déjà rédigé
	default:
		return "", apperreur.Interne("échec de l'emprunt").AvecCause(errors.New(message))
	}
}

// Rendre enregistre le retour d'un livre au sein d'une TRANSACTION Go.
//
// Étapes (toutes annulées d'un bloc en cas d'erreur, grâce à EnTransaction) :
//  1. verrouiller la ligne d'emprunt (SELECT ... FOR UPDATE) pour éviter deux
//     retours concurrents ;
//  2. vérifier que l'emprunt est encore actif ;
//  3. calculer la pénalité via la FONCTION SQL fn_calculer_penalite ;
//  4. passer l'emprunt à « rendu » ;
//  5. réincrémenter le stock du livre.
//
// Les étapes 4 et 5 touchent DEUX tables : c'est le cas d'école de la transaction
// (soit tout réussit, soit rien n'est modifié).
func (r *EmpruntRepository) Rendre(ctx context.Context, empruntUUID string) (float64, error) {
	var penalite float64

	err := database.EnTransaction(ctx, r.db, func(tx *sql.Tx) error {
		// 1) Verrou + lecture de l'état courant.
		var empruntID, livreID int64
		var statut string
		var datePrevue sql.NullTime
		ligne := tx.QueryRowContext(ctx,
			`SELECT id, livre_id, statut, date_retour_prevue FROM emprunts WHERE uuid = ? FOR UPDATE`,
			empruntUUID)
		if err := ligne.Scan(&empruntID, &livreID, &statut, &datePrevue); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return apperreur.NonTrouve("Emprunt introuvable.")
			}
			return apperreur.Interne("lecture de l'emprunt").AvecCause(err)
		}

		// 2) Un emprunt déjà rendu ne peut pas l'être une seconde fois.
		if statut == string(models.StatutRendu) {
			return apperreur.Conflit("Cet emprunt a déjà été rendu.")
		}

		// 3) Calcul de la pénalité par la fonction stockée (cohérence avec les vues).
		if err := tx.QueryRowContext(ctx,
			`SELECT fn_calculer_penalite(?, CURRENT_DATE)`, datePrevue).Scan(&penalite); err != nil {
			return apperreur.Interne("calcul de la pénalité").AvecCause(err)
		}

		// 4) Clôture de l'emprunt.
		if _, err := tx.ExecContext(ctx,
			`UPDATE emprunts SET statut = 'rendu', date_retour_effective = CURRENT_DATE, penalite = ? WHERE id = ?`,
			penalite, empruntID); err != nil {
			return apperreur.Interne("mise à jour de l'emprunt").AvecCause(err)
		}

		// 5) Retour de l'exemplaire dans le stock.
		if _, err := tx.ExecContext(ctx,
			`UPDATE livres SET exemplaires_disponibles = exemplaires_disponibles + 1 WHERE id = ?`,
			livreID); err != nil {
			return apperreur.Interne("réincrémentation du stock").AvecCause(err)
		}
		return nil // -> COMMIT
	})

	return penalite, err
}

// colonnesEmprunt liste les colonnes d'un emprunt enrichi (jointures).
const requeteBaseEmprunt = `
	SELECT e.id, e.uuid, e.date_emprunt, e.date_retour_prevue, e.date_retour_effective,
	       e.statut, e.penalite, e.cree_le, e.modifie_le,
	       u.uuid, CONCAT_WS(' ', u.prenom, u.nom), l.uuid, l.titre
	FROM emprunts e
	    INNER JOIN utilisateurs u ON u.id = e.utilisateur_id
	    INNER JOIN livres       l ON l.id = e.livre_id`

func scannerEmprunt(ligne ligneScannable) (*models.Emprunt, error) {
	var e models.Emprunt
	err := ligne.Scan(
		&e.ID, &e.UUID, &e.DateEmprunt, &e.DateRetourPrevue, &e.DateRetourEffective,
		&e.Statut, &e.Penalite, &e.CreeLe, &e.ModifieLe,
		&e.UtilisateurUUID, &e.UtilisateurNomComplet, &e.LivreUUID, &e.LivreTitre,
	)
	if err != nil {
		return nil, err
	}
	return &e, nil
}

// ParUUID récupère un emprunt enrichi (utilisateur + livre) par identifiant public.
func (r *EmpruntRepository) ParUUID(ctx context.Context, uuid string) (*models.Emprunt, error) {
	e, err := scannerEmprunt(r.db.QueryRowContext(ctx, requeteBaseEmprunt+` WHERE e.uuid = ?`, uuid))
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, apperreur.NonTrouve("Emprunt introuvable.")
		}
		return nil, apperreur.Interne("lecture de l'emprunt").AvecCause(err)
	}
	return e, nil
}

// Lister renvoie une page d'emprunts avec filtres par statut et par utilisateur.
// Si utilisateurUUID est non vide, on restreint aux emprunts de cet utilisateur
// (utilisé quand un membre consulte SES propres emprunts).
func (r *EmpruntRepository) Lister(ctx context.Context, utilisateurUUID string, params models.ParametresListe) ([]models.Emprunt, int, error) {
	var conditions constructeurConditions
	if utilisateurUUID != "" {
		conditions.ajouter("u.uuid = ?", utilisateurUUID)
	}
	if statut := params.Filtres["statut"]; statut != "" {
		conditions.ajouter("e.statut = ?", statut)
	}
	where := conditions.clauseWHERE()

	// Comptage (avec les mêmes jointures pour pouvoir filtrer par u.uuid).
	compte := `SELECT COUNT(*) FROM emprunts e
		INNER JOIN utilisateurs u ON u.id = e.utilisateur_id
		INNER JOIN livres l ON l.id = e.livre_id ` + where
	var total int
	if err := r.db.QueryRowContext(ctx, compte, conditions.args...).Scan(&total); err != nil {
		return nil, 0, apperreur.Interne("comptage des emprunts").AvecCause(err)
	}
	if total == 0 {
		return []models.Emprunt{}, 0, nil
	}

	// Tri : on préfixe la colonne par « e. » pour lever toute ambiguïté de jointure.
	triPagination, argsPagination := clauseTriEtPagination(params, "e.date_emprunt")
	//nolint:gosec // G202 : concaténation sûre — 'where' n'utilise que des '?' et 'triPagination' une colonne validée par liste blanche.
	requete := requeteBaseEmprunt + " " + where + triPagination
	lignes, err := r.db.QueryContext(ctx, requete, append(conditions.args, argsPagination...)...)
	if err != nil {
		return nil, 0, apperreur.Interne("liste des emprunts").AvecCause(err)
	}
	defer lignes.Close()

	emprunts := make([]models.Emprunt, 0, params.Taille)
	for lignes.Next() {
		e, err := scannerEmprunt(lignes)
		if err != nil {
			return nil, 0, apperreur.Interne("lecture d'une ligne emprunt").AvecCause(err)
		}
		emprunts = append(emprunts, *e)
	}
	if err := lignes.Err(); err != nil {
		return nil, 0, apperreur.Interne("parcours des emprunts").AvecCause(err)
	}
	return emprunts, total, nil
}

// StatistiquesUtilisateur appelle la procédure pr_statistiques_utilisateur, qui
// renvoie QUATRE valeurs via des paramètres OUT (même technique que Emprunter).
func (r *EmpruntRepository) StatistiquesUtilisateur(ctx context.Context, utilisateurUUID string) (models.StatistiquesUtilisateur, error) {
	var stats models.StatistiquesUtilisateur

	conn, err := r.db.Conn(ctx)
	if err != nil {
		return stats, apperreur.Interne("réservation d'une connexion").AvecCause(err)
	}
	defer conn.Close()

	if _, err := conn.ExecContext(ctx,
		"CALL pr_statistiques_utilisateur(?, @nb_total, @nb_en_cours, @nb_en_retard, @penalites)",
		utilisateurUUID); err != nil {
		return stats, apperreur.Interne("appel des statistiques utilisateur").AvecCause(err)
	}
	if err := conn.QueryRowContext(ctx, "SELECT @nb_total, @nb_en_cours, @nb_en_retard, @penalites").
		Scan(&stats.NbTotal, &stats.NbEnCours, &stats.NbEnRetard, &stats.TotalPenalites); err != nil {
		return stats, apperreur.Interne("lecture des statistiques utilisateur").AvecCause(err)
	}
	return stats, nil
}
