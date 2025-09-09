// lib/auth/current_user_role.dart
// Updated: Added throw on specific errors for better debugging (e.g., no user, fetch fail), null-safe ops, companyId param if roles per-company (optional; pass if needed). Integrated with multi-tenant (fetch from nested users if companyId provided).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'roles.dart';

Future<AppRole> currentUserRole({String? companyId}) async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) {
    throw Exception('No current user authenticated');
  }
  try {
    String collectionPath = 'users'; // Default global
    if (companyId != null && companyId.isNotEmpty) {
      collectionPath = 'companies/$companyId/users'; // Nested for multi-tenant
    }
    final snap = await FirebaseFirestore.instance
        .collection(collectionPath)
        .doc(u.uid)
        .get();
    if (!snap.exists) {
      throw Exception('User document not found');
    }
    final roleStr = snap.data()?['role']?.toString();
    return roleFromString(roleStr);
  } catch (e) {
    throw Exception('Role fetch failed: $e');
  }
}
