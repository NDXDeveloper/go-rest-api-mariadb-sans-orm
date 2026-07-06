// Package database gère la connexion à MariaDB via le package standard
// database/sql et le pilote go-sql-driver/mysql.
//
// # Aucun ORM ici
//
// On utilise UNIQUEMENT database/sql : c'est la bibliothèque standard de Go pour
// dialoguer avec une base SQL. Le « pilote » (driver) mysql traduit les appels
// database/sql en protocole réseau MariaDB. Toutes les requêtes SQL sont écrites
// à la main dans les repositories : aucune génération automatique.
//
// # Le pool de connexions
//
// *sql.DB N'EST PAS une connexion unique : c'est un POOL de connexions géré
// automatiquement. On l'ouvre une fois au démarrage et on le partage (par
// injection) dans toute l'application. Ouvrir/fermer une connexion à chaque
// requête serait catastrophique en performance.
package database

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/exemple/api-bibliotheque/internal/config"
	"github.com/go-sql-driver/mysql"
)

// Connecter ouvre le pool de connexions vers MariaDB, le configure et vérifie
// qu'il répond (ping). Elle renvoie un *sql.DB prêt à l'emploi ou une erreur.
//
// IMPORTANT : sql.Open n'établit PAS réellement de connexion (il prépare juste
// le pool). C'est PingContext qui force une vraie connexion et permet de détecter
// tôt un problème (mauvais mot de passe, base injoignable...).
func Connecter(cfg config.BaseDeDonnees) (*sql.DB, error) {
	dsn := construireDSN(cfg)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("ouverture du pool MariaDB : %w", err)
	}

	configurerPool(db, cfg)

	// Vérification effective de la connexion, bornée par un délai : si la base
	// ne répond pas à temps, on échoue proprement plutôt que d'attendre indéfiniment.
	ctx, annuler := context.WithTimeout(context.Background(), cfg.DelaiConnexion)
	defer annuler()
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("connexion à MariaDB impossible (%s) : %w", cfg.Hote, err)
	}

	return db, nil
}

// construireDSN assemble la chaîne de connexion (« Data Source Name ») à partir
// de la configuration. On utilise le constructeur du pilote plutôt que de
// concaténer des chaînes à la main : c'est plus sûr (échappement) et lisible.
func construireDSN(cfg config.BaseDeDonnees) string {
	c := mysql.NewConfig()
	c.User = cfg.Utilisateur
	c.Passwd = cfg.MotDePasse
	c.Net = "tcp"
	c.Addr = fmt.Sprintf("%s:%d", cfg.Hote, cfg.Port)
	c.DBName = cfg.Nom

	// Collation cohérente avec celle du serveur et des tables (voir charset.cnf).
	// Évite les erreurs « Illegal mix of collations » dans les procédures.
	c.Collation = "utf8mb4_unicode_ci"

	// parseTime : indispensable pour que le pilote convertisse les colonnes
	// DATE/DATETIME/TIMESTAMP en time.Time (sinon on récupérerait des []byte).
	c.ParseTime = true
	// On raisonne en UTC côté serveur ET côté client : cohérence des horodatages.
	c.Loc = time.UTC

	// Délai d'établissement de la connexion TCP.
	c.Timeout = cfg.DelaiConnexion

	// SÉCURITÉ : on laisse interpolateParams à false (valeur par défaut). Les
	// paramètres « ? » sont alors envoyés séparément de la requête au serveur
	// (requêtes préparées côté serveur), ce qui neutralise les injections SQL.
	// On n'active PAS multiStatements : impossible d'empiler plusieurs requêtes
	// dans un même appel, réduisant encore la surface d'attaque par injection.

	return c.FormatDSN()
}

// configurerPool applique les réglages du pool de connexions.
//
// Ces réglages sont cruciaux en production :
//   - MaxOpenConns limite le nombre de connexions simultanées vers la base.
//     Trop haut : on sature MariaDB (max_connections). Trop bas : on crée un
//     goulet d'étranglement. On l'aligne en général sur la capacité de la base.
//   - MaxIdleConns garde quelques connexions ouvertes « au repos » pour éviter
//     le coût de réouverture. On le met égal à MaxOpenConns pour un pool réactif.
//   - ConnMaxLifetime recycle les connexions périodiquement : utile derrière un
//     équilibreur de charge ou face à un pare-feu qui coupe les connexions longues.
func configurerPool(db *sql.DB, cfg config.BaseDeDonnees) {
	db.SetMaxOpenConns(cfg.MaxConnexionsOuvertes)
	db.SetMaxIdleConns(cfg.MaxConnexionsInactives)
	db.SetConnMaxLifetime(cfg.DureeVieMaxConnexion)
	// On limite aussi le temps d'inactivité d'une connexion avant recyclage.
	db.SetConnMaxIdleTime(cfg.DureeVieMaxConnexion)
}

// Verifier effectue un ping borné dans le temps. On l'utilise dans la sonde de
// disponibilité (/ready) pour savoir si la base est joignable à l'instant T.
func Verifier(ctx context.Context, db *sql.DB) error {
	return db.PingContext(ctx)
}
