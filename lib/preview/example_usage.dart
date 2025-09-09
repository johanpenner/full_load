// lib/preview/example_usage.dart
// Demo for navigating to previews (BOL PDF and photo).
// Updates: Added role gating, error checks, async load example (optional Firestore).

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // If pulling real URLs

import 'universal_preview_screen.dart';
import '../auth/roles.dart'; // For RoleGate
import '../auth/current_user_role.dart'; // For currentUserRole

class ExampleUsageScreen extends StatefulWidget {
  const ExampleUsageScreen({super.key});
  @override
  State<ExampleUsageScreen> createState() => _ExampleUsageScreenState();
}

class _ExampleUsageScreenState extends State<ExampleUsageScreen> {
  AppRole _role = AppRole.viewer;
  String? _bolUrl; // Example: fetch from Firestore
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadUrls(); // Optional: fetch real URLs
  }

  Future<void> _loadRole() async {
    _role = await currentUserRole();
    setState(() {});
  }

  Future<void> _loadUrls() async {
    // Example: Fetch from a load doc (replace with your logic)
    try {
      final doc = await FirebaseFirestore.instance
          .collection('loads')
          .doc('exampleLoadId') // Replace with real ID
          .get();
      if (doc.exists) {
        final m = doc.data()!;
        _bolUrl = m['bolUrl'] as String?;
        _photoUrl = m['photoUrl'] as String?;
        setState(() {});
      }
    } catch (e) {
      // Handle error silently or show snack
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fallback dummy URLs if not loaded
    final bol = _bolUrl ??
        'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf';
    final photo = _photoUrl ?? 'https://picsum.photos/1200/800';

    return Scaffold(
      appBar: AppBar(title: const Text('Preview Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            RoleGate(
              role: _role,
              perm: AppPerm.viewDispatch, // Or custom 'viewDocs'
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Preview BOL (PDF)'),
                onTap: bol.isEmpty
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UniversalPreviewScreen(
                              urlOrPath: bol,
                              fileName: 'BOL.pdf',
                            ),
                          ),
                        ),
              ),
            ),
            const SizedBox(height: 8),
            RoleGate(
              role: _role,
              perm: AppPerm.viewDispatch,
              child: ListTile(
                leading: const Icon(Icons.image),
                title: const Text('Preview Photo (JPG)'),
                onTap: photo.isEmpty
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UniversalPreviewScreen(
                              urlOrPath: photo,
                              fileName: 'photo.jpg',
                            ),
                          ),
                        ),
              ),
            ),
            if (_bolUrl == null && _photoUrl == null)
              const Center(child: CircularProgressIndicator()),
            if (_bolUrl == null || _photoUrl == null)
              const Text('Loading real URLs... (or using dummies)'),
          ],
        ),
      ),
    );
  }
}
