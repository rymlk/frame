# Mettre FRAME en service

Le code fonctionne avec deux services distincts : Supabase (comptes et base PostgreSQL) et un hébergement Node/Docker (API). Aucun de ces services n’a été créé ou facturé par ce dépôt.

## 1. Supabase

Créer un projet dans une région adaptée aux utilisateurs, puis exécuter le fichier `supabase/migrations/202610220001_frame.sql` dans le SQL Editor. Il crée les tables, les politiques d’accès par compte et les fonctions de synchronisation/modération. Ne pas exécuter une seconde fois cette migration initiale sur une base déjà configurée.

Dans Authentication, activer le fournisseur Email et l’inscription. Dans le modèle d’e-mail de connexion et de confirmation d’inscription, afficher `{{ .Token }}` : FRAME demande un code saisi dans l’app, pas un lien. Configurer un SMTP de production, vérifier le domaine d’envoi et les limites d’envoi avant de recruter les testeurs. L’application ne gère pas encore de défi CAPTCHA : ne pas l’activer sans ajouter ce parcours au client.

Récupérer l’URL du projet et la clé publique/publishable. La clé secret/service_role reste exclusivement dans les variables secrètes de l’hébergeur du serveur. Elle ne doit jamais figurer dans Xcode, une capture, un commit ou un message.

Le schéma est testé avec PostgreSQL embarqué (PGlite) et des rôles reproduisant `auth.uid()` et `auth.jwt()`. Ces tests ne remplacent pas une vérification de bout en bout avec le service Supabase réellement configuré.

## 2. API publique

La configuration Docker est dans `backend/Dockerfile`. Le modèle `render.yaml` prépare un service Render Starter, qui est une offre payante : vérifier son tarif et valider la création dans le tableau de bord avant de déployer. Aucun abonnement n’a été souscrit. Le même Dockerfile peut être utilisé chez un autre hébergeur.

Pour Render, connecter le dépôt et la branche qui contient l’implémentation, puis créer le Blueprint. Renseigner les variables indiquées dans `backend/.env.example`. `TMDB_READ_ACCESS_TOKEN` peut être repris du fichier `.env` de la V3, sans le publier. Le serveur écoute le port fourni par l’hébergeur et `/health` répond à la sonde de disponibilité.

Les trois adresses `TERMS_URL`, `PRIVACY_URL` et `SUPPORT_URL` doivent être des pages HTTPS réellement publiées avec l’identité et le contact de l’exploitant. Les documents de ce dépôt sont des brouillons de préparation et ne remplacent pas ces pages publiques.

`ALLOWED_ORIGINS` doit inclure l’origine de l’API pour utiliser sa console `/moderation`. Ajouter uniquement les origines web réellement nécessaires. Le client iOS natif ne transmet pas d’en-tête Origin. `TRUST_PROXY=true` n’est adapté que lorsque l’hébergeur réécrit la chaîne `X-Forwarded-For` de manière fiable ; sinon le laisser à `false`.

## 3. Ouvrir la communauté

La communauté est fermée par défaut, dans Node et dans PostgreSQL. Avant de l’ouvrir, préparer les règles, le contact d’assistance et une personne chargée de traiter les messages et signalements.

1. Créer un compte dans FRAME et relever son identifiant dans Supabase Authentication.
2. Depuis un environnement administratif, définir `app_metadata.frame_moderator=true` avec l’API Admin Supabase. Ne pas utiliser `user_metadata`, qui est modifiable par l’utilisateur. Ne pas remplacer les autres métadonnées administratives existantes.
3. Se reconnecter pour obtenir un jeton avec ce rôle. Dans PostgreSQL, exécuter `update public.frame_settings set community_enabled=true where singleton=true;`.
4. Mettre `COMMUNITY_ENABLED=true` et `MODERATION_READY=true` dans l’environnement du serveur, puis redéployer.
5. Ouvrir `/moderation` sur l’API. Tester publication en attente, approbation, signalement, retrait, blocage et déblocage avec deux comptes distincts.

Les messages sont prémodérés : aucun avis n’est public avant approbation. Fermer immédiatement la communauté nécessite de remettre la valeur PostgreSQL à `false`, puis de fermer les deux indicateurs du serveur. Le rôle modérateur doit être réservé aux personnes habilitées.

## 4. Tests et développement

Sur Windows ou macOS :

```text
cd backend
npm ci --ignore-scripts
npm test
npm run check
```

Le serveur n’a aucune dépendance tierce à l’exécution. PGlite est une dépendance de test. Les tests n’utilisent ni la collection ni la clé TMDB de la V3.

Pour Xcode : ouvrir `ios/FRAME.xcodeproj`. Le projet est fourni et peut être régénéré avec `python3 scripts/generate_xcode.py` après ajout de sources. Copier `ios/Config.local.xcconfig.example` en `ios/Config.local.xcconfig` et définir l’hôte de l’API (sans `https://`), le Team ID et le Bundle ID. Ce fichier est ignoré par Git.

## 5. Sans Mac : GitHub Actions

`Verify FRAME` compile et lance les tests sur un simulateur iPhone macOS ; les résultats Xcode et le journal sont conservés sept jours. Cela vérifie le code, sans créer de version installable sur un vrai iPhone.

Créer un environnement GitHub `testflight` avec les variables `FRAME_API_HOST`, `APPLE_TEAM_ID`, `FRAME_BUNDLE_ID`, puis les secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (clé privée `.p8` App Store Connect). Utiliser une clé avec les droits nécessaires aux ressources de signature et à l’app. Les clés individuelles ou restreintes n’offrent pas toutes les mêmes permissions ; la première signature automatique reste à vérifier avec le compte réel.

Enregistrer le Bundle ID et la fiche de l’application dans App Store Connect. Lancer manuellement `Prepare TestFlight build`. Par défaut, il prépare et valide l’IPA sans l’envoyer. L’option Upload envoie uniquement le binaire à App Store Connect ; elle ne soumet pas l’app à la revue publique et ne la publie pas. Le fichier `.p8` est temporaire et supprimé à la fin du travail.

Cette chaîne de signature/export/upload n’a pas été exécutée sans les accès Apple. Les captures App Store doivent provenir de l’application réellement connectée et testée, pas du prototype Windows.

## Sources des intégrations

- [Supabase Auth](https://supabase.com/docs/guides/auth)
- [Sécurité PostgreSQL par ligne](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Configuration Render](https://render.com/docs/blueprint-spec)
- [Envoi des builds Apple](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
