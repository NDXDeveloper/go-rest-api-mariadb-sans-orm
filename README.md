# API Bibliothèque — Go + MariaDB, sans ORM

> Une API REST complète, pédagogique et **francophone**, écrite en **Go** avec **MariaDB**,  
> **sans le moindre ORM** : uniquement la bibliothèque standard `database/sql` et des requêtes  
> SQL écrites à la main. Chaque choix technique est expliqué et justifié pour que vous appreniez  
> en lisant le code **et** la documentation.

![Go](https://img.shields.io/badge/Go-1.25-00ADD8?logo=go&logoColor=white)  
![MariaDB](https://img.shields.io/badge/MariaDB-11-003545?logo=mariadb&logoColor=white)  
![Docker](https://img.shields.io/badge/Docker%20Compose-v2-2496ED?logo=docker&logoColor=white)  
![Sans ORM](https://img.shields.io/badge/ORM-aucun-success)  
![Licence](https://img.shields.io/badge/licence-MIT-blue)

Domaine métier volontairement simple et parlant : **une bibliothèque** qui gère des livres,
des auteurs, des catégories, des membres et des emprunts. Ce support couvre l'ensemble des
briques d'une vraie API de production : authentification JWT, autorisation par rôle, pagination,
transactions, procédures stockées, triggers, events, observabilité, sécurité et performances.

---

## Table des matières

- [Pourquoi « sans ORM » ?](#pourquoi--sans-orm-)
- [Objectifs pédagogiques](#objectifs-pédagogiques)
- [Prérequis](#prérequis)
- [Démarrage rapide](#démarrage-rapide)
- [Architecture en couches](#architecture-en-couches)
- [Arborescence du dépôt](#arborescence-du-dépôt)
- [Configuration (`.env`)](#configuration-env)
- [Commandes utiles](#commandes-utiles)
- [Aperçu de l'API](#aperçu-de-lapi)
- [Comptes de démonstration](#comptes-de-démonstration)
- [Tests](#tests)
- [Observabilité](#observabilité)
- [Documentation détaillée](#documentation-détaillée)
- [FAQ](#faq)
- [Erreurs fréquentes et dépannage](#erreurs-fréquentes-et-dépannage)
- [Bonnes pratiques illustrées](#bonnes-pratiques-illustrées)
- [Ressources complémentaires](#ressources-complémentaires)
- [Licence](#licence)

---

## Pourquoi « sans ORM » ?

Un **ORM** (Object-Relational Mapper, comme GORM en Go) traduit automatiquement vos structures
en tables et génère le SQL à votre place. C'est confortable, mais cela **cache** ce qui se passe
réellement. Ce projet fait le choix inverse, **assumé et pédagogique** :

| Sans ORM (ce projet)                                    | Avec ORM                                          |
|---------------------------------------------------------|---------------------------------------------------|
| Vous **voyez et maîtrisez** chaque requête SQL          | Le SQL est généré, parfois imprévisible           |
| Vous **comprenez** requêtes préparées, transactions, index | Ces notions sont masquées derrière l'abstraction |
| **Zéro magie** : le code fait exactement ce qu'il dit   | « Effets de bord » difficiles à diagnostiquer     |
| Dépendances minimales, surface d'attaque réduite        | Grosse dépendance transverse                      |
| Idéal pour **apprendre** les fondamentaux               | Idéal pour aller vite une fois les bases acquises |

On n'utilise donc que :

- **`database/sql`** — la bibliothèque standard de Go pour dialoguer avec une base SQL ;
- **`go-sql-driver/mysql`** — le pilote (driver) qui parle le protocole MariaDB/MySQL. Ce **n'est
  pas** un ORM : il transporte juste les requêtes que vous écrivez.

Résultat : en lisant ce dépôt, vous apprenez le SQL, la sécurité et l'architecture d'une API,
pas les conventions d'un framework particulier.

---

## Objectifs pédagogiques

En explorant ce projet, vous apprendrez à :

1. **Structurer une API en couches** (handlers → services → repositories) avec **injection de
   dépendances manuelle**, sans aucune variable globale.
2. **Écrire du SQL sûr** : requêtes préparées paramétrées, liste blanche pour le tri, traduction
   des erreurs SQL en erreurs métier.
3. **Sécuriser une API** : JWT + refresh tokens avec rotation, bcrypt, rate limiting, en-têtes de
   sécurité, timeouts, protection anti Mass-Assignment, non-`root` dans le conteneur.
4. **Exploiter les fonctionnalités avancées de MariaDB** : vues, **fonctions**, **procédures
   stockées** (`IN`/`OUT`/`INOUT`), **triggers**, **events** planifiés, contraintes `CHECK`,
   index composés et `FULLTEXT`.
5. **Gérer les transactions** de deux façons : dans une **procédure stockée** (emprunt) et dans
   une **transaction Go** (retour de livre).
6. **Rendre l'application observable** : logs structurés (`slog`), métriques Prometheus, sondes
   de liveness/readiness.
7. **Industrialiser** avec Docker (multi-stage build), Docker Compose, un `Makefile` et des
   scripts d'exploitation (démarrage, sauvegarde, restauration…).

---

## Prérequis

Le chemin **recommandé** (et le plus simple) n'exige que **Docker** :

- **Docker Engine** récent et **Docker Compose v2** (commande `docker compose`).
  L'ancienne commande `docker-compose` (v1) reste supportée par les scripts.

Pour développer/compiler **hors Docker** (facultatif) :

- **Go 1.25+** (grâce aux *toolchains* Go, la bonne version est téléchargée automatiquement).
- Un serveur **MariaDB 11** accessible, ou le conteneur MariaDB de ce dépôt.
- `make` (facultatif, pour les raccourcis du `Makefile`).

Aucune connaissance préalable d'un framework web n'est nécessaire : on s'appuie sur la
bibliothèque standard `net/http` (routeur `ServeMux` de Go 1.22+).

---

## Démarrage rapide

Trois commandes suffisent pour tout lancer.

### 1. Copier le modèle de configuration

```bash
cp .env.example .env
```

Ouvrez `.env` et remplacez **au minimum** les secrets par de vraies valeurs :

- `BDD_MOT_DE_PASSE` et `BDD_ROOT_MOT_DE_PASSE` (mots de passe MariaDB) ;
- `JWT_SECRET` (**au moins 32 caractères** ; générez-en un avec `openssl rand -base64 48`).

> L'application **refuse de démarrer** si `BDD_MOT_DE_PASSE` ou `JWT_SECRET` sont vides, ou si le  
> secret JWT fait moins de 32 caractères. C'est volontaire : « échouer tôt et bruyamment » vaut  
> mieux qu'un démarrage silencieux dans un état incorrect.

### 2. Construire et démarrer la pile

```bash
docker compose up -d --build
```

Cette commande construit l'image de l'API, lance **MariaDB** (qui charge automatiquement le
schéma, les procédures, les triggers, les events et un jeu de données de démonstration), puis
démarre **l'API** — mais uniquement **après** que la base soit signalée « saine » (`healthcheck`).

### 3. Vérifier que tout répond

```bash
curl http://localhost:8080/health
```

Réponse attendue :

```json
{"succes":true,"donnees":{"statut":"ok","version":"1.0.0","duree_fonctionnement":"12.3s"}}
```

### 4. Se connecter en administrateur

```bash
curl -s -X POST http://localhost:8080/api/v1/auth/connexion \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@bibliotheque.fr","mot_de_passe":"MotDePasse123!"}'
```

Vous recevez le profil de l'utilisateur **et** une paire de jetons (`jeton_acces` +
`jeton_rafraichissement`). Placez le jeton d'accès dans l'en-tête `Authorization: Bearer <jeton>`
pour appeler les routes protégées.

> Astuce : pour enchaîner les appels, stockez le jeton dans une variable shell (voir  
> [Aperçu de l'API](#aperçu-de-lapi)).

---

## Architecture en couches

L'application suit une **architecture en couches** stricte. Chaque couche a **une seule
responsabilité** et ne parle qu'à la couche immédiatement inférieure. Les dépendances sont
injectées « à la main » depuis `cmd/api/main.go` (le *composition root*).

```
                    ┌──────────────────────────────────────────────────┐
   Requête HTTP  ─► │  Middlewares globaux (pile « oignon »)           │
                    │  ID requête → Logs → Recovery → En-têtes         │
                    │  sécurité → CORS → Rate limit → Limite corps     │
                    │  → Timeout → Métriques                           │
                    └───────────────────────┬──────────────────────────┘
                                            │
                    ┌───────────────────────▼──────────────────────────┐
                    │  HANDLERS (couche HTTP)                          │
                    │  Décodent le JSON, appellent le service,         │
                    │  écrivent la réponse enveloppée. Aucun SQL.      │
                    └───────────────────────┬──────────────────────────┘
                                            │
                    ┌───────────────────────▼──────────────────────────┐
                    │  SERVICES (logique métier)                       │
                    │  Valident, orchestrent, appliquent les règles    │
                    │  (quotas, autorisations). Aucun SQL, aucun HTTP. │
                    └───────────────────────┬──────────────────────────┘
                                            │
                    ┌───────────────────────▼──────────────────────────┐
                    │  REPOSITORIES (accès aux données)                │
                    │  SEULE couche qui écrit du SQL. Requêtes         │
                    │  préparées, transactions, appels de procédures.  │
                    └───────────────────────┬──────────────────────────┘
                                            │
                    ┌───────────────────────▼──────────────────────────┐
                    │  MariaDB : tables, vues, fonctions,              │
                    │  procédures, triggers, events                    │
                    └──────────────────────────────────────────────────┘
```

**Pourquoi séparer ainsi ?**

- **Testabilité** : chaque service dépend d'une **interface** de repository (voir
  `internal/service/interfaces.go`), pas d'une implémentation concrète. On peut donc injecter un
  faux repository dans les tests, sans base de données.
- **Sécurité** : le SQL est **centralisé** dans les repositories, donc facile à auditer.
- **Clarté** : on sait toujours où chercher (une règle métier → un service ; une requête → un
  repository).

---

## Arborescence du dépôt

```
.
├── cmd/api/main.go              # Point d'entrée : assemblage (DI) + arrêt gracieux
├── internal/                    # Code privé de l'application (non importable de l'extérieur)
│   ├── apperreur/               # Type d'erreur applicative + codes métier ↔ statuts HTTP
│   ├── auth/                    # JWT (accès) + refresh tokens + bcrypt (mots de passe)
│   ├── config/                  # Lecture de la config depuis l'environnement (12-Factor)
│   ├── contexte/                # Valeurs transportées dans context.Context (ID requête, user)
│   ├── database/                # Ouverture du pool, transactions, mapping des erreurs SQL
│   ├── handler/                 # Couche HTTP : handlers + définition des routes
│   ├── middleware/              # Intercepteurs : logs, sécurité, rate limit, auth, timeout…
│   ├── models/                  # Entités (sortie) et structures d'entrée (DTO anti Mass-Assignment)
│   ├── observabilite/           # Journalisation structurée (slog) + métriques Prometheus
│   ├── reponse/                 # Enveloppe JSON homogène (succès / erreur)
│   ├── repository/              # Accès aux données : TOUT le SQL vit ici
│   ├── scheduler/               # Ordonnanceur de tâches périodiques (goroutines)
│   ├── service/                 # Logique métier + interfaces de repository
│   └── validation/              # Validation des entrées écrite à la main (sans lib externe)
├── sql/                         # Tout le SQL, découpé par nature et numéroté pour l'ordre d'exécution
│   ├── schema/                  # 00 création manuelle, 01 privilèges, 02 tables, 03 index
│   ├── functions/               # 04 fonctions stockées
│   ├── views/                   # 05 vues
│   ├── procedures/              # 06 procédures stockées (IN/OUT/INOUT, transactions)
│   ├── triggers/                # 07 triggers (BEFORE/AFTER INSERT/UPDATE/DELETE)
│   ├── events/                  # 08 events planifiés (retards, purge, archivage, stats)
│   ├── data/                    # 09 jeu de données de démonstration (seed)
│   └── migrations/              # Exemples de migrations versionnées (évolution de schéma)
├── docker/mariadb/conf.d/       # Config serveur MariaDB (charset, collation, sql_mode, UTC)
├── scripts/                     # Scripts d'exploitation (start, stop, reset, backup, restore…)
├── tests/integration/           # Emplacement des tests d'intégration (tag « integration »)
├── docker-compose.yml           # Orchestration API + MariaDB
├── Dockerfile                   # Build multi-stage de l'API (image finale ~20 Mo, non-root)
├── Makefile                     # Raccourcis (compiler, tester, démarrer…)
├── .env.example                 # Modèle de configuration à copier en .env
├── README.md                    # Ce fichier
├── API.md                       # Référence complète des endpoints (+ exemples curl)
├── DATABASE.md                  # Schéma, vues, procédures, triggers, events, transactions
├── DOCKER.md                    # Cycle de vie Docker (toutes les commandes expliquées)
├── openapi.yaml                 # Spécification OpenAPI 3.0.3 de l'API
└── docs/
    ├── SECURITE.md              # Menaces et protections mises en place, expliquées
    └── PERFORMANCES.md          # Pool de connexions, prepared statements, contextes, index…
```

---

## Configuration (`.env`)

Toute la configuration provient de **variables d'environnement** (méthodologie **12-Factor**),
jamais du code. Le fichier `.env` (copié depuis `.env.example`) sert à deux choses :

1. **Docker Compose** y lit les variables pour substituer les `${VARIABLE}` de `docker-compose.yml`
   (mots de passe, ports exposés sur l'hôte, secret JWT…).
2. **L'application** (`internal/config/config.go`) lit les variables d'environnement injectées.
   Hors Docker (`make executer`), elle lit aussi directement le fichier `.env`.

> **À retenir sur les ports** : dans Docker, `SERVEUR_PORT_HOTE` et `BDD_PORT_HOTE` définissent le  
> port **exposé sur votre machine**, tandis que l'API écoute toujours sur `8080` **dans** le  
> conteneur et joint MariaDB via le nom de service `mariadb:3306` (DNS interne Docker).

### Variables lues par l'application

| Variable                        | Défaut            | Obligatoire | Rôle                                                        |
|---------------------------------|-------------------|:-----------:|-------------------------------------------------------------|
| `APP_ENVIRONNEMENT`             | `developpement`   |             | `developpement` ou `production` (durcit CORS, messages…)    |
| `SERVEUR_ADRESSE`               | `0.0.0.0`         |             | Interface d'écoute HTTP                                     |
| `SERVEUR_PORT`                  | `8080`            |             | Port d'écoute **dans** le processus                         |
| `SERVEUR_DELAI_LECTURE`         | `10s`             |             | Délai max de lecture requête (anti-Slowloris)               |
| `SERVEUR_DELAI_ECRITURE`        | `15s`             |             | Délai max d'écriture de la réponse                          |
| `SERVEUR_DELAI_INACTIF`         | `60s`             |             | Délai keep-alive entre deux requêtes                        |
| `SERVEUR_DELAI_TRAITEMENT`      | `10s`             |             | Délai max de traitement applicatif (contexte annulé au-delà)|
| `SERVEUR_DELAI_ARRET`           | `15s`             |             | Fenêtre laissée aux requêtes en cours à l'arrêt             |
| `BDD_HOTE`                      | `127.0.0.1`       |             | Hôte MariaDB (`mariadb` dans Docker)                        |
| `BDD_PORT`                      | `3306`            |             | Port MariaDB                                                |
| `BDD_NOM`                       | `bibliotheque`    |             | Nom de la base                                              |
| `BDD_UTILISATEUR`               | `app_bibliotheque`|             | Utilisateur applicatif (droits limités)                     |
| `BDD_MOT_DE_PASSE`              | *(vide)*          |   **oui**   | Mot de passe de l'utilisateur applicatif                    |
| `BDD_MAX_CONNEXIONS_OUVERTES`   | `25`              |             | Taille max du pool de connexions                            |
| `BDD_MAX_CONNEXIONS_INACTIVES`  | `25`              |             | Connexions gardées au repos                                 |
| `BDD_DUREE_VIE_CONNEXION`       | `5m`              |             | Durée de vie max d'une connexion (recyclage)                |
| `BDD_DELAI_CONNEXION`           | `5s`              |             | Délai max pour établir/valider la connexion                 |
| `JWT_SECRET`                    | *(vide)*          |   **oui**   | Clé HMAC-SHA256 (**≥ 32 caractères**)                       |
| `JWT_EMETTEUR`                  | `api-bibliotheque`|             | Champ `iss` du jeton                                        |
| `JWT_DUREE_ACCES`               | `15m`             |             | Durée de vie d'un jeton d'accès (court)                     |
| `JWT_DUREE_RAFRAICHISSEMENT`    | `168h`            |             | Durée de vie d'un refresh token (7 jours)                   |
| `CORS_ORIGINES_AUTORISEES`      | `*`               |             | Origines CORS (`*` **interdit** en production)              |
| `REQUETE_TAILLE_MAX_OCTETS`     | `1048576` (1 Mio) |             | Taille max du corps d'une requête (anti-DoS)                |
| `RATE_LIMIT_PAR_SECONDE`        | `10`              |             | Requêtes/seconde autorisées par IP                          |
| `RATE_LIMIT_RAFALE`             | `20`              |             | Pic de requêtes toléré (*burst*)                            |
| `LOG_NIVEAU`                    | `info`            |             | `debug` \| `info` \| `warn` \| `error`                      |
| `LOG_FORMAT`                    | `texte`           |             | `json` (prod) \| `texte` (dev)                              |

### Variables propres à Docker Compose (dans `.env`)

| Variable                | Défaut               | Rôle                                                        |
|-------------------------|----------------------|-------------------------------------------------------------|
| `COMPOSE_PROJECT_NAME`  | `bibliotheque`       | Préfixe des conteneurs, réseaux et volumes                  |
| `SERVEUR_PORT_HOTE`     | `8080`               | Port de l'API **exposé sur l'hôte**                         |
| `BDD_PORT_HOTE`         | `3306`               | Port MariaDB **exposé sur l'hôte** (client SQL externe)     |
| `BDD_ROOT_MOT_DE_PASSE` | *(à changer)*        | Mot de passe `root` de MariaDB (administration, sauvegardes)|

---

## Commandes utiles

### Makefile

Tapez `make` (ou `make aide`) pour afficher toutes les cibles. Les principales :

| Commande             | Effet                                                            |
|----------------------|------------------------------------------------------------------|
| `make demarrer`      | `docker compose up -d --build` (démarre API + MariaDB)           |
| `make arreter`       | `docker compose down` (arrête, **conserve** les données)         |
| `make reconstruire`  | Reconstruit les images et recrée les conteneurs                  |
| `make journaux`      | Suit les logs de l'API (`docker compose logs -f api`)            |
| `make nettoyer`      | `docker compose down -v` (**supprime les données** du volume)    |
| `make compiler`      | Compile le binaire dans `./bin`                                  |
| `make executer`      | Lance l'API en local (`go run`, nécessite un `.env`)             |
| `make tester`        | Lance tous les tests avec le détecteur de *data races*           |
| `make tester-court`  | Tests rapides uniquement (`-short`, sans intégration)            |
| `make couverture`    | Rapport de couverture HTML (`coverage.html`)                     |
| `make lint`          | `golangci-lint` (analyse statique, doit être installé)           |
| `make verifier`      | `gofmt` + `go vet` + `go build` (contrôle rapide avant commit)   |

### Scripts d'exploitation (`scripts/`)

Ces scripts détectent automatiquement `docker compose` (v2) ou `docker-compose` (v1) et lisent
votre `.env`. Ils demandent confirmation avant toute opération destructrice.

| Script                              | Rôle                                                                        |
|-------------------------------------|-----------------------------------------------------------------------------|
| `./scripts/start.sh`                | Démarre la pile (construit les images au besoin)                            |
| `./scripts/stop.sh`                 | Arrête la pile, **conserve** le volume de données                           |
| `./scripts/reset.sh`                | **Réinitialise** la base (supprime le volume, recharge schéma + seed)       |
| `./scripts/rebuild.sh`              | Reconstruit l'image de l'API **sans cache**, conserve les données           |
| `./scripts/backup.sh`               | Sauvegarde compressée (`backups/…​.sql.gz`) : schéma + données + routines    |
| `./scripts/restore.sh <fichier>`    | Restaure la base depuis une sauvegarde (**écrase** l'existant)              |
| `./scripts/clean.sh`                | Nettoyage **complet** : conteneurs, volumes, images locales, réseau         |

Exemple de cycle de sauvegarde / restauration :

```bash
./scripts/backup.sh
# → backups/bibliotheque_20260706_120000.sql.gz
./scripts/restore.sh backups/bibliotheque_20260706_120000.sql.gz
```

> Le détail de **chaque commande Docker** (et son équivalent `docker-compose` v1) est dans  
> **[DOCKER.md](DOCKER.md)**.

---

## Aperçu de l'API

- **Base des routes** : `http://localhost:8080/api/v1`
- **Format d'échange** : JSON (UTF-8), enveloppé de façon homogène.
- **Identifiants publics** : des **UUID** (le champ JSON s'appelle `id`). Les clés
  auto-incrémentées internes ne sont **jamais** exposées (protection contre l'énumération / IDOR).
- **Authentification** : `Authorization: Bearer <jeton_acces>` (JWT).

### Enveloppe de réponse

**Succès** (avec pagination optionnelle) :

```json
{
  "succes": true,
  "donnees": { "...": "..." },
  "meta": { "page": 1, "taille_par_page": 20, "total_elements": 28, "total_pages": 2 }
}
```

**Erreur** :

```json
{
  "succes": false,
  "erreur": {
    "code": "VALIDATION",
    "message": "Un ou plusieurs champs sont invalides.",
    "details": { "email": "adresse e-mail invalide" }
  }
}
```

### Pagination, tri, recherche et filtres

Les listes acceptent ces paramètres de requête :

| Paramètre    | Exemple            | Description                                                      |
|--------------|--------------------|------------------------------------------------------------------|
| `page`       | `?page=2`          | Numéro de page (défaut `1`)                                      |
| `taille`     | `?taille=50`       | Éléments par page (défaut `20`, **max `100`**)                   |
| `tri`        | `?tri=titre`       | Champ de tri (**liste blanche** par ressource, anti-injection)   |
| `ordre`      | `?ordre=desc`      | `asc` (défaut) ou `desc`                                         |
| `recherche`  | `?recherche=hugo`  | Recherche plein-texte simple (`LIKE`)                            |
| *filtres*    | `?disponible=true` | Filtres additionnels propres à chaque ressource                  |

### Exemples curl réels

**Se connecter et mémoriser le jeton** (avec [`jq`](https://jqlang.github.io/jq/)) :

```bash
JETON=$(curl -s -X POST http://localhost:8080/api/v1/auth/connexion \
  -H "Content-Type: application/json" \
  -d '{"email":"chloe.durand@exemple.fr","mot_de_passe":"MotDePasse123!"}' \
  | jq -r '.donnees.jetons.jeton_acces')
```

**Lister les livres disponibles, triés par prix décroissant** (public) :

```bash
curl -s "http://localhost:8080/api/v1/livres?disponible=true&tri=prix&ordre=desc&taille=5" | jq
```

**Emprunter un livre** (authentifié — remplacez l'UUID par un `id` de livre réel) :

```bash
curl -s -X POST http://localhost:8080/api/v1/emprunts \
  -H "Authorization: Bearer $JETON" \
  -H "Content-Type: application/json" \
  -d '{"livre_id":"<UUID_DU_LIVRE>","duree_jours":21}' | jq
```

**Consulter mes emprunts et mes statistiques** :

```bash
curl -s -H "Authorization: Bearer $JETON" http://localhost:8080/api/v1/moi/emprunts | jq
curl -s -H "Authorization: Bearer $JETON" http://localhost:8080/api/v1/moi/statistiques | jq
```

> La référence **exhaustive** de tous les endpoints (méthode, rôle requis, paramètres, corps  
> attendu/retourné, codes HTTP, erreurs possibles, curl complet) est dans **[API.md](API.md)**,  
> et la spécification machine dans **[openapi.yaml](openapi.yaml)**.

---

## Comptes de démonstration

Le jeu de données (`sql/data/09_seed.sql`) crée ces comptes. **Mot de passe commun :
`MotDePasse123!`**

| E-mail                          | Rôle             | Remarque                          |
|---------------------------------|------------------|-----------------------------------|
| `admin@bibliotheque.fr`         | `admin`          | Accès complet                     |
| `bibliothecaire@bibliotheque.fr`| `bibliothecaire` | Gère catalogue et emprunts        |
| `chloe.durand@exemple.fr`       | `membre`         | Emprunts en cours et rendus       |
| `david.petit@exemple.fr`        | `membre`         | A un emprunt en retard            |
| `emma.roux@exemple.fr`          | `membre`         |                                   |
| `farid.benali@exemple.fr`       | `membre`         |                                   |
| `gwen.leroy@exemple.fr`         | `membre`         |                                   |

Le catalogue est peuplé de **28 livres**, **12 auteurs** et **8 catégories**, avec des emprunts
dans divers états (`en_cours`, `rendu`, `en_retard`) pour illustrer immédiatement les vues et les
statistiques.

---

## Tests

```bash
# Tous les tests, avec détection des accès concurrents (data races)
go test -race -count=1 ./...        # ou : make tester

# Uniquement les tests rapides (unitaires), sans intégration
go test -short -count=1 ./...       # ou : make tester-court

# Rapport de couverture HTML
make couverture                     # → coverage.html
```

**Tests unitaires vs tests d'intégration.** Les services dépendent d'**interfaces** de repository,
donc les tests unitaires peuvent injecter un faux repository et tourner **sans base de données**.
Les tests d'intégration (qui ont besoin d'un vrai MariaDB) se placent dans `tests/integration/` et
se protègent par la convention `-short` / un *build tag* dédié :

```go
//go:build integration

package integration
// … tests nécessitant une base réelle …
```

On les exécute alors explicitement :

```bash
go test -tags=integration ./tests/integration/...
```

---

## Observabilité

Trois points d'entrée **non authentifiés** :

| Endpoint   | Rôle                                                                              |
|------------|-----------------------------------------------------------------------------------|
| `/health`  | **Liveness** : « le processus est-il vivant ? ». Répond toujours `200` si vivant. |
| `/ready`   | **Readiness** : « peut-il servir ? ». Vérifie MariaDB (`503` si injoignable).     |
| `/metrics` | **Métriques Prometheus** (compteurs, histogrammes de latence, runtime Go).        |

Distinguer *liveness* et *readiness* évite les redémarrages inutiles : un orchestrateur
redémarre le conteneur sur échec de `/health`, mais se contente de retirer l'instance du service
sur échec de `/ready` (le temps que la base se rétablisse).

Les **logs** sont structurés (`slog`), au format `json` (production) ou `texte` (développement).
Chaque requête est tracée avec un **identifiant de requête** (`X-Request-ID`) pour corréler tous
ses logs. Aucune donnée sensible n'est journalisée (ni corps, ni *query string*, ni secret).

Exemple d'extraction d'une métrique :

```bash
curl -s http://localhost:8080/metrics | grep bibliotheque_http_requetes_total
```

---

## Documentation détaillée

| Document                              | Contenu                                                                    |
|---------------------------------------|----------------------------------------------------------------------------|
| **[API.md](API.md)**                  | Référence de tous les endpoints, par ressource, avec exemples curl complets |
| **[openapi.yaml](openapi.yaml)**      | Spécification OpenAPI 3.0.3 (importable dans Swagger UI, Postman, Insomnia) |
| **[DATABASE.md](DATABASE.md)**        | Schéma complet, index, vues, fonctions, procédures, triggers, events, transactions |
| **[DOCKER.md](DOCKER.md)**            | Cycle de vie Docker : toutes les commandes, expliquées, v2 **et** v1       |
| **[docs/SECURITE.md](docs/SECURITE.md)**   | Chaque menace (injection SQL, XSS, CSRF, brute force, DoS…) et sa parade |
| **[docs/PERFORMANCES.md](docs/PERFORMANCES.md)** | Pool de connexions, prepared statements, `context`, timeouts, index |

---

## FAQ

**Pourquoi le champ `id` est-il un UUID et pas un nombre ?**
Exposer une clé séquentielle (`1`, `2`, `3`…) permettrait à un attaquant de deviner et d'énumérer
les ressources (faille **IDOR**). On expose donc un UUID non devinable ; la clé numérique reste
interne à la base.

**Pourquoi deux systèmes de tâches planifiées (events MariaDB *et* ordonnanceur Go) ?**
Les **events MariaDB** sont idéaux pour la maintenance des **données** (purge, archivage,
agrégats), au plus près des tables. L'**ordonnanceur Go** convient aux tâches **applicatives**
(ici, journaliser périodiquement l'état du pool de connexions).

**Puis-je changer le mot de passe de démonstration ?**
Oui : le seed contient un haché bcrypt de `MotDePasse123!`. Créez un nouveau compte via
`/api/v1/auth/inscription`, ou modifiez le seed et réinitialisez la base (`./scripts/reset.sh`).

**L'API fonctionne-t-elle sans Docker ?**
Oui : lancez un MariaDB 11, renseignez `.env` (dont `BDD_HOTE`), puis `make executer`. Il faudra
charger vous-même les scripts `sql/` (voir [DATABASE.md](DATABASE.md)).

**Où est écrit le SQL ?**
Exclusivement dans `internal/repository/`. Les handlers et services n'en contiennent jamais.

**Comment un emprunt gère-t-il la concurrence sur le dernier exemplaire ?**
La procédure `pr_emprunter_livre` verrouille la ligne du livre (`SELECT … FOR UPDATE`) : deux
emprunts simultanés du dernier exemplaire sont **sérialisés**, le second voit `0` disponible.

---

## Erreurs fréquentes et dépannage

| Symptôme                                                        | Cause probable et solution                                                                 |
|-----------------------------------------------------------------|--------------------------------------------------------------------------------------------|
| `configuration invalide : JWT_SECRET doit faire au moins 32…`   | Secret JWT trop court. Générez-en un : `openssl rand -base64 48`.                           |
| `configuration invalide : BDD_MOT_DE_PASSE est obligatoire`     | `.env` manquant ou variable vide. `cp .env.example .env` et renseignez les secrets.        |
| L'API redémarre en boucle au premier lancement                  | Elle attend MariaDB « healthy ». Patientez (~40 s au 1er boot), puis `docker compose logs api`. |
| `Illegal mix of collations`                                     | Collation incohérente. Ce projet impose `utf8mb4_unicode_ci` partout (voir `charset.cnf`). Réinitialisez : `./scripts/reset.sh`. |
| `401` « Jeton d'accès invalide ou expiré »                      | Le jeton d'accès dure 15 min. Rafraîchissez-le via `/api/v1/auth/rafraichir`.              |
| `429` « Trop de requêtes »                                      | Limite de débit atteinte (10 req/s par IP par défaut). Patientez ou ajustez `RATE_LIMIT_*`. |
| `403` « Vous n'avez pas les droits nécessaires »                | Rôle insuffisant. Connectez-vous avec un compte `admin` ou `bibliothecaire` selon la route. |
| Les modifications du code Go ne sont pas prises en compte       | Reconstruisez l'image : `./scripts/rebuild.sh` (ou `make reconstruire`).                    |
| Le port 8080 est déjà utilisé                                   | Changez `SERVEUR_PORT_HOTE` dans `.env` (ex. `8081`).                                       |

---

## Bonnes pratiques illustrées

Ce dépôt met concrètement en œuvre, avec explications dans le code :

- **12-Factor App** : configuration par l'environnement, secrets hors du code.
- **Injection de dépendances manuelle**, **aucune variable globale** mutable.
- **Requêtes préparées paramétrées** systématiques ; **liste blanche** pour l'`ORDER BY`.
- **Structures d'entrée dédiées** + `DisallowUnknownFields` (anti **Mass-Assignment**).
- **Erreurs métier stables** (code + statut HTTP) et **aucune fuite technique** au client.
- **Suppression logique** (horodatage `supprime_le`) plutôt que destruction des données.
- **Transactions** avec rollback automatique et **verrouillage** ciblé (`FOR UPDATE`).
- **Arrêt gracieux** (SIGINT/SIGTERM) qui laisse les requêtes en cours se terminer.
- **Build Docker multi-stage**, image minimale, exécution en utilisateur **non-`root`**.

---

## Ressources complémentaires

- [Documentation `database/sql` (Go)](https://pkg.go.dev/database/sql)
- [Tutoriel officiel « Accessing a relational database »](https://go.dev/doc/tutorial/database-access)
- [Go 1.22 : les nouveautés du routeur `net/http.ServeMux`](https://go.dev/blog/routing-enhancements)
- [Base de connaissances MariaDB](https://mariadb.com/kb/en/)
- [The Twelve-Factor App](https://12factor.net/fr/)
- [OWASP API Security Top 10](https://owasp.org/API-Security/)
- [Spécification OpenAPI 3.0.3](https://spec.openapis.org/oas/v3.0.3)

---

## Licence

Projet distribué sous licence **MIT** — libre d'utilisation, y compris à des fins pédagogiques et
commerciales. Voir le fichier `LICENSE` s'il est présent, ou adaptez la mention à votre contexte.
