<DOCUMENT filename="auth_debug.dart">
// lib/auth/auth_debug.dart
// Updated: Added clear fields after action, role gating (hide if not admin), error snackbar instead of text, async role load with loading state, consistent with app's professional UI (e.g., for admin debugging in subscription-based trucking app).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'roles.dart'; // For AppRole and RoleGate
import 'current_user_role.dart'; // For currentUserRole

class AuthDebugScreen extends StatefulWidget {
  const AuthDebugScreen({super.key});
  @override
  State<AuthDebugScreen> createState() => _AuthDebugScreenState();
}

class _AuthDebugScreenState extends State<AuthDebugScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = true;
  AppRole _role = AppRole.viewer;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    try {
      _role = await currentUserRole();
    } catch (_) {
      _role = AppRole.viewer;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _register() async {
    final email = _email.text.trim();
    final pass = _pass.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      _snack('Enter email and password');
      return;
    }
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      _snack('Register OK');
      _clear();
    } on FirebaseAuthException catch (e) {
      _snack('${e.code}: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _anon() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
      _snack('Anon OK');
      _clear();
    } on FirebaseAuthException catch (e) {
      _snack('${e.code}: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _clear() {
    _email.clear();
    _pass.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(title: const Text('Auth Debug')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RoleGate(
          role: _role,
          perm: AppPerm.manageUsers, // Admin only for user management
          child: Column(
            children: [
              TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 8),
              TextField(
                  controller: _pass,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _register, child: const Text('Register (Direct)')),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: _anon, child: const Text('Sign in Anonymously')),
            ],
          ),
          deniedTooltip: 'Admin access only',
        ),
      ),
    );
  }
}
</DOCUMENT>