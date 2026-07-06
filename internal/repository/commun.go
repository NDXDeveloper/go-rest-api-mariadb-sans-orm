// Package repository contient la couche d'accès aux données. C'est la SEULE
// couche autorisée à écrire du SQL. Les handlers et services n'en contiennent
// jamais : cette séparation garde le SQL centralisé, testable et auditable.
//
// # Principes appliqués dans TOUS les repositories
//
//  1. Requêtes PRÉPARÉES paramétrées : les valeurs passent par des « ? » et sont
//     envoyées séparément au serveur. C'est la parade n°1 contre l'injection SQL.
//     On ne concatène JAMAIS une valeur utilisateur dans une requête.
//
//  2. context.Context sur chaque appel : permet d'annuler une requête si le
//     client se déconnecte ou si un délai est dépassé (voir le middleware Timeout).
//
//  3. Traduction des erreurs SQL en erreurs métier (apperreur) : aucune erreur
//     technique brute ne remonte vers le client (pas de fuite d'information).
package repository

import (
	"database/sql"
	"strings"

	"github.com/exemple/api-bibliotheque/internal/models"
)

// dateVersChaine convertit une colonne DATE nullable (lue en sql.NullTime) vers
// un *string au format « AAAA-MM-JJ », ou nil si la valeur est NULL.
//
// Pourquoi ? Une colonne DATE seule (sans heure) est plus lisible en JSON sous la
// forme "1802-02-26" que "1802-02-26T00:00:00Z" (ce que donnerait un time.Time).
func dateVersChaine(valeur sql.NullTime) *string {
	if !valeur.Valid {
		return nil
	}
	s := valeur.Time.Format("2006-01-02")
	return &s
}

// argDate prépare une date facultative (*string) pour un paramètre SQL : renvoie
// la chaîne si elle est renseignée, sinon nil (qui devient NULL en base). Le
// pilote convertit automatiquement "AAAA-MM-JJ" en type DATE.
func argDate(valeur *string) any {
	if valeur == nil || *valeur == "" {
		return nil
	}
	return *valeur
}

// ligneScannable est satisfaite à la fois par *sql.Row (résultat d'une ligne) et
// *sql.Rows (curseur multi-lignes). Grâce à elle, on écrit UNE seule fonction de
// scan par entité, réutilisée pour « lire un » comme pour « lire plusieurs ».
type ligneScannable interface {
	Scan(destinations ...any) error
}

// constructeurConditions assemble progressivement la clause WHERE d'une requête
// de liste (filtres, recherche...) tout en collectant les arguments « ? »
// correspondants, dans le bon ordre.
//
// Il garantit que les valeurs restent des paramètres préparés : on n'insère
// jamais une valeur directement dans la chaîne SQL.
type constructeurConditions struct {
	conditions []string
	args       []any
}

// ajouter enregistre une condition SQL (avec ses « ? ») et ses arguments.
//
//	c.ajouter("email = ?", email)
//	c.ajouter("role IN (?, ?)", r1, r2)
func (c *constructeurConditions) ajouter(condition string, args ...any) {
	c.conditions = append(c.conditions, condition)
	c.args = append(c.args, args...)
}

// clauseWHERE renvoie « WHERE a AND b AND ... » ou une chaîne vide s'il n'y a
// aucune condition.
func (c *constructeurConditions) clauseWHERE() string {
	if len(c.conditions) == 0 {
		return ""
	}
	return "WHERE " + strings.Join(c.conditions, " AND ")
}

// clauseTriEtPagination construit la fin d'une requête de liste :
// « ORDER BY <colonne> <sens> LIMIT ? OFFSET ? ».
//
// SÉCURITÉ : params.ColonneTri est un nom de colonne DÉJÀ VALIDÉ contre une liste
// blanche par le handler (voir models.ParametresListe et le parsing HTTP). Il est
// donc sûr de l'interpoler ici. En dernier recours, si la colonne est vide, on
// applique un tri par défaut : jamais de valeur non maîtrisée dans « ORDER BY ».
//
// LIMIT et OFFSET, eux, restent des paramètres « ? » classiques.
func clauseTriEtPagination(params models.ParametresListe, colonneParDefaut string) (string, []any) {
	colonne := params.ColonneTri
	if colonne == "" {
		colonne = colonneParDefaut
	}
	sens := params.Ordre
	if sens != models.OrdreAsc && sens != models.OrdreDesc {
		sens = models.OrdreAsc
	}
	clause := " ORDER BY " + colonne + " " + sens + " LIMIT ? OFFSET ?"
	return clause, []any{params.Taille, params.Offset()}
}
