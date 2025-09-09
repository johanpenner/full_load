// lib/shippers_tab.dart
// Shippers: list + full-screen editor (clean like Clients/Receivers).
// Save closes immediately; Firestore writes finish in background.
// NOTE: No Address Line 2 anywhere in the UI or payload.
// Updated to handle authentication: sign in anonymously if not authenticated.
// Ensure Firebase Anonymous Auth is enabled in console, and Firestore rules allow reads/writes if request.auth != null.

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

Future<void> _openMaps(String address) async {
  if (address.trim().isEmpty) return;
  // Works on iOS/Android/Desktop by delegating to default maps handler
  final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// =======================
/// Models
/// =======================

class Address {
  String line1, city, region, postalCode, country;
  Address({
    this.line1 = '',
    this.city = '',
    this.region = '',
    this.postalCode = '',
    this.country = 'CA',
  });

  Map<String, dynamic> toMap() => {
        'line1': line1,
        'city': city,
        'region': region,
        'postalCode': postalCode,
        'country': country,
      };

  factory Address.fromMap(Map<String, dynamic>? m) => Address(
        line1: (m?['line1'] ?? '').toString(),
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

class Shipper {
  String id, name, legacyId, legacyName;
  Address address;
  String email, mobilePhone, phone, ext, fax, website;
  String hours, notes;
  List<PersonContact> contacts;
  bool isActive;

  Shipper({
    required this.id,
    this.name = '',
    this.legacyId = '',
    this.legacyName = '',
    required this.address,
    this.email = '',
    this.mobilePhone = '',
    this.phone = '',
    this.ext = '',
    this.fax = '',
    this.website = '',
    this.hours = '',
    this.notes = '',
    required this.contacts,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'nameLower': name.toLowerCase(),
        'legacyId': legacyId,
        'legacyName': legacyName,
        'address': address.toMap(),
        'email': email,
        'mobilePhone': mobilePhone,
        'phone': phone,
        'ext': ext,
        'fax': fax,
        'website': website,
        'hours': hours,
        'notes': notes,
        'contacts': contacts.map((c) => c.toMap()).toList(),
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory Shipper.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data()!;
    return Shipper(
      id: doc.id,
      name: (m['name'] ?? '').toString(),
      legacyId: (m['legacyId'] ?? m['LegacyID'] ?? '').toString(), // compat
      legacyName:
          (m['legacyName'] ?? m['LegacyName'] ?? '').toString(), // compat
      address: Address.fromMap(m['address']),
      email: (m['email'] ?? m['Email'] ?? '').toString(), // compat
      mobilePhone: (m['mobilePhone'] ?? m['MobilePhone'] ?? '').toString(),
      phone: (m['phone'] ?? m['Phone'] ?? '').toString(),
      ext: (m['ext'] ?? m['Ext'] ?? '').toString(),
      fax: (m['fax'] ?? m['Fax'] ?? '').toString(),
      website: (m['website'] ?? m['Website'] ?? '').toString(),
      hours: (m['hours'] ?? m['Hours'] ?? '').toString(),
      notes: (m['notes'] ?? m['Notes'] ?? '').toString(),
      contacts: (m['contacts'] as List<dynamic>? ?? [])
          .map((c) => PersonContact.fromMap(c))
          .toList(),
      isActive: m['isActive'] as bool? ?? true,
    );
  }
}

/// =======================
/// List Screen
/// =======================

class ShippersTab extends StatefulWidget {
  const ShippersTab({super.key});

  @override
  State<ShippersTab> createState() => _ShippersTabState();
}

class _ShippersTabState extends State<ShippersTab> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _ensureAuthenticated();
    _search.addListener(
        () => setState(() => _q = _search.text.trim().toLowerCase()));
  }

  Future<void> _ensureAuthenticated() async {
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Auth failed: $e')));
        }
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('shippers')
        .orderBy('nameLower')
        .limit(500)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Shippers')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, address, email, phone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                        child: Text(
                            'Error: ${snap.error}. Check permissions or sign in.'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var shippers = snap.data!.docs.map(Shipper.fromDoc).toList();

                  if (_q.isNotEmpty) {
                    shippers = shippers.where((s) {
                      final hay = [
                        s.name,
                        s.address.line1,
                        s.address.city,
                        s.email,
                        s.mobilePhone,
                        s.phone,
                        ...s.contacts
                            .map((c) => '${c.name} ${c.email} ${c.phone}'),
                      ].join(' ').toLowerCase();
                      return hay.contains(_q);
                    }).toList();
                  }

                  if (shippers.isEmpty) {
                    return const Center(child: Text('No shippers'));
                  }

                  return ListView.separated(
                    itemCount: shippers.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final s = shippers[i];
                      final addr =
                          _oneLine('${s.address.line1} ${s.address.city}');
                      return ListTile(
                        leading: const Icon(Icons.store),
                        title: Text(s.name.isEmpty ? '(unnamed)' : s.name),
                        subtitle:
                            Text(_oneLine('$addr • ${s.email} • ${s.phone}')),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: 'Edit',
                              onPressed: () async {
                                final res = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          ShipperEditScreen(shipperId: s.id)),
                                );
                                if (res is Map && res['action'] != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              '${res['action']} shipper: ${res['name']}')));
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.call),
                              tooltip: 'Call',
                              onPressed: () => _callNumber(context, s.phone),
                            ),
                            IconButton(
                              icon: const Icon(Icons.map),
                              tooltip: 'Open in Maps',
                              onPressed: () => _openMaps(addr),
                            ),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ShipperEditScreen(shipperId: s.id)),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final res = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ShipperEditScreen()),
          );
          if (res is Map && res['action'] != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${res['action']} shipper: ${res['name']}')));
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// =======================
/// Edit Screen
/// =======================

class ShipperEditScreen extends StatefulWidget {
  final String? shipperId;
  const ShipperEditScreen({super.key, this.shipperId});

  @override
  State<ShipperEditScreen> createState() => _ShipperEditScreenState();
}

class _ShipperEditScreenState extends State<ShipperEditScreen> {
  late final TextEditingController name,
      legacyId,
      legacyName,
      line1,
      city,
      region,
      postal,
      country,
      email,
      mobile,
      phone,
      ext,
      fax,
      website,
      hours,
      notes;
  late List<PersonContact> _contacts;
  bool _isActive = true;
  bool _loading = true;
  Shipper? _original;

  @override
  void initState() {
    super.initState();
    name = TextEditingController();
    legacyId = TextEditingController();
    legacyName = TextEditingController();
    line1 = TextEditingController();
    city = TextEditingController();
    region = TextEditingController();
    postal = TextEditingController();
    country = TextEditingController(text: 'CA');
    email = TextEditingController();
    mobile = TextEditingController();
    phone = TextEditingController();
    ext = TextEditingController();
    fax = TextEditingController();
    website = TextEditingController();
    hours = TextEditingController();
    notes = TextEditingController();
    _contacts = [];
    if (widget.shipperId != null) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('shippers')
          .doc(widget.shipperId)
          .get();
      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Shipper not found')));
          Navigator.pop(context);
        }
        return;
      }
      _original = Shipper.fromDoc(doc);
      name.text = _original!.name;
      legacyId.text = _original!.legacyId;
      legacyName.text = _original!.legacyName;
      line1.text = _original!.address.line1;
      city.text = _original!.address.city;
      region.text = _original!.address.region;
      postal.text = _original!.address.postalCode;
      country.text = _original!.address.country;
      email.text = _original!.email;
      mobile.text = _original!.mobilePhone;
      phone.text = _original!.phone;
      ext.text = _original!.ext;
      fax.text = _original!.fax;
      website.text = _original!.website;
      hours.text = _original!.hours;
      notes.text = _original!.notes;
      _contacts = List.from(_original!.contacts);
      _isActive = _original!.isActive;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Load failed: $e')));
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    legacyId.dispose();
    legacyName.dispose();
    line1.dispose();
    city.dispose();
    region.dispose();
    postal.dispose();
    country.dispose();
    email.dispose();
    mobile.dispose();
    phone.dispose();
    ext.dispose();
    fax.dispose();
    website.dispose();
    hours.dispose();
    notes.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label) => InputDecoration(labelText: label);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shipperId == null ? 'New Shipper' : 'Edit Shipper'),
        actions: [
          if (widget.shipperId != null)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Delete',
              onPressed: _delete,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: name, decoration: _dec('Name')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: legacyId, decoration: _dec('Legacy ID'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: legacyName, decoration: _dec('Legacy Name'))),
            ]),
            const SizedBox(height: 16),
            const Text('Address'),
            const SizedBox(height: 8),
            TextField(controller: line1, decoration: _dec('Line 1')),
            const SizedBox(height: 8),
            TextField(controller: city, decoration: _dec('City')),
            const SizedBox(height: 8),
            TextField(controller: region, decoration: _dec('Province/State')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: postal, decoration: _dec('Postal/ZIP Code'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: country, decoration: _dec('Country'))),
            ]),
            const SizedBox(height: 16),
            const Text('Contacts'),
            const SizedBox(height: 8),
            ..._contacts.asMap().entries.map((e) {
              final pc = e.value;
              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(pc.name),
                subtitle: Text(
                    '${pc.position} • ${pc.email} • ${pc.phone} ${pc.ext}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () =>
                      _openContactDialog(index: e.key, existing: pc),
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => _openContactDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Contact'),
            ),
            const SizedBox(height: 16),
            TextField(controller: email, decoration: _dec('Main Email')),
            const SizedBox(height: 8),
            TextField(controller: mobile, decoration: _dec('Mobile Phone')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child:
                      TextField(controller: phone, decoration: _dec('Phone'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 120,
                  child: TextField(controller: ext, decoration: _dec('Ext'))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: fax, decoration: _dec('Fax')),
            const SizedBox(height: 8),
            TextField(controller: website, decoration: _dec('Website')),
            const SizedBox(height: 16),
            TextField(
              controller: hours,
              decoration: _dec('Hours'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notes,
              decoration: _dec('Notes'),
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Active'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final id = widget.shipperId ?? _newId();
    final shipper = Shipper(
      id: id,
      name: name.text.trim(),
      legacyId: legacyId.text.trim(),
      legacyName: legacyName.text.trim(),
      address: Address(
        line1: line1.text.trim(),
        city: city.text.trim(),
        region: region.text.trim(),
        postalCode: postal.text.trim(),
        country: country.text.trim(),
      ),
      email: email.text.trim(),
      mobilePhone: mobile.text.trim(),
      phone: phone.text.trim(),
      ext: ext.text.trim(),
      fax: fax.text.trim(),
      website: website.text.trim(),
      hours: hours.text.trim(),
      notes: notes.text.trim(),
      contacts: _contacts,
      isActive: _isActive,
    );

    try {
      await FirebaseFirestore.instance
          .collection('shippers')
          .doc(id)
          .set(shipper.toMap(), SetOptions(merge: true));
      if (mounted) {
        Navigator.pop(context, {
          'action': widget.shipperId == null ? 'Added' : 'Updated',
          'name': shipper.name
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Shipper?'),
        content: const Text('This cannot be undone.'),
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
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('shippers')
          .doc(widget.shipperId)
          .delete();
      if (mounted) {
        Navigator.pop(
            context, {'action': 'Deleted', 'name': _original?.name ?? ''});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
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
          _contacts[index] = pc;
        } else {
          _contacts.add(pc);
        }
      });
    }
  }
}
