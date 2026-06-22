// ⚠️  PLACEHOLDER — Run `flutterfire configure` to replace this file.
//
// Steps:
//   1. Create a Firebase project at https://console.firebase.google.com
//   2. Install FlutterFire CLI:  dart pub global activate flutterfire_cli
//   3. From this project directory run:  flutterfire configure
//   4. Select your Firebase project and choose Android platform
//   5. The CLI will overwrite this file and update android/app/google-services.json
//
// Until you do this, the app will throw an error on startup.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDevPkTXWWsFl8968OVDmX3X9qIO2jIhhI',
    appId: '1:891334878584:android:c9b3aaf986f85facd2d48d',
    messagingSenderId: '891334878584',
    projectId: 'househeroes-69e92',
    storageBucket: 'househeroes-69e92.firebasestorage.app',
  );
}
