# Exploitation et limites vérifiées

## Données et secrets

Le client conserve la session dans le trousseau, avec une protection liée à l’appareil. Les fichiers de collection sont séparés par compte, écrits atomiquement dans Application Support et protégés jusqu’au premier déverrouillage. La déconnexion efface la session et la copie locale du compte, y compris les modifications encore en attente après confirmation. La suppression du compte efface les données serveur par cascade ; les sauvegardes externes suivent leur propre durée de rétention.

La déconnexion tente de révoquer la session auprès du fournisseur et réussit localement même hors connexion. Un jeton déjà émis peut rester utilisable jusqu’à son expiration ; configurer sa durée de vie et prévoir une procédure de révocation en cas de compromission. Ne jamais journaliser les jetons ou le contenu des avis.

## Synchronisation

Chaque changement porte un UUID persistant. L’application fige sa requête sur disque avant l’envoi, puis peut la rejouer après une perte de réponse ou un redémarrage. PostgreSQL conserve les réponses aux mutations réussies pour éviter les doubles écritures. Les révisions sont indépendantes pour chaque champ et chaque épisode. Un conflit renvoie l’état serveur ; le client rebase la modification locale et réessaie, au maximum trois conflits successifs. La dernière modification acceptée par le serveur l’emporte pour un même champ.

La lecture est paginée et fusionne les révisions sans remplacer les données plus récentes. Les suppressions de valeurs sont conservées sous forme de valeurs nulles, afin de ne pas ressusciter les données lors d’une synchronisation. Il n’y a pas encore de synchronisation en tâche de fond garantie par iOS ; elle se fait à l’ouverture, au retour au premier plan, à la reconnexion et après les actions dans l’application.

Le registre d’idempotence n’est pas purgé automatiquement : définir une politique d’archivage seulement après avoir défini une fenêtre de reprise et une procédure de migration des clients. Le supprimer sans ce contrat pourrait permettre le rejeu d’anciennes mutations.

## Sauvegarde et restauration

Activer les sauvegardes PostgreSQL chez Supabase selon le plan retenu ; vérifier leur disponibilité et leur rétention dans le projet réel. Documenter séparément la sauvegarde des identités Auth et des configurations SMTP/secrets : une exportation des seules tables publiques ne suffit pas à reconstituer le service.

Avant une ouverture publique : restaurer une sauvegarde dans un projet de test isolé, reconnecter deux comptes de test, comparer les collections/progressions, vérifier les politiques d’accès, signalements et suppressions, puis supprimer le projet de restauration selon sa politique de conservation. Noter la date, le résultat et les durées réellement mesurées. Aucun exercice de restauration hébergé n’a encore été réalisé.

## Disponibilité et surveillance

`/health` vérifie que le processus répond ; ce n’est pas une garantie que TMDB, SMTP, Supabase et le parcours complet sont disponibles. Ajouter une surveillance externe de l’authentification et d’une lecture de collection avec un compte de test dédié, ainsi que des alertes sur erreurs, stockage et consommation. Ne pas utiliser de vraies données personnelles dans les sondes.

La limite de requêtes Node est en mémoire par instance. Elle ne remplace pas une protection à la périphérie ou une limite partagée si plusieurs instances sont déployées. Les messages sont limités en PostgreSQL à six par minute et par compte, même en accès direct à Supabase. La file de modération traite cent éléments à la fois, les flux soixante ; prévoir une exploitation régulière de la file.

## Périmètre et contrôles externes restants

- Le site Windows V3 reste autonome ; il n’a pas été raccordé à la nouvelle authentification. Sa collection n’est pas importée automatiquement dans le nouveau compte.
- Le profil iOS propose un pseudo, une présentation et un avatar coloré ; le téléversement de photos n’est pas implémenté.
- Les prochaines diffusions sont affichées dans les fiches ; il n’y a pas encore de calendrier global ni de notifications push.
- Les tests de base tournent dans PGlite, pas dans un projet Supabase hébergé configuré pour FRAME.
- Les tests de simulateur et la compilation ne valident pas l’expérience sur appareil réel, les performances terrain ou l’accessibilité complète.
- La signature Apple, TestFlight, les pages légales publiques, les droits TMDB et les captures réelles restent à valider avant toute soumission.
