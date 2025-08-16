// lib/shippers_tab.dart
// Shippers with multi-locations & contacts. DEV mode enables Add/Edit/Delete for anyone.
// Turn kDevAllowAllWrites to false for production to respect roles.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ShippersTab extends StatefulWidget {
  const ShippersTab({super.key});

  @override
  State<ShippersTab> createState() => _ShippersTabState();
}

class _ShippersTabState extends State<ShippersTab> {
  static const bool kDevAllowAllWrites = true; // <- set false to gate by role

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

  String _oneLine(String s) =>
      s.replaceAll('\n', ', ').replaceAll(RegExp(r'\s+'), ' ').trim();
  bool _matches(String? s) => (s ?? '').toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shippers')),
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
                if (_canEdit)
                  ElevatedButton.icon(
                    onPressed: () => _openAddEditShipperDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('New Shipper'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('shippers')
                    .orderBy('name')
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
                          return _matches(m['name']) ||
                              _matches(m['mainAddress'] ?? m['address']) ||
                              _matches(m['mainPhone'] ?? m['phone']) ||
                              _matches(m['mainEmail'] ?? m['email']);
                        }).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('No shippers found.'));
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _shipperTile(filtered[i]),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _shipperTile(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final name = (m['name'] ?? '') as String;
    final mainAddress = (m['mainAddress'] ?? m['address'] ?? '') as String;
    final mainPhone = (m['mainPhone'] ?? m['phone'] ?? '') as String;
    final mainEmail = (m['mainEmail'] ?? m['email'] ?? '') as String;
    final locations = List<Map<String, dynamic>>.from(m['locations'] ?? []);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(name.isEmpty ? 'Unnamed' : name),
        subtitle: Text(_oneLine('$mainAddress • $mainPhone • $mainEmail')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: _canEdit ? 'Edit shipper' : 'View',
              icon: const Icon(Icons.edit),
              onPressed: () => _openAddEditShipperDialog(doc: d),
            ),
            IconButton(
              tooltip: _canDelete ? 'Delete shipper' : 'No permission',
              icon: const Icon(Icons.delete_outline),
              onPressed: _canDelete ? () => _confirmDeleteShipper(d) : null,
            ),
          ],
        ),
        children: [
          if (_canEdit)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: () => _openAddEditLocationDialog(d.id),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Add Location'),
                ),
              ),
            ),
          for (int i = 0; i < locations.length; i++)
            _locationCard(shipperId: d.id, index: i, location: locations[i]),
        ],
      ),
    );
  }

  Widget _locationCard(
      {required String shipperId,
      required int index,
      required Map<String, dynamic> location}) {
    final locName = (location['locationName'] ?? '') as String;
    final address = (location['address'] ?? '') as String;
    final type = (location['type'] ?? 'pickup') as String;
    final contacts =
        List<Map<String, dynamic>>.from(location['contacts'] ?? []);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(locName.isEmpty ? 'Location ${index + 1}' : locName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_oneLine('$address ($type)')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _canEdit ? 'Edit location' : 'View',
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  onPressed: () =>
                      _openAddEditLocationDialog(shipperId, index: index),
                ),
                IconButton(
                  tooltip: _canDelete ? 'Delete location' : 'No permission',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _canDelete
                      ? () => _confirmDeleteLocation(shipperId, index)
                      : null,
                ),
              ],
            ),
          ),
          for (int c = 0; c < contacts.length; c++)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 0, right: 0),
              leading: const Icon(Icons.person_outline),
              title: Text((contacts[c]['name'] ?? '') as String),
              subtitle: Text(_oneLine(
                  '${contacts[c]['position'] ?? ''} • ${contacts[c]['phone'] ?? ''} ext ${contacts[c]['ext'] ?? ''}')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _canEdit ? 'Edit contact' : 'View',
                    icon: const Icon(Icons.edit),
                    onPressed: () => _openAddEditContactDialog(shipperId, index,
                        contactIndex: c),
                  ),
                  IconButton(
                    tooltip: _canDelete ? 'Delete contact' : 'No permission',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _canDelete
                        ? () => _confirmDeleteContact(shipperId, index, c)
                        : null,
                  ),
                ],
              ),
            ),
          if (_canEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () => _openAddEditContactDialog(shipperId, index),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add Contact'),
              ),
            ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  // ---------- Shipper ----------
  Future<void> _openAddEditShipperDialog(
      {QueryDocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final isEdit = doc != null;
    final data = isEdit ? (doc.data()) : <String, dynamic>{};

    final name = TextEditingController(text: data['name'] ?? '');
    final mainAddress = TextEditingController(
        text: data['mainAddress'] ?? data['address'] ?? '');
    final mainPhone =
        TextEditingController(text: data['mainPhone'] ?? data['phone'] ?? '');
    final mainMobile = TextEditingController(text: data['mainMobile'] ?? '');
    final mainEmail =
        TextEditingController(text: data['mainEmail'] ?? data['email'] ?? '');
    final hours = TextEditingController(text: data['hoursOfOperation'] ?? '');
    final notes = TextEditingController(text: data['notes'] ?? '');

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Shipper' : 'New Shipper'),
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
                    decoration:
                        const InputDecoration(labelText: 'Company Name *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: mainAddress,
                      decoration:
                          const InputDecoration(labelText: 'Main Address')),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: mainPhone,
                      decoration:
                          const InputDecoration(labelText: 'Office Phone')),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: mainMobile,
                      decoration:
                          const InputDecoration(labelText: 'Mobile Phone')),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: mainEmail,
                      decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: hours,
                      decoration: const InputDecoration(
                          labelText: 'Hours of Operation')),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: notes,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      minLines: 1,
                      maxLines: 4),
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

                final payload = {
                  'name': name.text.trim(),
                  'nameLower': name.text.trim().toLowerCase(),
                  'mainAddress': mainAddress.text.trim(),
                  'mainPhone': mainPhone.text.trim(),
                  'mainMobile': mainMobile.text.trim(),
                  'mainEmail': mainEmail.text.trim(),
                  'hoursOfOperation': hours.text.trim(),
                  'notes': notes.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                _closeDialogNextFrame();

                try {
                  if (isEdit) {
                    await doc.reference.update(payload);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Shipper updated.')));
                    }
                  } else {
                    await FirebaseFirestore.instance
                        .collection('shippers')
                        .add({
                      ...payload,
                      'locations': [],
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Shipper added.')));
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
              label: Text(isEdit ? 'Save Changes' : 'Create Shipper'),
            ),
        ],
      ),
    );

    name.dispose();
    mainAddress.dispose();
    mainPhone.dispose();
    mainMobile.dispose();
    mainEmail.dispose();
    hours.dispose();
    notes.dispose();
  }

  Future<void> _confirmDeleteShipper(
      QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final name = (d.data()['name'] ?? '') as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Shipper?'),
        content: Text(
            'Delete "$name" and all locations/contacts? This cannot be undone.'),
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
            .showSnackBar(const SnackBar(content: Text('Shipper deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  // ---------- Location ----------
  Future<void> _openAddEditLocationDialog(String shipperId,
      {int? index}) async {
    final isEdit = index != null;
    final docRef =
        FirebaseFirestore.instance.collection('shippers').doc(shipperId);
    final snap = await docRef.get();
    final data = (snap.data() ?? <String, dynamic>{});
    final locations = List<Map<String, dynamic>>.from(data['locations'] ?? []);

    final existing = isEdit ? locations[index] : <String, dynamic>{};

    final locName = TextEditingController(text: existing['locationName'] ?? '');
    final address = TextEditingController(text: existing['address'] ?? '');
    String type = (existing['type'] ?? 'pickup') as String;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Location' : 'Add Location'),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: locName,
                  decoration:
                      const InputDecoration(labelText: 'Location Name')),
              const SizedBox(height: 8),
              TextField(
                  controller: address,
                  decoration: const InputDecoration(labelText: 'Address')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: type,
                items: const [
                  DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
                  DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
                  DropdownMenuItem(value: 'both', child: Text('Both')),
                ],
                onChanged: (v) => type = v ?? 'pickup',
                decoration: const InputDecoration(labelText: 'Type'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          if (_canEdit)
            ElevatedButton.icon(
              onPressed: () async {
                final payload = {
                  'locationName': locName.text.trim(),
                  'address': address.text.trim(),
                  'type': type,
                  'contacts': List<Map<String, dynamic>>.from(
                      existing['contacts'] ?? []),
                };

                _closeDialogNextFrame();

                try {
                  if (isEdit) {
                    locations[index] = payload;
                  } else {
                    locations.add(payload);
                  }
                  await docRef.update({
                    'locations': locations,
                    'updatedAt': FieldValue.serverTimestamp()
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(isEdit
                              ? 'Location updated.'
                              : 'Location added.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to save: $e')));
                  }
                }
              },
              icon: const Icon(Icons.save),
              label: Text(isEdit ? 'Save Changes' : 'Add Location'),
            ),
        ],
      ),
    );

    locName.dispose();
    address.dispose();
  }

  Future<void> _confirmDeleteLocation(String shipperId, int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Location?'),
        content: const Text('Remove this location and its contacts?'),
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
      final docRef =
          FirebaseFirestore.instance.collection('shippers').doc(shipperId);
      final snap = await docRef.get();
      final data = (snap.data() ?? <String, dynamic>{});
      final locations =
          List<Map<String, dynamic>>.from(data['locations'] ?? []);
      if (index >= 0 && index < locations.length) {
        locations.removeAt(index);
        await docRef.update({
          'locations': locations,
          'updatedAt': FieldValue.serverTimestamp()
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Location deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  // ---------- Contact ----------
  Future<void> _openAddEditContactDialog(String shipperId, int locationIndex,
      {int? contactIndex}) async {
    final isEdit = contactIndex != null;
    final docRef =
        FirebaseFirestore.instance.collection('shippers').doc(shipperId);
    final snap = await docRef.get();
    final data = (snap.data() ?? <String, dynamic>{});
    final locations = List<Map<String, dynamic>>.from(data['locations'] ?? []);
    final contacts = List<Map<String, dynamic>>.from(
        locations[locationIndex]['contacts'] ?? []);

    final existing = isEdit ? contacts[contactIndex] : <String, dynamic>{};

    final name = TextEditingController(text: existing['name'] ?? '');
    final position = TextEditingController(text: existing['position'] ?? '');
    final phone = TextEditingController(text: existing['phone'] ?? '');
    final email = TextEditingController(text: existing['email'] ?? '');
    final ext = TextEditingController(text: existing['ext'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Contact' : 'Add Contact'),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(
                  controller: position,
                  decoration: const InputDecoration(labelText: 'Position')),
              const SizedBox(height: 8),
              TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 8),
              TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 8),
              TextField(
                  controller: ext,
                  decoration: const InputDecoration(labelText: 'Ext')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          if (_canEdit)
            ElevatedButton.icon(
              onPressed: () async {
                final payload = {
                  'name': name.text.trim(),
                  'position': position.text.trim(),
                  'phone': phone.text.trim(),
                  'email': email.text.trim(),
                  'ext': ext.text.trim(),
                };

                _closeDialogNextFrame();

                try {
                  if (isEdit) {
                    contacts[contactIndex] = payload;
                  } else {
                    contacts.add(payload);
                  }
                  locations[locationIndex]['contacts'] = contacts;
                  await docRef.update({
                    'locations': locations,
                    'updatedAt': FieldValue.serverTimestamp()
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              isEdit ? 'Contact updated.' : 'Contact added.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to save: $e')));
                  }
                }
              },
              icon: const Icon(Icons.save),
              label: Text(isEdit ? 'Save Changes' : 'Add Contact'),
            ),
        ],
      ),
    );

    name.dispose();
    position.dispose();
    phone.dispose();
    email.dispose();
    ext.dispose();
  }

  Future<void> _confirmDeleteContact(
      String shipperId, int locationIndex, int contactIndex) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact?'),
        content: const Text('Remove this contact from the location?'),
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
      final docRef =
          FirebaseFirestore.instance.collection('shippers').doc(shipperId);
      final snap = await docRef.get();
      final data = (snap.data() ?? <String, dynamic>{});
      final locations =
          List<Map<String, dynamic>>.from(data['locations'] ?? []);
      final contacts = List<Map<String, dynamic>>.from(
          locations[locationIndex]['contacts'] ?? []);
      if (contactIndex >= 0 && contactIndex < contacts.length) {
        contacts.removeAt(contactIndex);
        locations[locationIndex]['contacts'] = contacts;
        await docRef.update({
          'locations': locations,
          'updatedAt': FieldValue.serverTimestamp()
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Contact deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }
}
