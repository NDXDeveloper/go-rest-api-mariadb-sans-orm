#!/usr/bin/env bash
# =============================================================================
# backup.sh — Sauvegarde la base de données dans un fichier compressé
# -----------------------------------------------------------------------------
# Produit un dump SQL COMPLET (schéma + données + procédures + fonctions +
# triggers + events), compressé, dans le dossier backups/, horodaté.
# =============================================================================
source "$(dirname "$0")/_commun.sh"
detecter_compose
charger_env
cd "$RACINE_PROJET"

DOSSIER_SAUVEGARDE="$RACINE_PROJET/backups"
mkdir -p "$DOSSIER_SAUVEGARDE"

HORODATAGE="$(date +%Y%m%d_%H%M%S)"
FICHIER="$DOSSIER_SAUVEGARDE/bibliotheque_${HORODATAGE}.sql.gz"

echo "Sauvegarde de la base « $BDD_NOM » en cours..."

# mariadb-dump s'exécute DANS le conteneur, en root (mot de passe pris dans son
# environnement). Options importantes :
#   --single-transaction : dump cohérent sans verrouiller les tables (InnoDB) ;
#   --routines           : inclut les procédures et fonctions stockées ;
#   --triggers           : inclut les triggers ;
#   --events             : inclut les events planifiés.
# La sortie est compressée à la volée avec gzip.
$COMPOSE exec -T mariadb sh -c \
    'exec mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" --single-transaction --routines --triggers --events '"$BDD_NOM" \
    | gzip >"$FICHIER"

echo "Sauvegarde terminée : $FICHIER"
echo "Taille : $(du -h "$FICHIER" | cut -f1)"
