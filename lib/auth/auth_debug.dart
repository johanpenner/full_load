import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthDebugScreen extends StatefulWidget {
  const AuthDebugScreen({super.key});
  @override
  State<AuthDebugScreen> createState() => _AuthDebugScreenState();
}

class _AuthDebugScreenState extends State<AuthDebugScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String _result = '';

  Future<void> _register() async {
    setState(() => _result = 'Working…');
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );
      setState(() => _result = 'REGISTER OK');
    } on FirebaseAuthException catch (e) {
      setState(
          () => _result = 'FirebaseAuthException: ${e.code} — ${e.message}');
      // ignore: avoid_print
      print('FIREBASE AUTH ERROR -> code=${e.code} message=${e.message}');
    } catch (e) {
      setState(() => _result = 'Unknown error: $e');
      // ignore: avoid_print
      print('UNKNOWN ERROR -> $e');
    }
  }

  Future<void> _anon() async {
    setState(() => _result = 'Working (anon)…');
    try {
      await FirebaseAuth.instance.signInAnonymously();
      setState(() => _result = 'ANON OK');
    } on FirebaseAuthException catch (e) {
      setState(() => _result = 'Anon error: ${e.code} — ${e.message}');
      print('ANON ERROR -> ${e.code} / ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auth Debug')),
      body: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 16),
            Text(_result),
          ],
        ),
      ),
    );
  }
}
