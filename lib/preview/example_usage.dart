import 'package:flutter/material.dart';
import 'universal_preview_screen.dart';

class LoadDetailScreen extends StatelessWidget {
  final String loadId;
  const LoadDetailScreen({super.key, required this.loadId});

  @override
  Widget build(BuildContext context) {
    // Example URLs; replace with your Firestore doc fields
    final bolUrl =
        'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf';
    final photoUrl = 'https://picsum.photos/1200/800';

    return Scaffold(
      appBar: AppBar(title: Text('Load #$loadId')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: const Text('Preview BOL (PDF)'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UniversalPreviewScreen(
                  urlOrPath: bolUrl,
                  fileName: 'BOL.pdf',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.image),
            title: const Text('Preview Photo (JPG)'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UniversalPreviewScreen(
                  urlOrPath: photoUrl,
                  fileName: 'photo.jpg',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
