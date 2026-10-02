
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;


class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC5QVyV0g2gI5I-C5PRMOTJZrzTjo37aoo',
    appId: '1:273918198352:web:995177412a652aefe9c755',
    messagingSenderId: '273918198352',
    projectId: 'pawwatch-2a799',
    authDomain: 'pawwatch-2a799.firebaseapp.com',
    storageBucket: 'pawwatch-2a799.firebasestorage.app',
    measurementId: 'G-ZSVPMN508F',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCAX0NMxLqf8l2L9dG1M1UXM2Es6tIZync',
    appId: '1:273918198352:android:d98d869142a1a898e9c755',
    messagingSenderId: '273918198352',
    projectId: 'pawwatch-2a799',
    storageBucket: 'pawwatch-2a799.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBwh4vRanm7ldXygI2RUdvaICL3habfrss',
    appId: '1:273918198352:ios:ccb94d519031e4bbe9c755',
    messagingSenderId: '273918198352',
    projectId: 'pawwatch-2a799',
    storageBucket: 'pawwatch-2a799.firebasestorage.app',
    iosBundleId: 'com.example.pawWatch',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBwh4vRanm7ldXygI2RUdvaICL3habfrss',
    appId: '1:273918198352:ios:ccb94d519031e4bbe9c755',
    messagingSenderId: '273918198352',
    projectId: 'pawwatch-2a799',
    storageBucket: 'pawwatch-2a799.firebasestorage.app',
    iosBundleId: 'com.example.pawWatch',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyC5QVyV0g2gI5I-C5PRMOTJZrzTjo37aoo',
    appId: '1:273918198352:web:10fd064ec2fdc59be9c755',
    messagingSenderId: '273918198352',
    projectId: 'pawwatch-2a799',
    authDomain: 'pawwatch-2a799.firebaseapp.com',
    storageBucket: 'pawwatch-2a799.firebasestorage.app',
    measurementId: 'G-45CKG65F54',
  );
}

