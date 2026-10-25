# Boutique du Sanctuaire marial d'Abidjan : package PWA

Contenu du dossier :

| Fichier | Rôle |
|---|---|
| `index.html` | L'application (boutique, livraison, espace gestion) |
| `config.js` | Les deux clés Supabase à renseigner |
| `manifest.webmanifest` + `icons/` | Rendent l'application installable (icône sur l'écran d'accueil) |
| `sw.js` | Service worker : l'application s'ouvre même avec une mauvaise connexion |
| `_headers` | Règles de cache et de sécurité (reconnues par Netlify et Cloudflare) |
| `supabase/schema.sql` | Création de toute la base de données |

Sans clés dans `config.js`, l'application fonctionne en **mode démonstration** (données gardées sur l'appareil, code gestion 1234). Pratique pour un premier test.

## Étape 1. Créer la base Supabase (10 minutes)

1. Créez un compte sur supabase.com puis un projet (choisissez une région proche, par exemple Paris ou Londres). Notez le mot de passe de la base.
2. Ouvrez **SQL Editor**, collez tout le contenu de `supabase/schema.sql`, cliquez **Run**. Les tables, les règles de sécurité, le stockage des photos et vos 6 articles de départ sont créés.
3. **Authentication > Users > Add user** : créez le compte administrateur (e-mail + mot de passe), en cochant « Auto Confirm User ».
4. Retournez dans **SQL Editor** et exécutez, avec votre e-mail :
   `insert into admins (user_id) select id from auth.users where email = 'votre@email.com';`
5. **Project Settings > API** : copiez la **Project URL** et la clé **anon public**.

## Étape 2. Renseigner `config.js`

Ouvrez `config.js` dans un éditeur de texte et collez l'URL et la clé anon. Ajoutez aussi `SHARE_URL` (l'adresse finale du site) pour que le bouton WhatsApp partage la bonne adresse. N'y mettez jamais la clé `service_role`.

## Étape 3. Mettre en ligne

**Netlify (le plus simple)** : allez sur app.netlify.com/drop et glissez le dossier `sanctuaire-pwa`. Le site est en ligne tout de suite. Pour les mises à jour suivantes : Site > Deploys > glisser le dossier à nouveau (ou reliez un dépôt GitHub).

**Cloudflare Pages** : Workers & Pages > Create > Pages > « Upload assets », envoyez le dossier. Si vous passez par GitHub : aucune commande de build, dossier de sortie `/`.

**Nom de domaine** : achetez-le (voir nos échanges), puis ajoutez-le dans Netlify (Domain management) ou Cloudflare (Custom domains). Le HTTPS est automatique. Remettez ensuite l'adresse finale dans `SHARE_URL`.

## Étape 4. Tester

1. Ouvrez le site sur un téléphone : passez une commande test (retrait puis livraison).
2. Onglet **Gestion** : connectez-vous avec le compte administrateur. Vérifiez que la commande apparaît, changez son statut, ajoutez un article avec sa photo (une photo par article), réglez les distances.
3. Android (Chrome) : bouton « Installer » ou menu ⋮ > « Ajouter à l'écran d'accueil ». iPhone (Safari) : Partager > « Sur l'écran d'accueil ».
4. Partagez l'adresse par WhatsApp avec l'icône de partage.

## Mot de passe oublié

Dans Gestion > « Mot de passe oublié ? », saisissez l'e-mail administrateur : Supabase envoie un lien, qui rouvre la boutique sur l'écran « Nouveau mot de passe ». Pour que cela fonctionne :

1. Dans Supabase : **Authentication > URL Configuration**. Mettez l'adresse du site dans **Site URL** et ajoutez-la aussi dans **Redirect URLs**.
2. Le service d'e-mail par défaut de Supabase envoie très peu de messages par heure. Pour un usage régulier, configurez votre propre service d'envoi (SMTP) dans Authentication > Emails.
3. Secours : dans Supabase > Authentication > Users, vous pouvez toujours changer le mot de passe à la main.

Une fois connecté, Gestion > **Compte** permet de changer son mot de passe.

## À savoir

- Le paiement Wave est manuel : le client voit le numéro et la référence, le sanctuaire vérifie dans Wave puis passe la commande en « Paiement vérifié ». Le numéro Wave se règle dans Gestion > Distances.
- Le prix des commandes est recalculé par la base (impossible à falsifier depuis le navigateur). Le stock diminue à chaque commande.
- Le prix d'une course de livraison pour des tiers est calculé par l'application ; vérifiez-le avant de valider.
- Offre gratuite Supabase : un projet peu utilisé peut être mis en pause. Vérifiez les conditions actuelles et pensez aux sauvegardes avant le lancement officiel.
- Les photos sont réduites à 640 px avant l'envoi pour rester légères.

## Étape suivante : Google Play

Une fois le site en ligne avec HTTPS : allez sur pwabuilder.com, collez l'adresse du site, choisissez « Android » et téléchargez le paquet. Compte Google Play développeur : 25 $ (paiement unique). Pour l'App Store : compte Apple Developer à 99 $/an et un Mac.
