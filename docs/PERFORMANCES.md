# PERFORMANCES.md — Performances et concurrence, expliquées

Ce document détaille les choix de **performance** et de **concurrence** du projet : le pool de
connexions, les requêtes préparées côté serveur, la propagation du `context.Context`, les timeouts,
la gestion des goroutines, et les conseils d'optimisation SQL (index, `EXPLAIN`). Chaque réglage est
**justifié** : le but est de comprendre *pourquoi* il compte.

## Table des matières

- [1. Le pool de connexions](#1-le-pool-de-connexions)
- [2. Requêtes préparées côté serveur](#2-requêtes-préparées-côté-serveur)
- [3. `context.Context` : propagation et annulation](#3-contextcontext--propagation-et-annulation)
- [4. Timeouts en cascade](#4-timeouts-en-cascade)
- [5. Concurrence et goroutines](#5-concurrence-et-goroutines)
- [6. Optimisation SQL : index et `EXPLAIN`](#6-optimisation-sql--index-et-explain)
- [7. Autres bonnes pratiques de performance](#7-autres-bonnes-pratiques-de-performance)
- [Récapitulatif des réglages](#récapitulatif-des-réglages)

---

## 1. Le pool de connexions

**Le point clé à comprendre.** En Go, `*sql.DB` n'est **pas** une connexion : c'est un **pool de
connexions** géré automatiquement. On l'ouvre **une seule fois** au démarrage et on le partage
(par injection) dans toute l'application. Ouvrir/fermer une connexion à **chaque** requête serait
catastrophique (l'établissement d'une connexion TCP + authentification coûte cher).

> `sql.Open` **n'établit pas** réellement de connexion : il prépare le pool. C'est `PingContext`  
> qui force une vraie connexion et permet de détecter tôt un problème (mauvais mot de passe, base  
> injoignable). Voir `internal/database/database.go`.

Les réglages du pool (`internal/database/database.go`, valeurs par `internal/config/config.go`) :

```go
db.SetMaxOpenConns(cfg.MaxConnexionsOuvertes)   // BDD_MAX_CONNEXIONS_OUVERTES, défaut 25
db.SetMaxIdleConns(cfg.MaxConnexionsInactives)  // BDD_MAX_CONNEXIONS_INACTIVES, défaut 25
db.SetConnMaxLifetime(cfg.DureeVieMaxConnexion) // BDD_DUREE_VIE_CONNEXION, défaut 5m
db.SetConnMaxIdleTime(cfg.DureeVieMaxConnexion) // même durée pour l'inactivité
```

| Réglage             | Rôle et justification                                                                 |
|---------------------|---------------------------------------------------------------------------------------|
| `SetMaxOpenConns`   | **Plafonne** le nombre de connexions simultanées vers MariaDB. **Trop haut** → on sature le serveur (`max_connections`). **Trop bas** → goulet d'étranglement (les requêtes attendent). On l'aligne sur la capacité de la base. |
| `SetMaxIdleConns`   | Nombre de connexions gardées **ouvertes au repos** pour éviter le coût de réouverture. Le mettre **égal** à `MaxOpenConns` donne un pool réactif (une connexion libérée reste disponible). |
| `SetConnMaxLifetime`| **Recycle** les connexions périodiquement. Indispensable derrière un équilibreur de charge ou un pare-feu qui coupe les connexions longues, et pour éviter des connexions « zombies ». |
| `SetConnMaxIdleTime`| Recycle une connexion restée **inactive** trop longtemps (libère des ressources côté base). |

**Pourquoi `MaxIdleConns == MaxOpenConns` ?** Si `MaxIdleConns` était plus petit, une connexion
tout juste libérée après une requête serait **fermée** faute de place au repos, puis **rouverte** à
la requête suivante — un gâchis. En les égalisant, une connexion active reste disponible pour la
prochaine requête.

**Surveillance en production.** Un ordonnanceur journalise périodiquement l'état du pool (voir
`cmd/api/main.go`), ce qui permet de détecter une saturation (`WaitCount` qui grimpe = requêtes en
attente d'une connexion) :

```go
stats := db.Stats()
logger.Info("état du pool de connexions",
    slog.Int("connexions_ouvertes", stats.OpenConnections),
    slog.Int("en_utilisation", stats.InUse),
    slog.Int("au_repos", stats.Idle),
    slog.Int64("en_attente", stats.WaitCount),
)
```

Si `en_attente` augmente durablement, il faut soit augmenter `MaxOpenConns` (si MariaDB tient), soit
optimiser les requêtes lentes qui monopolisent les connexions.

---

## 2. Requêtes préparées côté serveur

**Ce que fait le pilote.** Avec `interpolateParams=false` (**valeur par défaut**, laissée telle
quelle dans `construireDSN`), les paramètres `?` sont envoyés **séparément** de la requête au
serveur : c'est une **requête préparée côté serveur**. Le serveur analyse (« parse ») et planifie la
requête, puis exécute avec les valeurs fournies.

**Double bénéfice :**

1. **Sécurité** : les valeurs ne peuvent jamais altérer la structure de la requête → neutralise
   l'injection SQL (voir [SECURITE.md](SECURITE.md)).
2. **Performance** : sur une requête répétée avec des valeurs différentes, le serveur peut réutiliser
   le plan d'exécution, et le passage des paramètres en binaire est efficace.

```go
// internal/database/database.go — extrait commenté
c.ParseTime = true            // convertit DATE/DATETIME/TIMESTAMP en time.Time (sinon des []byte)
c.Loc = time.UTC              // horodatages cohérents en UTC (serveur ET client)
c.Collation = "utf8mb4_unicode_ci"  // évite « Illegal mix of collations » dans les procédures
c.Timeout = cfg.DelaiConnexion      // délai d'établissement de la connexion TCP
// interpolateParams laissé à false  -> requêtes préparées côté serveur
// multiStatements NON activé         -> une seule requête par appel (sécurité + simplicité)
```

**À propos des appels de procédures à paramètres `OUT`.** Ils utilisent des **variables de session**
(`@emprunt_uuid`…) qui ne vivent que sur **une** connexion. Comme `*sql.DB` est un pool, le
repository **réserve une connexion dédiée** avec `db.Conn(ctx)`, exécute le `CALL` **puis** lit les
`@variables` sur la **même** connexion, avant de la rendre au pool (`defer conn.Close()`). C'est le
point subtil à retenir pour les procédures `OUT` (voir
`internal/repository/emprunt_repository.go`).

---

## 3. `context.Context` : propagation et annulation

**Le principe.** Chaque requête HTTP porte un `context.Context`. On le **propage** jusqu'aux appels
base de données (`...Context`). Si la requête est **annulée** (client déconnecté, délai dépassé), le
contexte est annulé et les opérations qui l'observent **s'interrompent d'elles-mêmes**, libérant
aussitôt les ressources (connexion, mémoire).

**En pratique, partout dans le code :**

```go
// Handlers  -> services -> repositories : r.Context() est transmis de bout en bout.
r.db.QueryRowContext(ctx, requete, uuid)     // et non QueryRow(...) sans contexte
r.db.ExecContext(ctx, requete, args...)
db.BeginTx(ctx, nil)                         // même une transaction est liée au contexte
```

**Pourquoi c'est crucial ?** Sans propagation du contexte, une requête SQL lente continuerait de
tourner côté base **même si** le client a abandonné ou si le délai a expiré : la connexion resterait
mobilisée pour rien, réduisant la capacité disponible. Avec le contexte, l'annulation se **propage**
jusqu'à MariaDB.

> Règle d'or : **toujours** utiliser les variantes `...Context` et propager `r.Context()`. Sans  
> cela, le middleware de timeout (§4) serait sans effet sur les requêtes SQL (voir le commentaire  
> de `internal/middleware/timeout.go`).

**Sondes bornées.** La sonde `/ready` elle-même borne son `ping` à 2 s
(`context.WithTimeout(r.Context(), 2*time.Second)` dans `internal/handler/sante_handler.go`) : la
sonde de disponibilité ne doit **jamais** rester bloquée.

---

## 4. Timeouts en cascade

Plusieurs délais se **complètent**, chacun protégeant une phase différente :

| Délai                                | Où                                   | Protège…                                          |
|--------------------------------------|--------------------------------------|---------------------------------------------------|
| `ReadHeaderTimeout` / `ReadTimeout`  | `http.Server` (`cmd/api/main.go`)    | La **lecture** de la requête (anti-Slowloris)     |
| `WriteTimeout`                       | `http.Server`                        | L'**écriture** de la réponse                       |
| `IdleTimeout`                        | `http.Server`                        | Les connexions keep-alive **inactives**           |
| `DelaiTraitement` (middleware)       | `middleware/timeout.go`              | La **durée de traitement** applicatif (contexte)  |
| `DelaiConnexion` (pool)              | `database/database.go`               | L'**établissement** d'une connexion à la base     |
| Ping `/ready` (2 s)                  | `handler/sante_handler.go`           | La sonde de disponibilité                          |

**Cohérence importante.** Le délai de traitement doit rester **inférieur** au `WriteTimeout` du
serveur, pour que le **contexte expire AVANT** que le serveur ne coupe l'écriture de la réponse (on
préfère renvoyer une erreur propre plutôt qu'une connexion coupée). C'est documenté dans
`internal/config/config.go` (défaut : traitement 10 s < écriture 15 s).

---

## 5. Concurrence et goroutines

Go rend la concurrence naturelle. Le projet en illustre les fondamentaux **proprement**, avec un
arrêt maîtrisé (pas de goroutine « fuyarde »).

### Le serveur HTTP

`net/http` traite **chaque requête dans sa propre goroutine**. C'est pourquoi le code partagé doit
être **sans état mutable global** : ici, tout est injecté (pool, config, logger…), et les seules
variables au niveau package sont des **constantes immuables** (ex. les `regexp` compilés une fois
dans `internal/validation/validation.go`, sûrs pour un usage concurrent).

### Le limiteur de débit

`internal/middleware/rate_limiter.go` maintient une `map[string]*clientLimite` (un seau par IP),
protégée par un **`sync.Mutex`** car des requêtes concurrentes y accèdent :

```go
l.mu.Lock()
defer l.mu.Unlock()
// … accès à la map partagée …
```

Une **goroutine de nettoyage** (lancée au démarrage) purge les IP inactives toutes les minutes et
s'**arrête proprement** quand le `context.Context` global est annulé (arrêt du serveur) :

```go
select {
case <-ctx.Done():
    return                 // arrêt propre, pas de fuite de goroutine
case <-ticker.C:
    // … purge des clients inactifs …
}
```

### L'ordonnanceur de tâches

`internal/scheduler/scheduler.go` illustre le motif complet : **une goroutine par tâche**, un
`time.Ticker` pour la périodicité, un `context.Context` pour l'arrêt, et un **`sync.WaitGroup`** pour
**attendre** la fin de toutes les goroutines lors de l'arrêt gracieux :

```go
func (o *Ordonnanceur) Demarrer(ctx context.Context) {
    for _, tache := range o.taches {
        o.wg.Add(1)
        go o.boucleTache(ctx, tache)   // une goroutine par tâche
    }
}
func (o *Ordonnanceur) Attendre() { o.wg.Wait() }   // arrêt propre
```

À l'arrêt (`cmd/api/main.go`), le contexte est annulé, puis `ordonnanceur.Attendre()` bloque jusqu'à
ce que toutes les tâches soient sorties — aucune goroutine n'est laissée en suspens.

### `-race` : détecter les accès concurrents

Les tests se lancent avec le **détecteur de data races** (`go test -race`, cible `make tester`) : il
signale tout accès concurrent non synchronisé à une même donnée. C'est le filet de sécurité
indispensable de tout code concurrent.

### Tâches Go vs events MariaDB

Deux mécanismes de planification, chacun à sa place (voir aussi [DATABASE.md](../DATABASE.md)) :

- **Events MariaDB** : maintenance des **données** (purge des jetons, archivage, statistiques), au
  plus près des tables, sans dépendre de l'application.
- **Ordonnanceur Go** : tâches **applicatives** (ici, journaliser l'état du pool de connexions).

---

## 6. Optimisation SQL : index et `EXPLAIN`

**Un index accélère les lectures, ralentit un peu les écritures.** C'est une structure (arbre B) qui
évite de parcourir toute la table pour un `WHERE`, un `JOIN` ou un `ORDER BY`. Il faut le **maintenir**
à chaque écriture et il occupe de l'espace : on indexe donc les colonnes **réellement** filtrées ou
triées, pas toutes.

Le projet définit des index adaptés à ses requêtes (voir `sql/schema/02_tables.sql` et
`03_index.sql`), notamment :

- des **index simples** sur les colonnes filtrées (`role`, `statut`, `categorie_id`…) ;
- des **index composés** dont l'**ordre des colonnes** épouse les requêtes :
  - `idx_emprunts_util_statut (utilisateur_id, statut)` pour « les emprunts actifs d'un membre » ;
  - `idx_livres_categorie_titre (categorie_id, titre)` pour « les livres d'une catégorie, triés par
    titre » — la base **filtre ET trie** via le seul index, sans tri supplémentaire coûteux ;
- un index **`FULLTEXT`** (`ft_livres_recherche`) pour la recherche plein-texte performante.

> **Ordre des colonnes d'un index composé.** `(a, b)` sert les requêtes filtrant sur `a` seul, ou  
> sur `a` **et** `b`, mais **pas** sur `b` seul. On place en tête la colonne la plus souvent filtrée.

**Diagnostiquer avec `EXPLAIN`.** Pour vérifier qu'une requête utilise bien un index, préfixez-la
par `EXPLAIN` et regardez les colonnes `type` et `key` :

```sql
EXPLAIN SELECT * FROM livres WHERE categorie_id = 5 ORDER BY titre;
```

- `type` : évitez **`ALL`** (scan complet de la table). `ref`, `range`, `const`, `eq_ref` sont bons.
- `key` : l'index effectivement choisi (s'il est `NULL`, aucun index n'est utilisé).
- `rows` : estimation du nombre de lignes examinées (plus c'est bas, mieux c'est).

**Le piège du `LIKE '%mot%'`.** Un joker **en tête** (`%mot`) empêche l'usage d'un index B-arbre
classique → scan complet. Sur de gros volumes, on préfère `MATCH … AGAINST` sur un index `FULLTEXT`.
Dans ce projet, la recherche exposée reste volontairement en `LIKE` (plus simple à comprendre), et
l'index `FULLTEXT` est fourni pour expérimenter la version performante.

**Autres leviers SQL du projet :**

- **Vues pré-jointes** : `vue_livres_details` joint auteurs/catégories et calcule la disponibilité
  **une fois**, ce qui évite au client des allers-retours et centralise la logique de lecture.
- **`COUNT` + `SELECT` paginé** : les listes exécutent un `COUNT(*)` (pour la pagination) puis un
  `SELECT … LIMIT ? OFFSET ?`, en **court-circuitant** le `SELECT` si le total est 0 (voir les
  repositories).
- **Pagination bornée** : `taille` est plafonnée à **100** (`models.TailleMax`), pour éviter qu'un
  client ne demande des millions de lignes d'un coup (protection mémoire **et** performance).

---

## 7. Autres bonnes pratiques de performance

- **Pré-allocation des tranches** : les repositories créent les slices résultats avec une capacité
  initiale (`make([]models.X, 0, params.Taille)`) pour limiter les réallocations pendant le parcours
  des lignes.
- **Fermeture systématique des curseurs** : `defer lignes.Close()` après chaque `QueryContext`, et
  vérification de `lignes.Err()` après la boucle (une erreur d'itération ne se voit pas dans
  `Next()`).
- **Image Docker minimale** : binaire statique compilé avec `-ldflags "-s -w"` (table des symboles
  retirée), image finale ~20 Mo → **démarrage rapide** et déploiements légers (voir `Dockerfile`).
- **Métriques de latence** : l'histogramme `bibliotheque_http_duree_requete_secondes` (voir
  `internal/observabilite/metriques.go`) permet de suivre les quantiles (p50, p95, p99) et de
  repérer les endpoints lents. Le label `route` utilise le **patron** (`/livres/{id}`), pas le
  chemin réel, pour éviter l'explosion de cardinalité (une série par identifiant).
- **`ON DELETE CASCADE` / `RESTRICT` ciblés** : l'intégrité est gérée par la base (pas de multiples
  requêtes applicatives pour nettoyer les dépendances).

---

## Récapitulatif des réglages

| Réglage                        | Variable / lieu                       | Défaut     | Effet                                          |
|--------------------------------|---------------------------------------|------------|------------------------------------------------|
| Connexions max du pool         | `BDD_MAX_CONNEXIONS_OUVERTES`         | `25`       | Plafond de connexions simultanées à MariaDB    |
| Connexions au repos            | `BDD_MAX_CONNEXIONS_INACTIVES`        | `25`       | Connexions gardées prêtes                       |
| Durée de vie d'une connexion   | `BDD_DUREE_VIE_CONNEXION`             | `5m`       | Recyclage périodique                            |
| Délai de connexion             | `BDD_DELAI_CONNEXION`                 | `5s`       | Timeout d'établissement                         |
| Délai de traitement            | `SERVEUR_DELAI_TRAITEMENT`            | `10s`      | Annulation du contexte au-delà                  |
| Lecture / écriture serveur     | `SERVEUR_DELAI_LECTURE` / `_ECRITURE` | `10s`/`15s`| Anti-Slowloris / borne l'écriture               |
| Keep-alive                     | `SERVEUR_DELAI_INACTIF`               | `60s`      | Ferme les connexions inactives                  |
| Débit par IP                   | `RATE_LIMIT_PAR_SECONDE` / `_RAFALE`  | `10`/`20`  | Limite le volume par client                     |
| Taille max du corps            | `REQUETE_TAILLE_MAX_OCTETS`           | `1 Mio`    | Protège la mémoire                              |
| Taille de page max             | `models.TailleMax`                    | `100`      | Borne le volume renvoyé par liste               |

Ces valeurs sont des **points de départ raisonnables**. En production, on les ajuste à partir des
**mesures** (métriques Prometheus, `db.Stats()`, `EXPLAIN` sur les requêtes lentes) : on optimise ce
que l'on **mesure**, jamais à l'aveugle.
