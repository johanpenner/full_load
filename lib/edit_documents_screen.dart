import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

class EditDocumentsScreen extends StatefulWidget {
  final String loadNumber;
  final Map<String, dynamic> documents;

  const EditDocumentsScreen({
    super.key,
    required this.loadNumber,
    required this.documents,
  });

  @override
  State<EditDocumentsScreen> createState() => _EditDocumentsScreenState();
}

class _EditDocumentsScreenState extends State<EditDocumentsScreen> {
  late Map<String, dynamic> documentMap;
  final Map<String, File> selectedFiles = {};
  double uploadProgress = 0;
  bool isUploading = false;
  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB
  final uploaderEmail = 'dispatcher@company.com'; // Replace with real auth

  @override
  void initState() {
    super.initState();
    documentMap = Map<String, dynamic>.from(widget.documents);
  }

  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (result != null) {
      for (final file in result.files) {
        if (file.path == null) continue;
        final selected = File(file.path!);
        final fileSize = await selected.length();
        if (fileSize > maxFileSizeBytes) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${file.name} is too large. Max 10MB.")),
          );
          continue;
        }
        final suggestedTag = path.basenameWithoutExtension(file.name);
        selectedFiles[suggestedTag] = selected;
      }
      setState(() {});
    }
  }

  Future<void> uploadAllFiles() async {
    setState(() {
      isUploading = true;
      uploadProgress = 0;
    });

    int total = selectedFiles.length;
    int done = 0;

    for (final entry in selectedFiles.entries) {
      final tag = _getVersionedTag(entry.key);
      final file = entry.value;
      final fileName = path.basename(file.path);
      final ref = FirebaseStorage.instance.ref().child('documents/$fileName');
      final uploadTask = ref.putFile(file);

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      documentMap[tag] = {
        'url': url,
        'uploadedBy': uploaderEmail,
        'timestamp': DateTime.now().toIso8601String(),
      };

      done++;
      setState(() => uploadProgress = done / total);
    }

    setState(() {
      selectedFiles.clear();
      isUploading = false;
    });
  }

  String _getVersionedTag(String baseTag) {
    if (!documentMap.containsKey(baseTag)) return baseTag;

    int version = 2;
    while (documentMap.containsKey("${baseTag}_v$version")) {
      version++;
    }
    return "${baseTag}_v$version";
  }

  Future<void> deleteDocument(String tag) async {
    final data = documentMap[tag];
    final url = data is String ? data : data['url'];
    if (url != null && url.contains('firebase')) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }
    setState(() => documentMap.remove(tag));
  }

  Future<void> saveChangesToFirestore() async {
    final loads = await FirebaseFirestore.instance
        .collection('loads')
        .where('loadNumber', isEqualTo: widget.loadNumber)
        .get();

    if (loads.docs.isNotEmpty) {
      final docId = loads.docs.first.id;
      await FirebaseFirestore.instance
          .collection('loads')
          .doc(docId)
          .update({'documents': documentMap});
    }

    if (mounted) Navigator.pop(context);
  }

  Widget _buildPreviewIcon(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png')) {
      return Image.network(url, width: 50, height: 50, fit: BoxFit.cover);
    } else if (lower.endsWith('.pdf')) {
      return const Icon(Icons.picture_as_pdf, size: 40, color: Colors.red);
    } else {
      return const Icon(Icons.insert_drive_file, size: 40, color: Colors.blue);
    }
  }

  Widget _buildFilePreview(String tag, File file) {
    final lower = file.path.toLowerCase();
    return ListTile(
      leading: lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.png')
          ? Image.file(file, width: 50, height: 50, fit: BoxFit.cover)
          : lower.endsWith('.pdf')
              ? const Icon(Icons.picture_as_pdf, size: 40, color: Colors.red)
              : const Icon(Icons.insert_drive_file,
                  size: 40, color: Colors.blue),
      title: Text(tag),
      trailing: IconButton(
        icon: const Icon(Icons.delete),
        onPressed: () => setState(() => selectedFiles.remove(tag)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Documents (${widget.loadNumber})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: saveChangesToFirestore,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Existing Documents",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...documentMap.entries.map((entry) {
            final docData = entry.value;
            final url = docData is String ? docData : docData['url'];
            final uploader = docData is Map ? docData['uploadedBy'] : null;
            final uploadedAt = docData is Map ? docData['timestamp'] : null;

            return Card(
              child: ListTile(
                leading: _buildPreviewIcon(url),
                title: Text(entry.key),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (uploader != null || uploadedAt != null)
                      Text("Uploaded by: $uploader\nAt: $uploadedAt",
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => deleteDocument(entry.key),
                ),
              ),
            );
          }),
          const Divider(height: 40),
          const Text("Upload New Documents",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Select Files'),
            onPressed: pickFiles,
          ),
          const SizedBox(height: 10),
          ...selectedFiles.entries
              .map((e) => _buildFilePreview(e.key, e.value)),
          if (isUploading)
            Column(
              children: [
                const SizedBox(height: 12),
                const Text("Uploading..."),
                LinearProgressIndicator(value: uploadProgress),
              ],
            ),
          if (selectedFiles.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: const Text("Upload All"),
              onPressed: isUploading ? null : uploadAllFiles,
            ),
        ],
      ),
    );
  }
}
