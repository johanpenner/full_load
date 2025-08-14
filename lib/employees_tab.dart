// lib/employees_tab.dart
// Employees: DEV mode enables Add/Edit/Delete; dialogs close next frame to avoid assert.
// Turn kDevAllowAllWrites to false for production.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EmployeesTab extends StatefulWidget {
  const EmployeesTab({super.key});

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab> {
  static const bool kDevAllowAllWrites = true;

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
      appBar: AppBar(title: const Text('Employees')),
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
                    hintText: 'Search by name, role, phone, or email',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_canEdit)
                ElevatedButton.icon(
                  onPressed: () => _openAddEditDialog(),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('New Employee'),
                ),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('employees').orderBy('name').snapshots(),
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
                              _matches(m['email']) ||
                              _matches(m['role']) ||
                              _matches(m['phone']);
                        }).toList();
                  if (filtered.isEmpty) return const Center(child: Text('No employees found.'));

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Role')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Email')),
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
      DataCell(Text((m['name'] ?? '') as String)),
      DataCell(Text((m['role'] ?? '') as String)),
      DataCell(Text((m['phone'] ?? '') as String)),
      DataCell(Text((m['email'] ?? '') as String)),
      DataCell(Row(children: [
        IconButton(tooltip: _canEdit ? 'Edit' : 'View', icon: const Icon(Icons.edit), onPressed: () => _openAddEditDialog(doc: d)),
        IconButton(tooltip: _canDelete ? 'Delete' : 'No permission', icon: const Icon(Icons.delete_outline), onPressed: _canDelete ? () => _confirmDelete(d) : null),
      ])),
    ]);
  }

  Future<void> _confirmDelete(QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final name = (d.data()['name'] ?? '') as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Employee?'),
        content: Text('Delete "$name"?'),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee deleted.')));
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

    final name = TextEditingController(text: data['name'] ?? '');
    final role = TextEditingController(text: data['role'] ?? '');
    final phone = TextEditingController(text: data['phone'] ?? '');
    final email = TextEditingController(text: data['email'] ?? '');

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Employee' : 'New Employee'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                  const SizedBox(height: 8),
                  TextFormField(controller: role, decoration: const InputDecoration(labelText: 'Role')),
                  const SizedBox(height: 8),
                  TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                  const SizedBox(height: 8),
                  TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          if (_canEdit)
            ElevatedButton.icon(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final payload = {
                  'name': name.text.trim(),
                  'nameLower': name.text.trim().toLowerCase(),
                  'role': role.text.trim(),
                  'phone': phone.text.trim(),
                  'email': email.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                _closeDialogNextFrame();

                try {
                  if (isEdit) {
                    await doc!.reference.update(payload);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee updated.')));
                    }
                  } else {
                    await FirebaseFirestore.instance.collection('employees').add({
                      ...payload,
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee added.')));
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
                  }
                }
              },
              icon: const Icon(Icons.save),
              label: Text(isEdit ? 'Save Changes' : 'Create Employee'),
            ),
        ],
      ),
    );

    name.dispose();
    role.dispose();
    phone.dispose();
    email.dispose();
  }
}
