// lib/auth/auth_gate.dart
// Updated: Made stateful for async role/company fetch after sign-in. Added error handling, loading state. Integrated AppRoleProvider setRole. Fetches companyId from user doc (assume 'companyId' field). Navigates to HomeShell with companyId. Removed RoleRouter (assume replaced by HomeShell; adjust if needed).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/roles.dart'; // For AppRoleProvider
import '../home_shell.dart'; // Updated home
import 'sign_in_screen.dart';
import 'current_user_role.dart'; // For role fetch

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _companyId; // Fetched after auth

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const SignInScreen();
        }
        // User signed in: Fetch role/companyId async
        _initUserData(context, snapshot.data!);
        if (_companyId == null) {
          return const Center(
              child: CircularProgressIndicator()); // Wait for fetch
        }
        return HomeShell(companyId: _companyId!);
      },
    );
  }

  Future<void> _initUserData(BuildContext context, User user) async {
    if (_companyId != null) return; // Already fetched
    try {
      final role = await currentUserRole();
      Provider.of<AppRoleProvider>(context, listen: false).setRole(role);
      // Fetch companyId from user doc
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      _companyId =
          snap.data()?['companyId'] as String? ?? 'default-company'; // Fallback
      if (mounted) setState(() {});
    } catch (e) {
      // Handle: Sign out and show error
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Init failed: $e')));
      }
    }
  }
}
