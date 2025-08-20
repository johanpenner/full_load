import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'roles.dart';

/// Loads the current user's role from Firestore: users/{uid}.role
Future<AppRole> fetchCurrentUserRole() async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return AppRole.viewer;
  try {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
    return roleFromString(doc.data()?['role']?.toString());
  } catch (_) {
    return AppRole.viewer;
  }
}
