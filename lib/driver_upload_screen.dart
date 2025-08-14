import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as path;
import 'package:firebase_auth/firebase_auth.dart';

class DriverUploadScreen extends StatefulWidget {
  const DriverUploadScreen({super.key});

  @override
  State<DriverUploadScreen> createState() => _DriverUploadScreenState();
}

class _DriverUploadScreenState extends State<DriverUploadScreen> {
  String? selectedLoadNumber;
  File? selectedFile;
  final tagController = TextEditingController();
  bool isUploading = false;
  double uploadProgress = 0;
  List<String> driverLoads = [];

  @override
  void initState() {
    super.initState();
    fetchDriverLoads();
  }

  Future<void> fetchDriverLoads() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final loadsSnapshot = await FirebaseFirestore.instance
        .collection('loads')
        .where('driverId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'Delivered')
        .get();

    setState(() {
      driverLoads = loadsSnapshot.docs.map((doc) => doc['loadNumber'].toString()).toList();
    });
  }

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => selectedFile = File(result.files.single.path!));
    }
  }

  Future<void> uploadDocument() async {
    if (selectedFile == null || selectedLoadNumber == null || tagController.text.trim().isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      isUploading = true;
      uploadProgress = 0;
    });

    final fileName = path.basename(selectedFile!.path);
    final ref = FirebaseStorage.instance.ref().child('documents/$fileName');
    final uploadTask = ref.putFile(selectedFile!);

    uploadTask.snapshotEvents.listen((event) {
      setState(() => uploadProgress = event.bytesTransferred / event.totalBytes);
    });

    final snapshot = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();

    final tag = tagController.text.trim();

    final loads = await FirebaseFirestore.instance
        .collection('loads')
        .where('loadNumber', isEqualTo: selectedLoadNumber)
        .get();

    if (loads.docs.isNotEmpty) {
      final docRef = loads.docs.first.reference;
      final existingDocs = loads.docs.first.data()['documents'] ?? {};

      existingDocs[tag] = {
        'url': downloadUrl,
        'uploadedBy': user.email ?? user.uid,
        'timestamp': DateTime.now().toIso8601String(),
      };

      await docRef.update({'documents': existingDocs});
    }

    setState(() {
      selectedFile = null;
      tagController.clear();
      isUploading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Document uploaded successfully')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Document Upload')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Load Number'),
            DropdownButtonFormField<String>(
              value: selectedLoadNumber,
              items: driverLoads.map((load) {
                return DropdownMenuItem(
                  value: load,
                  child: Text(load),
                );
              }).toList(),
              onChanged: (val) => setState(() => selectedLoadNumber = val),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: tagController,
              decoration: const InputDecoration(labelText: 'Document Tag (e.g. POD, Receipt)'),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(selectedFile == null ? 'Select File' : path.basename(selectedFile!.path)),
              onPressed: pickFile,
            ),
            const SizedBox(height: 20),
            if (isUploading)
              LinearProgressIndicator(value: uploadProgress),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Upload Document'),
              onPressed: isUploading ? null : uploadDocument,
            ),
          ],
        ),
      ),
    );
  }
}
