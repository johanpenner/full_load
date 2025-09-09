<DOCUMENT filename="current_user_role_stream.dart">
// lib/auth/current_user_role_stream.dart
// Updated: Added companyId param for multi-tenant (roles nested under company), debounce with rxdart to avoid flicker on auth changes (add rxdart: ^0.27.7 to pubspec), better error handling (yield viewer + log), null-safe.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart'; // Add to pubspec for debounce

import 'roles.dart';

Stream<AppRole> currentUserRoleStream({String? companyId}) {
  return FirebaseAuth.instance.authStateChanges().debounceTime(const Duration(milliseconds: 500)).asyncMap((user) async {
    if (user == null) return AppRole.viewer;
    try {
      String collectionPath = 'users'; // Global fallback
      if (companyId != null && companyId.isNotEmpty) {
        collectionPath = 'companies/$companyId/users'; // Nested for multi-tenant
      }
      final snap = await FirebaseFirestore.instance.collection(collectionPath).doc(user.uid).get();
      if (!snap.exists) throw Exception('User doc missing');
      final roleStr = snap.data()?['role']?.toString();
      return roleFromString(roleStr);
    } catch (e) {
      // Log error (use print for debug; integrate logger in prod)
      print('Role stream error: $e');
      return AppRole.viewer;
    }
  });
}
</DOCUMENT>