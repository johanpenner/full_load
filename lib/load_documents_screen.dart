import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

class LoadDocumentsScreen extends StatefulWidget {
  const LoadDocumentsScreen({super.key});

  @override
  State<LoadDocumentsScreen> createState() => _LoadDocumentsScreenState();
}

class _LoadDocumentsScreenState extends State<LoadDocumentsScreen> {
  String? selectedLoadId;

  Future<void> uploadFile(String category) async {
    if (selectedLoadId == null) return;

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      final files = result.paths.whereType<String>().toList();

      final docRef =
          FirebaseFirestore.instance.collection('loads').doc(selectedLoadId);
      final snap = await docRef.get();
      final data = snap.data()!;
      final existing = Map<String, dynamic>.from(data['documents'] ?? {});

      final updatedList = [...(existing[category] ?? []), ...files];
      existing[category] = updatedList;

      await docRef.update({'documents': existing});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$category file(s) uploaded')));
    }
  }

  Future<void> exportAllDocumentsAsZip() async {
    if (selectedLoadId == null) return;

    final docRef =
        FirebaseFirestore.instance.collection('loads').doc(selectedLoadId);
    final snap = await docRef.get();
    final data = snap.data()!;
    final documents = Map<String, dynamic>.from(data['documents'] ?? {});

    final encoder = ZipFileEncoder();
    final dir = await getApplicationDocumentsDirectory();
    final zipPath = "${dir.path}/load_${data['loadNumber']}_docs.zip";

    encoder.create(zipPath);

    documents.forEach((category, files) {
      for (var filePath in files) {
        final file = File(filePath);
        if (file.existsSync()) {
          encoder.addFile(file);
        }
      }
    });

    encoder.close();

    await Share.shareXFiles([XFile(zipPath)],
        text: 'Documents for Load ${data['loadNumber']}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Load Documents')),
      body: Column(
        children: [
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('loads')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final loads = snapshot.data!.docs;

              return DropdownButtonFormField<String>(
                value: selectedLoadId,
                decoration: const InputDecoration(labelText: 'Select Load'),
                items: loads.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DropdownMenuItem(
                    value: doc.id,
                    child: Text(data['loadNumber'] ?? 'Unnamed'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => selectedLoadId = val),
              );
            },
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload BOL'),
                onPressed: () => uploadFile('bol'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload Invoice'),
                onPressed: () => uploadFile('invoice'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload Receipt'),
                onPressed: () => uploadFile('receipt'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.archive),
            label: const Text('Export All Documents (ZIP)'),
            onPressed: exportAllDocumentsAsZip,
          )
        ],
      ),
    );
  }
}
