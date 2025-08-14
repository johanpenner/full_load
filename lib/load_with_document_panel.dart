import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'load_document_viewer.dart';

class LoadWithDocumentsPanel extends StatefulWidget {
  const LoadWithDocumentsPanel({super.key});

  @override
  State<LoadWithDocumentsPanel> createState() => _LoadWithDocumentsPanelState();
}

class _LoadWithDocumentsPanelState extends State<LoadWithDocumentsPanel> {
  Map<String, dynamic>? selectedLoad;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(title: const Text('Loads + Documents')),
      body: Row(
        children: [
          Expanded(
            flex: isWide ? 2 : 1,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('loads').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;

                    return ListTile(
                      title: Text("Load #: ${data['loadNumber'] ?? 'N/A'}"),
                      subtitle: Text("${data['client'] ?? 'Unknown'} → ${data['receiver'] ?? ''}"),
                      selected: selectedLoad?['loadNumber'] == data['loadNumber'],
                      onTap: () => setState(() => selectedLoad = data),
                    );
                  },
                );
              },
            ),
          ),
          if (isWide)
            VerticalDivider(width: 1, color: Colors.grey[300]),
          Expanded(
            flex: 3,
            child: selectedLoad != null
                ? LoadDocumentViewer(
                    documents: Map<String, dynamic>.from(selectedLoad!['documents'] ?? {}),
                    loadNumber: selectedLoad!['loadNumber'] ?? '',
                  )
                : const Center(child: Text('Select a load to view documents')),
          ),
        ],
      ),
    );
  }
}
