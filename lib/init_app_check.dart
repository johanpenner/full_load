// lib/init_app_check.dart
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_app_check/firebase_app_check.dart';

Future<void> initAppCheck() async {
  final isUnsupportedDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);
  if (isUnsupportedDesktop) return;

  await FirebaseAppCheck.instance.activate(
    webProvider: ReCaptchaV3Provider('your-recaptcha-v3-site-key'),
    androidProvider: AndroidProvider.debug, // or .playIntegrity
    appleProvider: AppleProvider.appAttest, // or .deviceCheck
  );
}
