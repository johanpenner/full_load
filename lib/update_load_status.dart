import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'driver_upload_screen.dart';

Future<void> updateLoadStatus(BuildContext context, String loadId, String newStatus) async {
  final docRef = FirebaseFirestore.instance.collection('loads').doc(loadId);

  try {
    await docRef.update({'status': newStatus});

    if (newStatus == 'Delivered') {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final role = userDoc.data()?['role'] ?? 'viewer';

        if (role == 'driver') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DriverUploadScreen()),
          );
        }
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Status updated to "$newStatus"')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to update status: $e')),
    );
  }
}
