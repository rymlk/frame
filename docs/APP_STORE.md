# Préparation App Store — FRAME 1.0

État : préparation de la bêta, pas une application déjà soumise ou approuvée. Ne pas cocher une étape sans avoir vérifié son résultat dans le service réel.

## Conditions de soumission

- [ ] Projet Supabase créé, SMTP configuré et essais complets avec deux comptes réels.
- [ ] API publique HTTPS opérationnelle ; configuration de l’app pointant vers cette API.
- [ ] Suppression de compte testée sur le service réel et les appareils connectés.
- [ ] Restauration de sauvegarde vérifiée et politique de rétention définie.
- [ ] Communauté fermée ou opérateur de modération identifié avec délai de traitement ; signalement, retrait et blocage vérifiés.
- [ ] Identité de l’exploitant, contact d’assistance et pages légales publiques.
- [ ] Conditions et licence TMDB vérifiées selon le modèle économique ; attribution avec logo officiel et droits des visuels marketing vérifiés.
- [ ] Bundle ID et Team ID vérifiés dans le compte Apple existant ; nom FRAME disponible.
- [ ] Archive Release signée, validation Apple et arrivée du build dans TestFlight confirmées.
- [ ] Test sur au moins un vrai iPhone : connexion, collection hors ligne, reconnexion, fin de saison, perte réseau pendant sauvegarde, relance et déconnexion.
- [ ] VoiceOver, taille de texte maximale, contraste et Réduire les animations testés.
- [ ] App Review : fournir un compte de démonstration ou un mécanisme de connexion utilisable par Apple, et garder le backend disponible pendant la revue. Le parcours par e-mail doit être compatible avec leur accès ; ne pas supposer qu’un compte sans accès à la boîte mail sera utilisable.
- [ ] Déclarations de confidentialité, classification par âge, statut professionnel/non professionnel et disponibilité géographique complétés dans App Store Connect.
- [ ] Captures produites depuis le build réel ; tester également sur iPad puisque le projet le prend en charge.

Apple exige une protection adaptée des contenus utilisateurs et une suppression de compte dans l’app lorsque celle-ci permet la création de comptes. Le code fournit ces parcours ; leur simple présence ne garantit pas l’approbation. Références : [Guidelines Apple](https://developer.apple.com/app-store/review/guidelines/), [Suppression de compte](https://developer.apple.com/support/offering-account-deletion-in-your-app/), [Envoi d’un build](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

## Fiche proposée, à adapter aux fonctions effectivement ouvertes

Nom : FRAME

Sous-titre : Ton cinéma, ta collection

Description :

Retrouve les films, séries et animes qui comptent pour toi.

Explore le catalogue, prépare ta liste à voir et garde le fil de tes épisodes. FRAME rassemble ta collection, tes notes et ta progression dans une interface pensée pour l’iPhone.

• Découvre des films, séries et animes et consulte leurs fiches.
• Marque tes films et épisodes vus, avec la possibilité de rattraper les épisodes précédents.
• Filtre ta collection et explore-la en carrousel.
• Retrouve tes notes, tes avis personnels et ton temps de visionnage renseigné.
• Synchronise ta collection entre appareils et consulte sa copie hors connexion.

FRAME est une application de suivi et de découverte. Elle ne diffuse pas les films ou les épisodes.

Les discussions communautaires ne doivent être mentionnées dans la fiche que si elles sont ouvertes, modérées et vérifiées dans la version proposée à Apple. Ne pas annoncer les notifications, le calendrier global, le téléversement de photos ou la synchronisation avec le site Windows tant que ces fonctions ne sont pas livrées.

Mots-clés proposés : films,séries,anime,collection,épisodes,suivi,cinéma,watchlist

Catégorie envisagée : Divertissement. La classification doit être déterminée à partir du questionnaire réel et des fonctions ouvertes, sans inventer une classification automatique.

## Données à déclarer selon le déploiement réel

| Donnée | Usage | Reliée au compte | Suivi publicitaire |
| --- | --- | --- | --- |
| E-mail et identifiant de compte | Connexion et gestion du compte | Oui | Non |
| Pseudo, présentation, couleur d’avatar | Personnalisation ; pseudo visible dans les messages | Oui | Non |
| Collection, progression, notes, avis personnels | Fonctionnement et synchronisation | Oui | Non |
| Messages, signalements, blocages | Communauté et sécurité | Oui | Non |
| Adresse IP et journaux de l’hébergeur | Sécurité et exploitation selon la configuration choisie | À vérifier avec l’hébergeur | Non prévu |

Le projet n’intègre aucun SDK publicitaire, outil d’analyse comportementale ou service de crash tiers. Le manifeste fourni décrit la collecte fonctionnelle prévue ; il doit être revu si l’hébergement ou des SDK modifient les données traitées. L’app charge les affiches depuis les serveurs d’images TMDB, qui reçoivent les informations réseau nécessaires à leur livraison.

## Textes légaux

Les textes à publier dépendent de l’identité de l’exploitant, de son pays, des prestataires, de la région d’hébergement, des durées de rétention et du contact réel. Il manque ces informations ; aucune politique fictive n’est publiée dans l’app. Les liens définitifs sont des paramètres obligatoires du serveur.

La politique doit décrire : les données du tableau, les destinataires, les finalités et fondements applicables, les durées de conservation réellement choisies, les droits et le contact, la suppression du compte et les éventuelles copies de sauvegarde. Les règles communautaires doivent interdire harcèlement, haine, contenu illégal et violations de droits, expliquer la prémodération, le signalement, le blocage et le traitement des réclamations.
