// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Optional: only needed when you wire App Check fully
// import 'package:firebase_app_check/firebase_app_check.dart';

import 'firebase_options.dart'; // <-- must exist at lib/firebase_options.dart
import 'auth/auth_gate.dart'; // <-- make sure this file exists

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // If/when you set up App Check for Web, uncomment and paste your SITE key:
  // if (kIsWeb) {
  //   await FirebaseAppCheck.instance.activate(
  //     webProvider: ReCaptchaV3Provider('YOUR_RECAPTCHA_V3_SITE_KEY'),
  //   );
  // }

  runApp(const FullLoadApp());
}

class FullLoadApp extends StatelessWidget {
  const FullLoadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Full Load',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const AuthGate();
        },
      ),
    );
  }
}
