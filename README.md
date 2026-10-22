# FRAME

Application iOS native de suivi de films, séries et animes, issue de FRAME Windows V3.

- `ios/` : projet Xcode, SwiftUI et tests iOS.
- `backend/` : API Node, catalogue TMDB, authentification et tests.
- `supabase/migrations/` : schéma PostgreSQL, accès par compte et modération.
- `docs/` : installation, exploitation et préparation App Store.

Développement en cours. Une compilation de simulateur ne remplace pas les essais sur iPhone, la signature Apple ou la validation App Store.

La V3 Windows d’origine et sa collection locale ne sont pas modifiées.

## Démarrage

Consulter [l’installation](docs/INSTALLATION.md), [l’exploitation](docs/OPERATIONS.md) et [les étapes App Store](docs/APP_STORE.md).

Les écrans iOS couvrent la découverte, les fiches, les saisons et épisodes, la collection avec carrousel 3D, les notes personnelles, le profil et les discussions prémodérées. La synchronisation reprend les modifications enregistrées hors connexion, avec contrôle des révisions et rejeu idempotent.

Les données ne sont disponibles en ligne qu’après configuration des services. La communauté reste fermée par défaut dans l’API et dans PostgreSQL. Les restrictions et vérifications externes restantes sont documentées, sans prétendre à une publication déjà effectuée.

## Vérification

```text
cd backend
npm ci --ignore-scripts
npm test
npm run check
```

Les tests PostgreSQL vérifient les accès entre deux comptes, les conflits, la reprise de mutations, la prémodération, les signalements, les blocages et la suppression en cascade. Le workflow **Verify FRAME** lance également les tests natifs sur un simulateur iPhone.

Le projet Xcode est livré dans `ios/FRAME.xcodeproj`, avec un générateur reproductible dans `scripts/generate_xcode.py`. Aucun outil de génération externe ni SDK tiers iOS n’est nécessaire.
