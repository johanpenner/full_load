<DOCUMENT filename="init_app_check.dart">
// lib/auth/init_app_check.dart
// Updated: Added platform-specific providers (ReCaptcha for web, PlayIntegrity/AppAttest for mobile), error handling with print (replace with logger in prod), skip for unsupported desktops. Aligns with cross-platform app (web/Windows/iOS/macOS/Android).

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_app_check/firebase_app_check.dart';

Future<void> initAppCheck() async {
  try {
    final isUnsupportedDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (isUnsupportedDesktop) {
      print('App Check skipped: Unsupported desktop platform');
      return;
    }

    await FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider('YOUR_RECAPTCHA_V3_SITE_KEY'), // Replace with real key from Firebase Console
      androidProvider: AndroidProvider.playIntegrity, // Or .debug for testing
      appleProvider: AppleProvider.appAttest, // Or .deviceCheck
    );
    print('App Check activated successfully');
  } catch (e) {
    print('App Check init failed: $e'); // Continue without; make optional for dev
  }
}
</DOCUMENT>