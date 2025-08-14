import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'document_viewer_screen.dart';

class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  File? selectedFile;
  String? fileName;
  String docType = 'BOL';
  bool isUploading = false;

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles();

    if (result != null && result.files.single.path != null) {
      setState(() {
        selectedFile = File(result.files.single.path!);
        fileName = path.basename(result.files.single.path!);
      });
    }
  }

  Future<void> uploadFile() async {
    if (selectedFile == null || fileName == null) return;

    setState(() {
      isUploading = true;
    });

    try {
      final ref = FirebaseStorage.instance.ref('documents/$fileName');
      await ref.putFile(selectedFile!);
      final downloadUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('documents').add({
        'name': fileName,
        'type': docType,
        'url': downloadUrl,
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Upload successful')),
      );

      setState(() {
        selectedFile = null;
        fileName = null;
        isUploading = false;
      });
    } catch (e) {
      setState(() {
        isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Document')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButton<String>(
              value: docType,
              onChanged: (value) {
                if (value != null) {
                  setState(() => docType = value);
                }
              },
              items: const [
                DropdownMenuItem(value: 'BOL', child: Text('Bill of Lading')),
                DropdownMenuItem(value: 'Receipt', child: Text('Receipt')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: pickFile,
              child: const Text('Select File'),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: fileName != null
                  ? Text('Selected: $fileName', key: const ValueKey(1))
                  : isUploading
                      ? const Text('Uploading...', key: ValueKey(2))
                      : const Text('No file selected', key: ValueKey(3)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: isUploading ? null : uploadFile,
              child: isUploading
                  ? const CircularProgressIndicator()
                  : const Text('Upload to Firebase'),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DocumentViewerScreen(),
                  ),
                );
              },
              child: const Text('📄 View Uploaded Documents'),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_box),
              label: const Text('➕ New Load Entry'),
              onPressed: () {
                Navigator.pushNamed(context, '/new-load');
              },
            ),
          ],
        ),
      ),
    );
  }
}
