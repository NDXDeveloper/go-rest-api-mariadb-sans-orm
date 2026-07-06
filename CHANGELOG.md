# Journal des modifications

Tous les changements notables de ce projet sont documentés dans ce fichier.

Le format s'appuie sur [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
et ce projet respecte le [Versionnage Sémantique](https://semver.org/lang/fr/)
(*Semantic Versioning*, `MAJEUR.MINEUR.CORRECTIF`) :

- **MAJEUR** : changement incompatible avec les versions précédentes (rupture) ;
- **MINEUR** : ajout de fonctionnalité rétrocompatible ;
- **CORRECTIF** : correction de bogue rétrocompatible.

## [Non publié]

Rien à signaler pour l'instant.

## [1.0.0] - 2026-07-06

Première version publique du projet.

### Ajouté

- API REST CRUD complète pour les ressources métier : utilisateurs, auteurs,
  catégories, livres et emprunts.
- Authentification par jetons JWT avec mécanisme de *refresh tokens* et
  rotation à chaque renouvellement (prévention du rejeu).
- Autorisation par rôles (contrôle d'accès aux routes selon le profil de
  l'utilisateur authentifié).
- Base de données MariaDB complète : tables et contraintes d'intégrité,
  index, vues, fonctions, procédures stockées, triggers et events (tâches
  planifiées côté base).
- Gestion des transactions applicatives pour garantir la cohérence des
  opérations métier composées de plusieurs écritures.
- Validation des données côté Go, en complément des contraintes portées par
  le schéma SQL.
- Middlewares HTTP : journalisation des requêtes (*logger*), récupération
  après panique (*recovery*), délais d'exécution (*timeout*), limitation de
  débit (*rate limiter*), identifiant de requête (*request id*), CORS,
  en-têtes de sécurité et vérification des jetons JWT.
- Observabilité : sondes `/health` (vivacité) et `/ready` (disponibilité),
  métriques exposées au format Prometheus, journaux structurés via `log/slog`.
- Conteneurisation Docker en construction multi-étapes (*multi-stage*), image
  d'exécution non-root, orchestration complète avec Docker Compose.
- Documentation exhaustive du projet.
- Suite de tests et de benchmarks.

[Non publié]: https://github.com/exemple/api-bibliotheque/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/exemple/api-bibliotheque/releases/tag/v1.0.0
