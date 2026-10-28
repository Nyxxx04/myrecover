# MyRecover mobile (Flutter + Firebase)

Mobile version of the MyRecover lost & found app. It uses Firebase directly:

- **Firebase Auth** (email/password) for accounts. Users still log in with their **username**.
- **Cloud Firestore** for profiles and items.
- **Photos** are resized to 800px JPEG and stored inside the item document, so the free Spark plan is enough (no Firebase Storage).
- **Maps** use OpenStreetMap (`flutter_map`). Address search uses Nominatim. Neither needs an API key.

It does not share data with the Laravel/MySQL web app in the parent folder.

## Features

| User | Admin |
| --- | --- |
| My Items (filter lost/found, delete) | Dashboard (total / lost / found / pending) |
| Discover all items, copy contact | Manage items (add, edit, delete) |
| Report item (map, GPS, photo) | Track items (reporter, timestamps) |

Marking an item **returned** removes it, the same as on the website.

## Setup

1. Create a project at <https://console.firebase.google.com>.
   - **Authentication → Sign-in method**: enable **Email/Password**.
   - **Firestore Database**: create a database (production mode).
   - **Firestore → Rules**: paste in the contents of [`firestore.rules`](firestore.rules), then click **Publish**.
2. Install the CLIs (one time):
   ```sh
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   ```
3. From this `mobile/` folder, link the app to your project. This replaces `lib/firebase_options.dart` and adds the platform config files:
   ```sh
   flutterfire configure
   ```
4. Run the app:
   ```sh
   flutter pub get
   flutter run
   ```

## Making an admin

Register in the app, then open Firestore → `users` → that user's document and change `role` from `user` to `admin`. Restart the app (or log out and back in).

## Data model

```
users/{uid}          name, username, email, role ('user' | 'admin'), createdAt
usernames/{username} uid, email           (lowercase username → account, for username login)
items/{id}           userId, reporter, type ('lost' | 'found'), title, category, description,
                     location, latitude, longitude, date, contact, status ('pending' | 'returned'),
                     imageBase64, createdAt, updatedAt
```

Note: `usernames` is readable without signing in, because the app needs it to log in by username. That means anyone who knows a username can look up its email. If that matters to you, switch the login screen to email and drop the `usernames` lookup.

## AI features (Google Gemini)

Everything runs inside the app: it calls Gemini directly and uses Firestore for data. No extra server is needed.

| Feature | Where |
| --- | --- |
| Photo → report autofill + privacy guard (offers to blur IC/bank cards) | Report Item: add a photo |
| Smart lost ↔ found matching (compares text and photos) | My Items → ✨ Find matches / Find owner |
| **Background match notifications** (score 75%+) | Automatic, about every 15 minutes |
| Ownership verification: the finder adds a hidden detail, the claimant answers AI-written questions, the finder's phone judges them | Report a *found* item → Secret detail; Discover → This is mine |
| Natural-language search (English/Malay) | Type a sentence in search and press Enter, or tap ✨ |
| Admin insights | Admin Dashboard → AI Insights |
| Spam/duplicate scan | Admin → Manage Items → ✨ in the top bar |

### Setup

1. Put your Gemini API key in `lib/ai_config.dart` (copy `ai_config.example.dart`). That file is git-ignored.
2. Publish the latest [`firestore.rules`](firestore.rules); they protect `secrets` (only the finder can read them) and `claims`.

### How background checks work

- Android runs a WorkManager job about every 15 minutes (the OS may delay it to save battery). It also runs when the app opens and after you report an item.
- It compares your open reports with new opposite reports (a quick text filter first, then Gemini on the best few) and notifies you when the score is 75 or more. Pairs are only checked once.
- On items you found, it judges pending ownership claims with AI and notifies you of a verified owner; claimants are notified of the result.
- iOS limits background work heavily, so this is reliable on Android only. Instant push would need a server (for example Firebase Cloud Functions on the paid plan).

### Security note

The Gemini key ships inside the app, so someone could extract it from the APK. That is fine for a project or demo. For a public release, switch to Firebase AI Logic with App Check, which keeps the key out of the app.
