import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'update_load_status.dart';

class LoadListScreen extends StatelessWidget {
  const LoadListScreen({super.key});

  Future<void> exportZip(Map<String, dynamic> documents, String loadNumber) async {
    final encoder = ZipFileEncoder();
    final dir = await getApplicationDocumentsDirectory();
    final zipPath = '${dir.path}/load_${loadNumber}_documents.zip';
    encoder.create(zipPath);

    documents.forEach((category, paths) {
      for (var p in paths) {
        final file = File(p);
        if (file.existsSync()) {
          encoder.addFile(file);
        }
      }
    });

    encoder.close();
    await Share.shareXFiles([XFile(zipPath)], text: 'Documents for Load $loadNumber');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All Loads')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('loads').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final docId = docs[index].id;
              String selectedStatus = data['status'] ?? 'Planned';

              return Card(
                margin: const EdgeInsets.all(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Load #${data['loadNumber']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text("Driver: ${data['driverId'] ?? 'Unassigned'}"),
                      Text("Pickup: ${data['pickupDate'] ?? ''}"),
                      Text("Delivery: ${data['deliveryDate'] ?? ''}"),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedStatus,
                              decoration: const InputDecoration(labelText: 'Status'),
                              items: const [
                                DropdownMenuItem(value: 'Planned', child: Text('Planned')),
                                DropdownMenuItem(value: 'Assigned', child: Text('Assigned')),
                                DropdownMenuItem(value: 'En Route', child: Text('En Route')),
                                DropdownMenuItem(value: 'Delivered', child: Text('Delivered')),
                              ],
                              onChanged: (val) {
                                if (val != null) selectedStatus = val;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('Update'),
                            onPressed: () async {
                              await updateLoadStatus(context, docId, selectedStatus);
                            },
                          ),
                        ],
                      ),
                      const Divider(),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.archive),
                        label: const Text('Export Documents (ZIP)'),
                        onPressed: () async {
                          final documents = Map<String, dynamic>.from(data['documents'] ?? {});
                          if (documents.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No documents to export.')));
                          } else {
                            await exportZip(documents, data['loadNumber'] ?? 'Unknown');
                          }
                        },
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
