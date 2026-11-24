 # MonoKek — application Flutter (caissier · serveur · cuisine)

Port de `mono-kep-tauri` pour les rôles **cashier**, **waiter** et **kitchen**
(l'administration reste dans l'application desktop). Mêmes API, même design, même logique métier.

| Rôle | Accueil | Écrans |
|---|---|---|
| Serveur | `/pos/tables` | plan de salle, prise de commande, mes services |
| Caissier | `/pos/sales` | choix de caisse, shift, encaissement, tables, comptoir bar, historique |
| Cuisine | `/kitchen` | stations, tickets en temps réel |
| Tous | | `/pos/clock` pointage par PIN, verrouillage PIN, garde de licence |

## Lancer

```bash
flutter pub get
flutter run --dart-define=API_URL=http://192.168.1.10:8080 \   # http : accepté en debug uniquement
            --dart-define=POS_CLIENT_SECRET=<secret du client monokek-pos>
```

`POS_CLIENT_ID` (défaut `monokek-pos`), `POS_CLIENT_SECRET` et `API_URL` se passent au build,
jamais dans le code. L'adresse du serveur se règle aussi sur le terminal (écran Réglages, protégé
par le PIN du poste).

## HTTPS et certificat du serveur

Le serveur n'accepte que HTTPS (port 8443), avec le certificat de l'autorité interne de Caddy.
Les builds **release** interdisent le HTTP en clair (`android/app/src/main/res/xml/network_security_config.xml`) ;
les builds **debug** l'autorisent pour un backend de développement. Une adresse saisie sans schéma
est traitée comme `https://`.

Sur chaque tablette, avant le premier lancement : télécharger `http://<serveur>:8090/ca.crt`, puis
Paramètres > Sécurité > Installer un certificat > Certificat CA (vérifier l'empreinte avec celle du
serveur). Android n'approuve normalement pas les CA installées par l'utilisateur ; la configuration
de l'app le demande explicitement, ce qui veut dire que toute CA ajoutée à la tablette est aussi
approuvée par l'app : n'y installer que celle du serveur.

## Build Android (APK signé)

L'application s'installe sous l'identifiant `com.monokek.pos`. La signature release utilise
`android/key.properties` (ignoré par git — modèle : `android/key.properties.example`) qui pointe
vers `android/keystore/monokek.keystore` (également ignoré par git).

```bash
tool/build_release.sh          # APK  → build/app/outputs/flutter-apk/app-release.apk
tool/build_release.sh aab      # AAB  → build/app/outputs/bundle/release/app-release.aab
API_URL=https://192.168.1.10:8443 tool/build_release.sh   # serveur par défaut intégré (optionnel)
```

Le script lit `POS_CLIENT_SECRET` dans l'environnement, sinon dans
`../monokek-deploy/.env` (`IDENTITY_POS_CLIENT_SECRET`). Sans `key.properties`, Gradle **refuse**
de produire un build release (jamais de repli silencieux sur la clé debug).

> ⚠️ Sauvegardez `monokek.keystore` et ses mots de passe hors du dépôt : une application publiée
> ne peut plus être mise à jour si la clé est perdue. Le secret OAuth est embarqué dans l'APK
> (même compromis que le build Tauri) : ne distribuez l'APK qu'aux terminaux du restaurant.

Debug : `flutter build apk --debug` (clé debug, aucun secret requis pour une simple vérification).

## Linux desktop (optionnel)

```bash
sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev   # plugin audio
flutter run -d linux
```

## Impression

Aucun code d'impression côté Flutter : le serveur imprime les tickets réseau (rounds, paiements,
réimpression via `POST /api/sales/{id}/reprint`). Les imprimantes USB restent gérées par le
worker de l'application desktop via `/api/print-queue`.

## Icônes et logo

Les visuels sources sont dans `design/source/` (`icon.jpg`, `logo.jpg`). Pour les régénérer
(icône adaptative + héritée + monochrome Android 13, logo à fond transparent, icône Play Store 512 px) :

```bash
python3 tool/generate_assets.py     # Pillow uniquement
```

Sorties : `android/app/src/main/res/**/ic_launcher*`, `assets/images/logo.png`,
`design/play-store-icon-512.png`. Le logo est affiché sur les écrans de connexion et de
configuration (sur plaque blanche en thème sombre).

## Tests

```bash
flutter analyze && flutter test
```

Les tests couvrent le routage par rôle, le panier, la garde de stock, l'envoi de round (dont le
réessai sur `orderId` périmé), l'encaissement (coupon, chambre), la clôture, le pointage, le flux
SSE et les mises en page téléphone/tablette (un débordement fait échouer le test).
