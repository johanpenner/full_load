// lib/receivers_tab.dart
// Receivers: list + full-screen editor (clean like Client).
// Save closes immediately; Firestore writes finish in background.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

/// =======================
/// Utils
/// =======================

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

String _oneLine(String s) =>
    s.replaceAll('\n', ', ').replaceAll(RegExp(r'\s+'), ' ').trim();

Future<void> _callNumber(BuildContext context, String? raw) async {
  final s = (raw ?? '').replaceAll(RegExp(r'[^0-9+*#]'), '');
  if (s.isEmpty) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No phone number')));
    return;
  }
  final uri = Uri(scheme: 'tel', path: s);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('This device cannot place calls')));
  }
}

/// =======================
/// Models
/// =======================

class Address {
  String line1, line2, city, region, postalCode, country;
  Address({
    this.line1 = '',
    this.line2 = '',
    this.city = '',
    this.region = '',
    this.postalCode = '',
    this.country = 'CA',
  });

  Map<String, dynamic> toMap() => {
        'line1': line1,
        'line2': line2, // kept for backward compatibility (not in UI)
        'city': city,
        'region': region,
        'postalCode': postalCode,
        'country': country,
      };

  factory Address.fromMap(Map<String, dynamic>? m) => Address(
        line1: (m?['line1'] ?? '').toString(),
        line2: (m?['line2'] ?? '').toString(), // ignored in UI
        city: (m?['city'] ?? '').toString(),
        region: (m?['region'] ?? '').toString(),
        postalCode: (m?['postalCode'] ?? '').toString(),
        country: (m?['country'] ?? 'CA').toString(),
      );
}

class PersonContact {
  String name, position, email, phone, ext;
  PersonContact({
    this.name = '',
    this.position = '',
    this.email = '',
    this.phone = '',
    this.ext = '',
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'position': position,
        'email': email,
        'phone': phone,
        'ext': ext
      };

  factory PersonContact.fromMap(Map<String, dynamic>? m) => PersonContact(
        name: (m?['name'] ?? '').toString(),
        position: (m?['position'] ?? '').toString(),
        email: (m?['email'] ?? '').toString(),
        phone: (m?['phone'] ?? '').toString(),
        ext: (m?['ext'] ?? '').toString(),
      );
}

class Receiver {
  String id;
  String name;
  Address address;
  String email; // main/site email
  String mobilePhone; // site mobile
  String workPhone; // site phone
  String workExt; // site ext
  String hours; // hours of operation (free text)
  String notes;

  // Optional higher-up / head office contact
  PersonContact headOffice;

  // Multiple on-site receiver contacts
  List<PersonContact> contacts;

  Receiver({
    this.id = '',
    this.name = '',
    Address? address,
    this.email = '',
    this.mobilePhone = '',
    this.workPhone = '',
    this.workExt = '',
    this.hours = '',
    this.notes = '',
    PersonContact? headOffice,
    List<PersonContact>? contacts,
  })  : address = address ?? Address(),
        headOffice = headOffice ?? PersonContact(),
        contacts = contacts ?? <PersonContact>[];

  Map<String, dynamic> toMap() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'address': address.toMap(),
        'email': email,
        'mobilePhone': mobilePhone,
        'workPhone': workPhone,
        'workExt': workExt,
        'hours': hours,
        'notes': notes,
        'headOffice': headOffice.toMap(),
        'contacts': contacts.map((c) => c.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
      };

  factory Receiver.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    Address addr;
    if (m['address'] is Map) {
      addr = Address.fromMap(m['address'] as Map<String, dynamic>);
    } else {
      addr = Address(line1: (m['mainAddress'] ?? '').toString());
    }
    final contacts = (m['contacts'] is List)
        ? (m['contacts'] as List)
            .map((x) => PersonContact.fromMap(x as Map<String, dynamic>?))
            .toList()
        : <PersonContact>[];
    final ho = (m['headOffice'] is Map)
        ? PersonContact.fromMap(m['headOffice'] as Map<String, dynamic>)
        : PersonContact(
            name: (m['headOfficeName'] ?? '').toString(),
            email: (m['headOfficeEmail'] ?? '').toString(),
            phone: (m['headOfficePhone'] ?? '').toString(),
            ext: (m['headOfficeExt'] ?? '').toString(),
          );
    return Receiver(
      id: d.id,
      name: (m['name'] ?? '').toString(),
      address: addr,
      email: (m['email'] ?? m['mainEmail'] ?? '').toString(),
      mobilePhone: (m['mobilePhone'] ?? m['mainMobile'] ?? '').toString(),
      workPhone: (m['workPhone'] ?? m['mainPhone'] ?? '').toString(),
      workExt: (m['workExt'] ?? '').toString(),
      hours: (m['hours'] ?? '').toString(),
      notes: (m['notes'] ?? '').toString(),
      headOffice: ho,
      contacts: contacts,
    );
  }
}

/// =======================
/// Receivers Tab (List)
/// =======================

class ReceiversTab extends StatefulWidget {
  const ReceiversTab({super.key});
  @override
  State<ReceiversTab> createState() => _ReceiversTabState();
}

class _ReceiversTabState extends State<ReceiversTab> {
  static const bool kDevAllowAllWrites = true; // Set false for role-gated
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

  void _handleResult(dynamic result) {
    if (result is! Map) return;
    final action = result['action']?.toString();
    final name = (result['name']?.toString().trim().isNotEmpty ?? false)
        ? result['name'].toString()
        : 'Receiver';

    String? msg;
    if (action == 'created') msg = 'Saved "$name".';
    if (action == 'updated') msg = 'Updated "$name".';
    if (action == 'deleted') msg = 'Deleted "$name".';
    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('receivers')
        .orderBy('nameLower')
        .limit(300);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receivers'),
        actions: [
          if (_canEdit)
            IconButton(
              tooltip: 'New receiver',
              icon: const Icon(Icons.add),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReceiverEditScreen()),
                );
                _handleResult(result);
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, address, phone, or email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: q.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs =
                      snap.data!.docs.map((d) => Receiver.fromDoc(d)).toList();

                  final filtered = _query.isEmpty
                      ? docs
                      : docs.where((r) {
                          final hay = [
                            r.name,
                            r.address.line1,
                            r.address.city,
                            r.address.region,
                            r.email,
                            r.mobilePhone,
                            r.workPhone,
                          ].join(' ').toLowerCase();
                          return hay.contains(_query);
                        }).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('No receivers found.'));
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = filtered[i];
                      final subtitle = _oneLine(
                          '${r.address.line1} ${r.address.city} ${r.address.region} ${r.address.postalCode} • ${r.email}');
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.store)),
                        title: Text(r.name.isEmpty ? 'Unnamed' : r.name),
                        subtitle: Text(subtitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip:
                                  r.workPhone.isEmpty ? 'No phone' : 'Call',
                              icon: const Icon(Icons.call),
                              onPressed: r.workPhone.isEmpty
                                  ? null
                                  : () => _callNumber(context, r.workPhone),
                            ),
                            if (_canDelete)
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _confirmDelete(r),
                              ),
                            IconButton(
                              tooltip: _canEdit ? 'Edit' : 'View',
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          ReceiverEditScreen(receiverId: r.id)),
                                );
                                _handleResult(result);
                              },
                            ),
                          ],
                        ),
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    ReceiverEditScreen(receiverId: r.id)),
                          );
                          _handleResult(result);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Receiver r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Receiver?'),
        content: Text('Delete "${r.name.isEmpty ? 'this receiver' : r.name}"? '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('receivers')
          .doc(r.id)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Receiver deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }
}

/// =======================
/// Editor
/// =======================

class ReceiverEditScreen extends StatefulWidget {
  final String? receiverId;
  const ReceiverEditScreen({super.key, this.receiverId});

  @override
  State<ReceiverEditScreen> createState() => _ReceiverEditScreenState();
}

class _ReceiverEditScreenState extends State<ReceiverEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _nameFocus = FocusNode();

  bool _saving = false;
  Receiver _receiver = Receiver();

  // Controllers
  final _name = TextEditingController();

  final _addr1 = TextEditingController(),
      _city = TextEditingController(),
      _region = TextEditingController(),
      _postal = TextEditingController(),
      _country = TextEditingController(text: 'CA');

  final _email = TextEditingController(),
      _mobile = TextEditingController(),
      _work = TextEditingController(),
      _ext = TextEditingController();

  final _hours = TextEditingController(), _notes = TextEditingController();

  // Head Office
  final _hoName = TextEditingController(),
      _hoPhone = TextEditingController(),
      _hoExt = TextEditingController(),
      _hoEmail = TextEditingController();

  List<PersonContact> _contacts = <PersonContact>[];

  @override
  void initState() {
    super.initState();
    if (widget.receiverId != null) _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _nameFocus.dispose();
    for (final c in [
      _name,
      _addr1,
      _city,
      _region,
      _postal,
      _country,
      _email,
      _mobile,
      _work,
      _ext,
      _hours,
      _notes,
      _hoName,
      _hoPhone,
      _hoExt,
      _hoEmail,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance
        .collection('receivers')
        .doc(widget.receiverId!)
        .get();
    if (!doc.exists) return;
    setState(() {
      _receiver = Receiver.fromDoc(doc);
      _name.text = _receiver.name;
      _addr1.text = _receiver.address.line1;
      // address.line2 intentionally ignored/hidden
      _city.text = _receiver.address.city;
      _region.text = _receiver.address.region;
      _postal.text = _receiver.address.postalCode;
      _country.text = _receiver.address.country;
      _email.text = _receiver.email;
      _mobile.text = _receiver.mobilePhone;
      _work.text = _receiver.workPhone;
      _ext.text = _receiver.workExt;
      _hours.text = _receiver.hours;
      _notes.text = _receiver.notes;
      _hoName.text = _receiver.headOffice.name;
      _hoPhone.text = _receiver.headOffice.phone;
      _hoExt.text = _receiver.headOffice.ext;
      _hoEmail.text = _receiver.headOffice.email;
      _contacts = [..._receiver.contacts];
    });
  }

  void _popNextFrame(Map<String, dynamic> result) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop(result);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      if (_name.text.trim().isEmpty) {
        _nameFocus.requestFocus();
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Receiver name is required')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fix highlighted fields')));
      }
      return;
    }

    final isNew = widget.receiverId == null;
    setState(() => _saving = true);

    // Build payload (no line 2)
    final payload = Receiver(
      id: widget.receiverId ?? '',
      name: _name.text.trim(),
      address: Address(
        line1: _addr1.text.trim(),
        line2: '', // removed from UI & payload
        city: _city.text.trim(),
        region: _region.text.trim(),
        postalCode: _postal.text.trim(),
        country: _country.text.trim().isEmpty ? 'CA' : _country.text.trim(),
      ),
      email: _email.text.trim(),
      mobilePhone: _mobile.text.trim(),
      workPhone: _work.text.trim(),
      workExt: _ext.text.trim(),
      hours: _hours.text.trim(),
      notes: _notes.text.trim(),
      headOffice: PersonContact(
        name: _hoName.text.trim(),
        phone: _hoPhone.text.trim(),
        ext: _hoExt.text.trim(),
        email: _hoEmail.text.trim(),
      ),
      contacts: _contacts,
    );

    // Close immediately like Client
    final result = {
      'action': isNew ? 'created' : 'updated',
      'name': payload.name
    };
    _popNextFrame(result);

    // Finish write in background
    () async {
      try {
        final ref = FirebaseFirestore.instance.collection('receivers');
        if (isNew) {
          await ref.add(payload.toMap());
        } else {
          await ref.doc(widget.receiverId!).update(payload.toMap());
        }
      } catch (_) {}
    }();
  }

  Future<void> _confirmDelete() async {
    if (widget.receiverId == null) return;
    final name =
        _name.text.trim().isEmpty ? 'this receiver' : _name.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Receiver?'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('receivers')
          .doc(widget.receiverId!)
          .delete();
      _popNextFrame({'action': 'deleted', 'name': name});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  InputDecoration _dec(String label, [String? hint, Widget? suffix]) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    final canDelete = widget.receiverId != null;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.receiverId == null ? 'New Receiver' : 'Edit Receiver'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Name
                TextFormField(
                  controller: _name,
                  focusNode: _nameFocus,
                  decoration: _dec('Receiver Name *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Address (no line 2)
                _addrBlock(
                    'Address', _addr1, _city, _region, _postal, _country),

                const Divider(height: 24),

                // Site contact
                Row(children: [
                  Expanded(
                      child: TextFormField(
                          controller: _email, decoration: _dec('Email'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextFormField(
                          controller: _mobile, decoration: _dec('Mobile'))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _work,
                      decoration: _dec(
                        'Work Phone',
                        null,
                        IconButton(
                          icon: const Icon(Icons.call),
                          onPressed: () => _callNumber(context, _work.text),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                        controller: _ext, decoration: _dec('Ext')),
                  ),
                ]),

                const SizedBox(height: 12),
                TextFormField(
                  controller: _hours,
                  decoration:
                      _dec('Hours of Operation (e.g., Mon-Fri 7:00–17:00)'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notes,
                  maxLines: 4,
                  decoration: _dec('Notes / Special Instructions'),
                ),

                // Head Office
                const Divider(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Head Office (optional)',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                TextFormField(controller: _hoName, decoration: _dec('Name')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _hoPhone,
                      decoration: _dec(
                        'Phone',
                        null,
                        IconButton(
                          icon: const Icon(Icons.call),
                          onPressed: () => _callNumber(context, _hoPhone.text),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                        controller: _hoExt, decoration: _dec('Ext')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                        controller: _hoEmail, decoration: _dec('Email')),
                  ),
                ]),

                // Contacts
                const Divider(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('On-Site Receiver Contacts',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                for (int i = 0; i < _contacts.length; i++)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(
                        _contacts[i].name.isEmpty
                            ? 'Contact ${i + 1}'
                            : _contacts[i].name,
                      ),
                      subtitle: Text(_oneLine(
                          '${_contacts[i].position} • ${_contacts[i].phone} ext ${_contacts[i].ext} • ${_contacts[i].email}')),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit),
                            onPressed: () => _openContactDialog(
                                index: i, existing: _contacts[i]),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                setState(() => _contacts.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openContactDialog(),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add Contact'),
                  ),
                ),

                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Receiver'),
                ),
                if (canDelete) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Danger zone',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.error),
                    ),
                    onPressed: _confirmDelete,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Delete receiver'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Address block WITHOUT Line 2
  Widget _addrBlock(
    String title,
    TextEditingController l1,
    TextEditingController city,
    TextEditingController region,
    TextEditingController postal,
    TextEditingController country,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(controller: l1, decoration: _dec('Street Address')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(controller: city, decoration: _dec('City'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: region, decoration: _dec('Province/State'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: postal, decoration: _dec('Postal/ZIP Code'))),
          const SizedBox(width: 8),
          Expanded(
              child:
                  TextField(controller: country, decoration: _dec('Country'))),
        ]),
      ],
    );
  }

  Future<void> _openContactDialog({int? index, PersonContact? existing}) async {
    final isEdit = index != null && existing != null;

    final name = TextEditingController(text: existing?.name ?? '');
    final position = TextEditingController(text: existing?.position ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    final ext = TextEditingController(text: existing?.ext ?? '');
    final email = TextEditingController(text: existing?.email ?? '');

    final ok = await showDialog<bool>(
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
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: phone,
                        decoration: const InputDecoration(labelText: 'Phone'))),
                const SizedBox(width: 8),
                SizedBox(
                    width: 120,
                    child: TextField(
                        controller: ext,
                        decoration: const InputDecoration(labelText: 'Ext'))),
              ]),
              const SizedBox(height: 8),
              TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isEdit ? 'Save' : 'Add')),
        ],
      ),
    );

    if (ok == true) {
      final pc = PersonContact(
        name: name.text.trim(),
        position: position.text.trim(),
        phone: phone.text.trim(),
        ext: ext.text.trim(),
        email: email.text.trim(),
      );
      setState(() {
        if (isEdit) {
          _contacts[index!] = pc;
        } else {
          _contacts.add(pc);
        }
      });
    }
  }
}
