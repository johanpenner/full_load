import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TrucksScreen extends StatefulWidget {
  const TrucksScreen({super.key});
  @override
  State<TrucksScreen> createState() => _TrucksScreenState();
}

class _TrucksScreenState extends State<TrucksScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(
        () => setState(() => _q = _search.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('trucks')
        .orderBy('nameLower', descending: false)
        .limit(500)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trucks'),
        actions: [
          IconButton(
            tooltip: 'Add truck',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search truck # or name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snap) {
                  if (snap.hasError)
                    return Center(child: Text('Error: ${snap.error}'));
                  if (!snap.hasData)
                    return const Center(child: CircularProgressIndicator());
                  var docs = snap.data!.docs;
                  if (_q.isNotEmpty) {
                    docs = docs.where((d) {
                      final m = d.data();
                      final hay = [
                        (m['number'] ?? '').toString(),
                        (m['name'] ?? '').toString(),
                      ].join(' ').toLowerCase();
                      return hay.contains(_q);
                    }).toList();
                  }
                  if (docs.isEmpty)
                    return const Center(child: Text('No trucks'));
                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data();
                      final numStr = (m['number'] ?? '').toString();
                      final name = (m['name'] ?? '').toString();
                      final plate = (m['plate'] ?? '').toString();
                      return ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.local_shipping_outlined)),
                        title: Text(numStr.isEmpty ? '(no number)' : numStr),
                        subtitle: Text([name, plate]
                            .where((s) => s.isNotEmpty)
                            .join(' • ')),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit),
                              onPressed: () =>
                                  _openEditor(id: d.id, initial: m),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final ok = await _confirm(
                                    context, 'Delete this truck?');
                                if (ok) {
                                  await FirebaseFirestore.instance
                                      .collection('trucks')
                                      .doc(d.id)
                                      .delete();
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Truck'),
      ),
    );
  }

  Future<void> _openEditor({String? id, Map<String, dynamic>? initial}) async {
    final numCtrl =
        TextEditingController(text: (initial?['number'] ?? '').toString());
    final nameCtrl =
        TextEditingController(text: (initial?['name'] ?? '').toString());
    final plateCtrl =
        TextEditingController(text: (initial?['plate'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(id == null ? 'New Truck' : 'Edit Truck'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: numCtrl,
                  decoration: const InputDecoration(labelText: 'Truck #')),
              const SizedBox(height: 8),
              TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Name/Description')),
              const SizedBox(height: 8),
              TextField(
                  controller: plateCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Plate (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      final data = {
        'number': numCtrl.text.trim(),
        'name': nameCtrl.text.trim(),
        'nameLower': nameCtrl.text.trim().toLowerCase(),
        'plate': plateCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      };
      final col = FirebaseFirestore.instance.collection('trucks');
      if (id == null) {
        await col.add(data);
      } else {
        await col.doc(id).update(data);
      }
    }
  }

  Future<bool> _confirm(BuildContext context, String text) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm'),
            content: Text(text),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Yes')),
            ],
          ),
        ) ??
        false;
  }
}
