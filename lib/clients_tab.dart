// lib/clients_tab.dart
// Clients: DEV mode allows Add/Edit/Delete for anyone; dialogs close next frame to avoid assert.
// Turn kDevAllowAllWrites to false for production if you want role-gated editing.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClientsTab extends StatefulWidget {
  const ClientsTab({super.key});

  @override
  State<ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends State<ClientsTab> {
  // ===== DEV override =====
  static const bool kDevAllowAllWrites = true; // <- set false to respect Firestore roles

  final _searchCtrl = TextEditingController();
  String _query = '';

  String _role = 'viewer';
  bool get _canEdit => kDevAllowAllWrites || _role == 'admin' || _role == 'dispatcher';
  bool get _canDelete => kDevAllowAllWrites || _role == 'admin' || _role == 'dispatcher';

  @override
  void initState() {
    super.initState();
    _loadRole();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  Future<void> _loadRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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

  // Close dialogs safely on next frame to avoid: `_dependents.isEmpty` assert
  void _closeDialogNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    });
  }

  // ---- coercion helpers ----
  String _asText(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();
    if (v is List) return v.map(_asText).where((s) => s.isNotEmpty).join(', ');
    if (v is Map) return v.values.map(_asText).where((s) => s.isNotEmpty).join(', ');
    return v.toString();
  }

  String _oneLine(dynamic v) =>
      _asText(v).replaceAll('\n', ', ').replaceAll(RegExp(r'\s+'), ' ').trim();
  bool _matches(dynamic v) => _asText(v).toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name, address, phone, or email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Always visible so you can add clients any time
                ElevatedButton.icon(
                  onPressed: () => _openAddEditDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('New Client'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('clients').orderBy('name').snapshots(),
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
                          return _matches(m['name']) ||
                              _matches(m['address']) ||
                              _matches(m['phone']) ||
                              _matches(m['email']) ||
                              _matches(m['notes']);
                        }).toList();

                  if (filtered.isEmpty) return const Center(child: Text('No clients found.'));

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Address')),
                          DataColumn(label: Text('Notes')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: [for (final d in filtered) _row(d)],
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  DataRow _row(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return DataRow(cells: [
      DataCell(Text(_asText(m['name']))),
      DataCell(Text(_asText(m['phone']))),
      DataCell(Text(_asText(m['email']))),
      DataCell(SizedBox(width: 280, child: Text(_oneLine(m['address'])))),
      DataCell(SizedBox(width: 220, child: Text(_oneLine(m['notes'])))),
      DataCell(Row(children: [
        IconButton(
          tooltip: _canEdit ? 'Edit' : 'View',
          icon: const Icon(Icons.edit),
          onPressed: () => _openAddEditDialog(doc: d),
        ),
        IconButton(
          tooltip: _canDelete ? 'Delete' : 'No permission',
          icon: const Icon(Icons.delete_outline),
          onPressed: _canDelete ? () => _confirmDelete(d) : null,
        ),
      ])),
    ]);
  }

  Future<void> _confirmDelete(QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final name = _asText(d.data()['name']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Client?'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await d.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _openAddEditDialog({QueryDocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final isEdit = doc != null;
    final data = isEdit ? (doc!.data()) : <String, dynamic>{};

    final name = TextEditingController(text: _asText(data['name']));
    final phone = TextEditingController(text: _asText(data['phone']));
    final email = TextEditingController(text: _asText(data['email']));
    final address = TextEditingController(text: _asText(data['address']));
    final notes = TextEditingController(text: _asText(data['notes']));

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Client' : 'New Client'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Client Name *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                  const SizedBox(height: 8),
                  TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 8),
                  TextFormField(controller: address, decoration: const InputDecoration(labelText: 'Address'), minLines: 1, maxLines: 3),
                  const SizedBox(height: 8),
                  TextFormField(controller: notes, decoration: const InputDecoration(labelText: 'Notes'), minLines: 1, maxLines: 5),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final user = FirebaseAuth.instance.currentUser;
              final payload = {
                'name': name.text.trim(),
                'nameLower': name.text.trim().toLowerCase(),
                'phone': phone.text.trim(),
                'email': email.text.trim(),
                'address': address.text.trim(),
                'notes': notes.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
                'updatedByUid': user?.uid,
              };

              // Close dialog on next frame to avoid framework assertion
              _closeDialogNextFrame();

              try {
                if (isEdit) {
                  await doc!.reference.update(payload);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client updated.')));
                  }
                } else {
                  await FirebaseFirestore.instance.collection('clients').add({
                    ...payload,
                    'createdAt': FieldValue.serverTimestamp(),
                    'createdByUid': user?.uid,
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client added.')));
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
                }
              }
            },
            icon: const Icon(Icons.save),
            label: Text(isEdit ? 'Save Changes' : 'Create Client'),
          ),
        ],
      ),
    );

    name.dispose();
    phone.dispose();
    email.dispose();
    address.dispose();
    notes.dispose();
  }
}
