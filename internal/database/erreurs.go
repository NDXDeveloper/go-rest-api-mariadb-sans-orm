package database

import (
	"errors"

	"github.com/go-sql-driver/mysql"
)

// Codes d'erreur MariaDB/MySQL que l'on sait interpréter. Les traduire en
// concepts métier permet aux repositories de renvoyer une *apperreur.Erreur
// claire (409 Conflit, etc.) plutôt qu'une erreur technique brute.
//
// Référence : https://mariadb.com/kb/en/mariadb-error-codes/
const (
	codeDoublon           = 1062 // ER_DUP_ENTRY : violation d'une contrainte UNIQUE
	codeFKParentManquant  = 1452 // ER_NO_REFERENCED_ROW : FK vers une ligne inexistante
	codeFKEnfantExistant  = 1451 // ER_ROW_IS_REFERENCED : suppression bloquée par une FK
	codeSignalUtilisateur = 1644 // ER_SIGNAL_EXCEPTION : SIGNAL levé par un trigger/procédure
)

// commeMySQL tente de convertir une erreur en *mysql.MySQLError afin d'inspecter
// son code numérique. Renvoie (nil, false) si ce n'en est pas une.
func commeMySQL(err error) (*mysql.MySQLError, bool) {
	var e *mysql.MySQLError
	if errors.As(err, &e) {
		return e, true
	}
	return nil, false
}

// EstErreurDoublon indique si l'erreur provient d'une violation de contrainte
// UNIQUE (par exemple, un e-mail ou un ISBN déjà présent). Le repository peut
// alors renvoyer un 409 Conflit avec un message adapté.
func EstErreurDoublon(err error) bool {
	e, ok := commeMySQL(err)
	return ok && e.Number == codeDoublon
}

// EstErreurCleEtrangere indique si l'erreur provient d'une contrainte de clé
// étrangère : soit on référence un parent inexistant (auteur/catégorie), soit on
// tente de supprimer une ligne encore référencée.
func EstErreurCleEtrangere(err error) bool {
	e, ok := commeMySQL(err)
	return ok && (e.Number == codeFKParentManquant || e.Number == codeFKEnfantExistant)
}

// MessageSignal extrait le texte d'un SIGNAL levé par un trigger ou une procédure
// (SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '...'). Ces messages sont RÉDIGÉS
// en français et pensés pour l'utilisateur : on peut donc les exposer tels quels
// (à la différence des autres erreurs SQL). Renvoie (message, true) si applicable.
func MessageSignal(err error) (string, bool) {
	e, ok := commeMySQL(err)
	if ok && e.Number == codeSignalUtilisateur {
		return e.Message, true
	}
	return "", false
}
