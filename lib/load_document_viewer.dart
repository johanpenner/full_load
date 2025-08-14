import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'edit_documents_screen.dart';
import 'fullscreen_image_viewer.dart';
import 'pdf_preview_screen.dart';

class LoadDocumentViewer extends StatefulWidget {
  final Map<String, dynamic> documents;
  final String loadNumber;

  const LoadDocumentViewer({super.key, required this.documents, required this.loadNumber});

  @override
  State<LoadDocumentViewer> createState() => _LoadDocumentViewerState();
}

class _LoadDocumentViewerState extends State<LoadDocumentViewer> {
  String searchQuery = '';
  String typeFilter = 'All';
  final List<String> typeOptions = ['All', 'PDF', 'Image'];
  String userRole = 'viewer';

  @override
  void initState() {
    super.initState();
    fetchUserRole();
  }

  Future<void> fetchUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final role = userDoc.data()?['role'] ?? 'viewer';
      setState(() => userRole = role);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredDocs = widget.documents.entries.where((entry) {
      final docType = entry.key.toLowerCase();
      final docData = entry.value;
      final uploader = docData is Map ? (docData['uploadedBy'] ?? '').toLowerCase() : '';
      final url = docData is String ? docData : docData['url'] ?? '';

      final matchesSearch = docType.contains(searchQuery) || uploader.contains(searchQuery);

      final isPDF = url.toLowerCase().endsWith('.pdf');
      final isImage = url.toLowerCase().endsWith('.jpg') || url.toLowerCase().endsWith('.jpeg') || url.toLowerCase().endsWith('.png');

      final matchesType = typeFilter == 'All' ||
          (typeFilter == 'PDF' && isPDF) ||
          (typeFilter == 'Image' && isImage);

      return matchesSearch && matchesType;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Documents for Load #${widget.loadNumber}'),
        actions: [
          if (userRole == 'admin' || userRole == 'dispatcher')
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Documents',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditDocumentsScreen(
                      loadNumber: widget.loadNumber,
                      documents: widget.documents,
                      userRole: userRole,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search by tag or uploader',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => searchQuery = value.toLowerCase()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: typeFilter,
                  decoration: const InputDecoration(labelText: 'Filter by Type'),
                  items: typeOptions.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                  onChanged: (value) => setState(() => typeFilter = value!),
                ),
              ],
            ),
          ),
          ...filteredDocs.map((entry) {
            final docType = entry.key;
            final docData = entry.value;
            final url = docData is String ? docData : docData['url'];
            final uploader = docData is Map ? docData['uploadedBy'] : null;
            final uploadedAt = docData is Map ? docData['timestamp'] : null;

            final isImage = url.toLowerCase().endsWith('.jpg') || url.toLowerCase().endsWith('.jpeg') || url.toLowerCase().endsWith('.png');
            final isPDF = url.toLowerCase().endsWith('.pdf');

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: ListTile(
                leading: isImage
                    ? Image.network(
                        url,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40),
                      )
                    : Icon(
                        isPDF ? Icons.picture_as_pdf : Icons.insert_drive_file,
                        size: 40,
                        color: isPDF ? Colors.red : Colors.blue,
                      ),
                title: Text(docType),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (uploader != null || uploadedAt != null)
                      Text("Uploaded by: $uploader\nAt: $uploadedAt",
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (choice) async {
                    if (choice == 'open') {
                      if (isImage) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullscreenImageViewer(imageUrl: url),
                          ),
                        );
                      } else if (isPDF) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PDFPreviewScreen(pdfUrl: url),
                          ),
                        );
                      } else {
                        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      }
                    } else if (choice == 'download') {
                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    } else if (choice == 'share') {
                      await Share.share(url);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'open', child: Text('Open')),
                    const PopupMenuItem(value: 'download', child: Text('Download')),
                    const PopupMenuItem(value: 'share', child: Text('Share')),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
