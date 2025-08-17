import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const kLoadStatuses = <String>[
  'Draft',
  'Assigned',
  'En route',
  'Loading',
  'Delivered',
  'Cancelled'
];

class LoadsTab extends StatelessWidget {
  LoadsTab({super.key});

  final _loads = FirebaseFirestore.instance
      .collection('loads')
      .orderBy('createdAt', descending: true)
      .limit(200);

  String _normalize(String? s) {
    final v = (s ?? 'Draft').trim();
    return kLoadStatuses.firstWhere((x) => x.toLowerCase() == v.toLowerCase(),
        orElse: () => 'Draft');
  }

  Future<void> _updateStatus(String id, String status) async {
    await FirebaseFirestore.instance
        .collection('loads')
        .doc(id)
        .update({'status': status});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _loads.snapshots(),
      builder: (c, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No loads yet'));
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final d = docs[i];
            final m = d.data();
            final ref = (m['reference'] ?? '').toString();
            final status = _normalize(m['status'] as String?);
            final clientId = (m['clientId'] ?? '').toString();

            return ListTile(
              title: Text(ref.isEmpty ? '(no reference)' : ref),
              subtitle: Text('Client: ${clientId.isEmpty ? '—' : clientId}'),
              trailing: SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: kLoadStatuses.contains(status) ? status : null,
                  items: kLoadStatuses
                      .toSet()
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    final next = v ?? status;
                    if (next != status) {
                      _updateStatus(d.id, next);
                      ScaffoldMessenger.of(c).showSnackBar(
                          SnackBar(content: Text('Status → $next')));
                    }
                  },
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(), labelText: 'Status'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
