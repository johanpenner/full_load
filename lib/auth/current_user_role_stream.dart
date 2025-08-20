import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'roles.dart';

Stream<AppRole> currentUserRoleStream() async* {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) {
    yield AppRole.viewer;
    return;
  }
  yield* FirebaseFirestore.instance
      .collection('users')
      .doc(u.uid)
      .snapshots()
      .map((snap) => roleFromString(snap.data()?['role']?.toString()));
}
