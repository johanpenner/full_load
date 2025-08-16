// lib/loads_tab.dart
// Loads: DEV mode enables Add/Edit/Delete; dialogs close next frame to avoid assert.
// Adjust fields to match your schema.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoadsTab extends StatefulWidget {
  const LoadsTab({super.key});

  @override
  State<LoadsTab> createState() => _LoadsTabState();
}

class _LoadsTabState extends State<LoadsTab> {
  static const bool kDevAllowAllWrites = true;

  final _searchCtrl = TextEditingController();
  String _query = '';
  String _role = 'viewer';

  bool get _canEdit =>
      kDevAllowAllWrites || _role == 'admin' || _role == 'dispatcher';
  bool get _canDelete =>
      kDevAllowAllWrites || _role == 'admin' || _role == 'dispatcher';

  @override
  void initState() {
    super.initState();
    _loadRole();
    _searchCtrl.addListener(
        () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  Future<void> _loadRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      setState(() => _role = (doc.data() ?? const {})['role'] ?? 'viewer');
    } catch (_) {
      setState(() => _role = 'viewer');
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _closeDialogNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    });
  }

  bool _matches(String? s) => (s ?? '').toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loads')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText:
                        'Search by reference, client, shipper, receiver, driver',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_canEdit)
                ElevatedButton.icon(
                  onPressed: () => _openAddEditDialog(),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('New Load'),
                ),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('loads')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final filtered = _query.isEmpty
                      ? docs
                      : docs.where((d) {
                          final m = d.data();
                          return _matches(m['ref']) ||
                              _matches(m['clientName']) ||
                              _matches(m['shipperName']) ||
                              _matches(m['receiverName']) ||
                              _matches(m['driverName']);
                        }).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('No loads found.'));
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final m = filtered[i].data();
                      return Card(
                        child: ListTile(
                          title: Text(
                              '${m['ref'] ?? '(no ref)'} — ${m['clientName'] ?? ''}'),
                          subtitle: Text(
                              '${m['shipperName'] ?? ''} → ${m['receiverName'] ?? ''} • ${m['status'] ?? 'open'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                  tooltip: _canEdit ? 'Edit' : 'View',
                                  icon: const Icon(Icons.edit),
                                  onPressed: () =>
                                      _openAddEditDialog(doc: filtered[i])),
                              IconButton(
                                  tooltip:
                                      _canDelete ? 'Delete' : 'No permission',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: _canDelete
                                      ? () => _confirmDelete(filtered[i])
                                      : null),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final ref = (d.data()['ref'] ?? '') as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Load?'),
        content: Text('Delete load "$ref"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await d.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Load deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _openAddEditDialog(
      {QueryDocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final isEdit = doc != null;
    final data = isEdit ? (doc.data()) : <String, dynamic>{};

    final ref = TextEditingController(text: data['ref'] ?? '');
    final clientName = TextEditingController(text: data['clientName'] ?? '');
    final shipperName = TextEditingController(text: data['shipperName'] ?? '');
    final receiverName =
        TextEditingController(text: data['receiverName'] ?? '');
    final driverName = TextEditingController(text: data['driverName'] ?? '');
    final status = TextEditingController(text: data['status'] ?? 'open');

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Load' : 'New Load'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                      controller: ref,
                      decoration:
                          const InputDecoration(labelText: 'Reference *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: clientName,
                      decoration:
                          const InputDecoration(labelText: 'Client Name')),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: shipperName,
                      decoration: const InputDecoration(labelText: 'Shipper')),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: receiverName,
                      decoration: const InputDecoration(labelText: 'Receiver')),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: driverName,
                      decoration: const InputDecoration(labelText: 'Driver')),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: status,
                      decoration: const InputDecoration(labelText: 'Status')),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          if (_canEdit)
            ElevatedButton.icon(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final user = FirebaseAuth.instance.currentUser;
                final payload = {
                  'ref': ref.text.trim(),
                  'clientName': clientName.text.trim(),
                  'shipperName': shipperName.text.trim(),
                  'receiverName': receiverName.text.trim(),
                  'driverName': driverName.text.trim(),
                  'status': status.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                  'updatedByUid': user?.uid,
                };

                _closeDialogNextFrame();

                try {
                  if (isEdit) {
                    await doc.reference.update(payload);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Load updated.')));
                    }
                  } else {
                    await FirebaseFirestore.instance.collection('loads').add({
                      ...payload,
                      'createdAt': FieldValue.serverTimestamp(),
                      'createdByUid': user?.uid,
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Load added.')));
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to save: $e')));
                  }
                }
              },
              icon: const Icon(Icons.save),
              label: Text(isEdit ? 'Save Changes' : 'Create Load'),
            ),
        ],
      ),
    );

    ref.dispose();
    clientName.dispose();
    shipperName.dispose();
    receiverName.dispose();
    driverName.dispose();
    status.dispose();
  }
}
