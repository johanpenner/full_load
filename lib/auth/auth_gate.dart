// lib/auth/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart' as fbui;

import '../routing/role_router.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // Already signed in → route immediately
    if (user != null) {
      return const RoleRouter();
    }

    return fbui.SignInScreen(
      providers: [fbui.EmailAuthProvider()],
      headerBuilder: (context, _, __) => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Welcome to Full Load', style: TextStyle(fontSize: 24)),
      ),
      footerBuilder: (context, _) => const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Sign in to continue'),
      ),
      actions: [
        // Surface real errors (wrong-password, user-not-found, etc.)
        fbui.AuthStateChangeAction<fbui.AuthFailed>((context, state) {
          final ex = state.exception;
          final msg = (ex is FirebaseAuthException)
              ? '${ex.code}: ${ex.message ?? ''}'
              : ex.toString();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
          // ignore: avoid_print
          print('Auth failed: $msg');
        }),

        // First-time account created
        fbui.AuthStateChangeAction<fbui.UserCreated>((context, state) async {
          await _bootstrapUserDoc();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const RoleRouter()),
            (_) => false,
          );
        }),

        // Signed in to an existing account
        fbui.AuthStateChangeAction<fbui.SignedIn>((context, state) async {
          await _bootstrapUserDoc();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const RoleRouter()),
            (_) => false,
          );
        }),
      ],
    );
  }

  /// Ensure users/{uid} exists.
  /// - On first sign-in: create with role = 'viewer'
  /// - On later sign-ins: update profile fields WITHOUT touching 'role'
  static Future<void> _bootstrapUserDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      // Prefer server, fall back to cache if needed
      final snap =
          await ref.get(const GetOptions(source: Source.serverAndCache));

      if (!snap.exists) {
        // First-time create: include default role
        await ref.set({
          'email': user.email,
          'displayName': user.displayName,
          'createdAt': FieldValue.serverTimestamp(),
          'role': 'viewer', // only on create; promote in console/admin UI
          'active': true,
        }, SetOptions(merge: true));
      } else {
        // Existing user: DO NOT overwrite role
        await ref.set({
          'email': user.email,
          'displayName': user.displayName,
          'active': true,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      // Best-effort merge (no 'role') if Firestore is momentarily unavailable
      // ignore: avoid_print
      print('bootstrap user doc failed: $e');
      await ref.set({
        'email': user.email,
        'displayName': user.displayName,
        'active': true,
      }, SetOptions(merge: true));
    }
  }
}
