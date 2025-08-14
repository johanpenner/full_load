import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class LoadDetailScreen extends StatefulWidget {
  final String loadId;

  const LoadDetailScreen({super.key, required this.loadId});

  @override
  State<LoadDetailScreen> createState() => _LoadDetailScreenState();
}

class _LoadDetailScreenState extends State<LoadDetailScreen> {
  Map<String, dynamic> documents = {};

  @override
  void initState() {
    super.initState();
    loadDocuments();
  }

  Future<void> loadDocuments() async {
    final doc = await FirebaseFirestore.instance.collection('loads').doc(widget.loadId).get();
    final data = doc.data()!;
    setState(() {
      documents = Map<String, dynamic>.from(data['documents'] ?? {});
    });
  }

  bool isImage(String path) => path.toLowerCase().endsWith('.jpg') || path.toLowerCase().endsWith('.jpeg') || path.toLowerCase().endsWith('.png');
  bool isPDF(String path) => path.toLowerCase().endsWith('.pdf');

  void openFile(String path) async {
    if (await File(path).exists()) {
      await OpenFile.open(path);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('File not found: $path')));
    }
  }

  Future<void> deleteFile(String category, String path) async {
    documents[category]?.remove(path);
    if (documents[category]?.isEmpty ?? false) {
      documents.remove(category);
    }
    await FirebaseFirestore.instance.collection('loads').doc(widget.loadId).update({'documents': documents});
    setState(() {});
  }

  Future<void> retagFile(String oldCategory, String path) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Retag File'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'New Category')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Move')),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      documents[oldCategory]?.remove(path);
      if (documents[oldCategory]?.isEmpty ?? false) documents.remove(oldCategory);
      documents[result] = [...(documents[result] ?? []), path];
      await FirebaseFirestore.instance.collection('loads').doc(widget.loadId).update({'documents': documents});
      setState(() {});
    }
  }

  Future<void> addDocument() async {
    final categoryController = TextEditingController();
    final category = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Document'),
        content: TextField(controller: categoryController, decoration: const InputDecoration(labelText: 'Category')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, categoryController.text.trim()), child: const Text('Add')),
        ],
      ),
    );

    if (category != null && category.isNotEmpty) {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null) {
        final files = result.paths.whereType<String>().toList();
        documents[category] = [...(documents[category] ?? []), ...files];
        await FirebaseFirestore.instance.collection('loads').doc(widget.loadId).update({'documents': documents});
        setState(() {});
      }
    }
  }

  Future<void> generatePdfSummary() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text("Load Document Summary", style: pw.TextStyle(fontSize: 22)),
          pw.SizedBox(height: 10),
          ...documents.entries.map((e) => pw.Column(children: [
                pw.Text(e.key.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Bullet(text: e.value.map((f) => f.split(Platform.pathSeparator).last).join("\n")),
                pw.SizedBox(height: 8)
              ]))
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Load Documents'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: addDocument, tooltip: 'Add Document'),
          IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: generatePdfSummary, tooltip: 'Generate PDF Summary'),
        ],
      ),
      body: documents.isEmpty
          ? const Center(child: Text('No documents uploaded.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: documents.entries.map((entry) {
                final category = entry.key;
                final files = List<String>.from(entry.value);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: files.map((path) {
                        final fileName = path.split(Platform.pathSeparator).last;
                        final isImg = isImage(path);
                        return GestureDetector(
                          onTap: () => openFile(path),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              isImg
                                  ? Image.file(File(path), width: 100, height: 100, fit: BoxFit.cover)
                                  : Icon(isPDF(path) ? Icons.picture_as_pdf : Icons.insert_drive_file, size: 80),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => retagFile(category, path),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => deleteFile(category, path),
                                  )
                                ],
                              ),
                              SizedBox(width: 100, child: Text(fileName, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center))
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const Divider(),
                  ],
                );
              }).toList(),
            ),
    );
  }
}
