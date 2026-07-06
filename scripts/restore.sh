#!/usr/bin/env bash
# =============================================================================
# restore.sh — Restaure la base depuis un fichier de sauvegarde
# -----------------------------------------------------------------------------
# Usage : ./scripts/restore.sh backups/bibliotheque_AAAAMMJJ_HHMMSS.sql.gz
#
# ATTENTION : écrase le contenu actuel de la base par celui de la sauvegarde.
# =============================================================================
source "$(dirname "$0")/_commun.sh"
detecter_compose
charger_env
cd "$RACINE_PROJET"

# Vérifie qu'un fichier a bien été fourni en argument.
if [ "$#" -ne 1 ]; then
    echo "Usage : $0 <fichier_de_sauvegarde.sql.gz>" >&2
    echo "Exemple : $0 backups/bibliotheque_20260101_120000.sql.gz" >&2
    exit 1
fi

FICHIER="$1"
if [ ! -f "$FICHIER" ]; then
    echo "Erreur : fichier introuvable : $FICHIER" >&2
    exit 1
fi

echo "ATTENTION : la base « $BDD_NOM » va être ÉCRASÉE par : $FICHIER"
read -r -p "Confirmer la restauration ? [o/N] " reponse
case "$reponse" in
    [oO][uU][iI] | [oO]) ;;
    *)
        echo "Annulé."
        exit 0
        ;;
esac

echo "Restauration en cours..."
# On décompresse le fichier et on l'injecte dans le client mariadb du conteneur.
gunzip <"$FICHIER" | $COMPOSE exec -T mariadb sh -c \
    'exec mariadb -u root -p"$MARIADB_ROOT_PASSWORD" '"$BDD_NOM"

echo "Restauration terminée."
