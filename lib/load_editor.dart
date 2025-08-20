// lib/load_editor.dart
//
// Unified Load Editor:
// - Tabs: Details · Parties · Stops · Cross-Border · Documents · eBOL
// - Multi-client / shipper / receiver, multi-stops (pick/drop)
// - Docs upload with uploader metadata (uploaderUid) for secure Storage rules
// - eBOL builder with signature capture + Save as PNG to Storage
//
// Requires:
//   cloud_firestore, firebase_storage, file_picker, url_launcher
//   and util/storage_upload.dart (upload helpers that add uploaderUid)

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io' as io show File;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // RenderRepaintBoundary
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

// Screens you already have
import 'clients_all_in_one.dart'; // ClientEditScreen / ClientListScreen
import 'shippers_tab.dart'; // ShipperEditScreen
import 'receivers_tab.dart'; // ReceiverEditScreen

// Upload helpers that set uploaderUid metadata
import 'util/storage_upload.dart';

// ----------------- small utils -----------------

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

String _oneLine(String s) =>
    s.replaceAll('\n', ', ').replaceAll(RegExp(r'\s+'), ' ').trim();

String _fmtDate(DateTime? d) {
  if (d == null) return '';
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

String _contentTypeFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'heic':
      return 'image/heic';
    case 'txt':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}

// If some older code referenced this name, keep an alias:
String _contentTypeFromPath(String name) => _contentTypeFor(name);

// ----------------- data models -----------------

class PartyRef {
  String id;
  String type; // client | shipper | receiver
  String name;
  String? department;
  String? location;
  PartyRef({
    this.id = '',
    this.type = '',
    this.name = '',
    this.department,
    this.location,
  });
  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'name': name,
        'department': department,
        'location': location,
      };
  factory PartyRef.fromMap(Map<String, dynamic>? m) => PartyRef(
        id: (m?['id'] ?? '').toString(),
        type: (m?['type'] ?? '').toString(),
        name: (m?['name'] ?? '').toString(),
        department: m?['department']?.toString(),
        location: m?['location']?.toString(),
      );
}

class Stop {
  String id;
  String kind; // pickup | drop
  String partyId;
  String partyName;
  String? location;
  DateTime? apptStart;
  DateTime? apptEnd;
  String poNo;
  String bolNo;
  String loadNo;
  String notes;
  Stop({
    String? id,
    this.kind = 'pickup',
    this.partyId = '',
    this.partyName = '',
    this.location,
    this.apptStart,
    this.apptEnd,
    this.poNo = '',
    this.bolNo = '',
    this.loadNo = '',
    this.notes = '',
  }) : id = id ?? _newId();

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'partyId': partyId,
        'partyName': partyName,
        'location': location,
        'apptStart': apptStart,
        'apptEnd': apptEnd,
        'poNo': poNo,
        'bolNo': bolNo,
        'loadNo': loadNo,
        'notes': notes,
      };

  factory Stop.fromMap(Map<String, dynamic>? m) => Stop(
        id: (m?['id'] ?? _newId()).toString(),
        kind: (m?['kind'] ?? 'pickup').toString(),
        partyId: (m?['partyId'] ?? '').toString(),
        partyName: (m?['partyName'] ?? '').toString(),
        location: m?['location']?.toString(),
        apptStart: (m?['apptStart'] is Timestamp)
            ? (m!['apptStart'] as Timestamp).toDate()
            : null,
        apptEnd: (m?['apptEnd'] is Timestamp)
            ? (m!['apptEnd'] as Timestamp).toDate()
            : null,
        poNo: (m?['poNo'] ?? '').toString(),
        bolNo: (m?['bolNo'] ?? '').toString(),
        loadNo: (m?['loadNo'] ?? '').toString(),
        notes: (m?['notes'] ?? '').toString(),
      );
}

class CrossBorderInfo {
  bool enabled;
  String exportCountry, importCountry, brokerName, brokerPhone, brokerEmail;
  String parsOrPaps,
      aceOrAci,
      hsCodes,
      totalValue,
      currency,
      incoterms,
      portOfEntry,
      carrierCode,
      trailerSeal;
  CrossBorderInfo({
    this.enabled = false,
    this.exportCountry = 'CA',
    this.importCountry = 'US',
    this.brokerName = '',
    this.brokerPhone = '',
    this.brokerEmail = '',
    this.parsOrPaps = '',
    this.aceOrAci = '',
    this.hsCodes = '',
    this.totalValue = '',
    this.currency = 'CAD',
    this.incoterms = '',
    this.portOfEntry = '',
    this.carrierCode = '',
    this.trailerSeal = '',
  });
  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'exportCountry': exportCountry,
        'importCountry': importCountry,
        'brokerName': brokerName,
        'brokerPhone': brokerPhone,
        'brokerEmail': brokerEmail,
        'parsOrPaps': parsOrPaps,
        'aceOrAci': aceOrAci,
        'hsCodes': hsCodes,
        'totalValue': totalValue,
        'currency': currency,
        'incoterms': incoterms,
        'portOfEntry': portOfEntry,
        'carrierCode': carrierCode,
        'trailerSeal': trailerSeal,
      };
  factory CrossBorderInfo.fromMap(Map<String, dynamic>? m) => CrossBorderInfo(
        enabled: (m?['enabled'] ?? false) as bool,
        exportCountry: (m?['exportCountry'] ?? 'CA').toString(),
        importCountry: (m?['importCountry'] ?? 'US').toString(),
        brokerName: (m?['brokerName'] ?? '').toString(),
        brokerPhone: (m?['brokerPhone'] ?? '').toString(),
        brokerEmail: (m?['brokerEmail'] ?? '').toString(),
        parsOrPaps: (m?['parsOrPaps'] ?? '').toString(),
        aceOrAci: (m?['aceOrAci'] ?? '').toString(),
        hsCodes: (m?['hsCodes'] ?? '').toString(),
        totalValue: (m?['totalValue'] ?? '').toString(),
        currency: (m?['currency'] ?? 'CAD').toString(),
        incoterms: (m?['incoterms'] ?? '').toString(),
        portOfEntry: (m?['portOfEntry'] ?? '').toString(),
        carrierCode: (m?['carrierCode'] ?? '').toString(),
        trailerSeal: (m?['trailerSeal'] ?? '').toString(),
      );
}

class LoadDoc {
  String id, name, url, category, contentType;
  Timestamp uploadedAt;
  int size;
  LoadDoc({
    String? id,
    this.name = '',
    this.url = '',
    this.category = 'other',
    Timestamp? uploadedAt,
    this.size = 0,
    this.contentType = '',
  })  : id = id ?? _newId(),
        uploadedAt = uploadedAt ?? Timestamp.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'url': url,
        'category': category,
        'uploadedAt': uploadedAt,
        'size': size,
        'contentType': contentType,
      };

  factory LoadDoc.fromMap(Map<String, dynamic>? m) => LoadDoc(
        id: (m?['id'] ?? _newId()).toString(),
        name: (m?['name'] ?? '').toString(),
        url: (m?['url'] ?? '').toString(),
        category: (m?['category'] ?? 'other').toString(),
        uploadedAt: (m?['uploadedAt'] is Timestamp)
            ? m!['uploadedAt'] as Timestamp
            : Timestamp.now(),
        size: (m?['size'] is num)
            ? (m?['size'] as num).toInt()
            : int.tryParse((m?['size'] ?? '0').toString()) ?? 0,
        contentType: (m?['contentType'] ?? '').toString(),
      );
}

class LoadModel {
  String id, reference, status;
  List<PartyRef> clients, shippers, receivers;
  List<Stop> stops;
  CrossBorderInfo crossBorder;
  List<LoadDoc> documents;

  LoadModel({
    this.id = '',
    this.reference = '',
    this.status = 'draft',
    List<PartyRef>? clients,
    List<PartyRef>? shippers,
    List<PartyRef>? receivers,
    List<Stop>? stops,
    CrossBorderInfo? crossBorder,
    List<LoadDoc>? documents,
  })  : clients = clients ?? [],
        shippers = shippers ?? [],
        receivers = receivers ?? [],
        stops = stops ?? [],
        crossBorder = crossBorder ?? CrossBorderInfo(),
        documents = documents ?? [];

  Map<String, dynamic> toMap() => {
        'reference': reference,
        'status': status,
        'clients': clients.map((e) => e.toMap()).toList(),
        'shippers': shippers.map((e) => e.toMap()).toList(),
        'receivers': receivers.map((e) => e.toMap()).toList(),
        'stops': stops.map((e) => e.toMap()).toList(),
        'crossBorder': crossBorder.toMap(),
        'documents': documents.map((e) => e.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
      };

  factory LoadModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};

    List<PartyRef> _list(String k) {
      final raw = m[k];
      if (raw is List) {
        return raw
            .map((x) => PartyRef.fromMap(x as Map<String, dynamic>?))
            .toList();
      }
      return [];
    }

    List<Stop> _stops() {
      final raw = m['stops'];
      if (raw is List) {
        return raw
            .map((x) => Stop.fromMap(x as Map<String, dynamic>?))
            .toList();
      }
      return [];
    }

    List<LoadDoc> _docs() {
      final raw = m['documents'];
      if (raw is List) {
        return raw
            .map((x) => LoadDoc.fromMap(x as Map<String, dynamic>?))
            .toList();
      }
      return [];
    }

    return LoadModel(
      id: d.id,
      reference: (m['reference'] ?? '').toString(),
      status: (m['status'] ?? 'draft').toString(),
      clients: _list('clients'),
      shippers: _list('shippers'),
      receivers: _list('receivers'),
      stops: _stops(),
      crossBorder:
          CrossBorderInfo.fromMap(m['crossBorder'] as Map<String, dynamic>?),
      documents: _docs(),
    );
  }
}

// ----------------- screen -----------------

class LoadEditorScreen extends StatefulWidget {
  final String? loadId;
  const LoadEditorScreen({super.key, this.loadId});

  @override
  State<LoadEditorScreen> createState() => _LoadEditorScreenState();
}

class _LoadEditorScreenState extends State<LoadEditorScreen>
    with TickerProviderStateMixin {
  final _form = GlobalKey<FormState>();
  late final TabController _tabs = TabController(length: 6, vsync: this);

  bool _saving = false;
  LoadModel _load = LoadModel();

  final _refCtrl = TextEditingController();

  // eBOL capture
  final GlobalKey _ebolKey = GlobalKey();
  final _driverSig = SignatureController();
  final _consigneeSig = SignatureController();
  final _shipperSig = SignatureController();
  final _ebolNotes = TextEditingController();
  final _ebolPieces = TextEditingController();
  final _ebolWeight = TextEditingController();
  final _ebolCommodity = TextEditingController();

  // docs tab
  String _docCategory = 'bol';
  final _folderCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.loadId != null) _loadDoc();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _refCtrl.dispose();
    _ebolNotes.dispose();
    _ebolPieces.dispose();
    _ebolWeight.dispose();
    _ebolCommodity.dispose();
    _folderCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDoc() async {
    final doc = await FirebaseFirestore.instance
        .collection('loads')
        .doc(widget.loadId!)
        .get();
    if (!doc.exists) return;
    setState(() {
      _load = LoadModel.fromDoc(doc);
      _refCtrl.text = _load.reference;
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
    if (!_form.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fix highlighted fields')),
      );
      return;
    }
    setState(() => _saving = true);
    final isNew = widget.loadId == null;

    _load.reference = _refCtrl.text.trim();

    // give immediate UX feedback by popping quickly
    _popNextFrame({
      'action': isNew ? 'created' : 'updated',
      'name': _load.reference.isEmpty ? 'Load' : _load.reference,
    });

    () async {
      try {
        final col = FirebaseFirestore.instance.collection('loads');
        if (isNew) {
          await col.add(_load.toMap());
        } else {
          await col.doc(widget.loadId!).update(_load.toMap());
        }
      } catch (_) {}
    }();
  }

  Future<void> _deleteDoc(LoadDoc d) async {
    try {
      await FirebaseStorage.instance.refFromURL(d.url).delete();
    } catch (_) {}
    setState(() => _load.documents.removeWhere((x) => x.id == d.id));
    if (widget.loadId != null) {
      await FirebaseFirestore.instance
          .collection('loads')
          .doc(widget.loadId!)
          .update({
        'documents': _load.documents.map((e) => e.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.loadId == null ? 'New Load' : 'Edit Load'),
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
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'Parties'),
            Tab(text: 'Stops'),
            Tab(text: 'Cross-Border'),
            Tab(text: 'Documents'),
            Tab(text: 'eBOL'),
          ],
        ),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _form,
          child: TabBarView(
            controller: _tabs,
            children: [
              _detailsTab(),
              _partiesTab(),
              _stopsTab(),
              _crossBorderTab(),
              _documentsTab(),
              _ebolTab(),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------- tabs -----------------

  Widget _detailsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextFormField(
          controller: _refCtrl,
          decoration: const InputDecoration(
            labelText: 'Internal Load Reference',
            hintText: 'e.g., FL-2025-000123',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: const [
            'draft',
            'planned',
            'assigned',
            'enroute',
            'delivered',
            'invoiced'
          ].contains(_load.status)
              ? _load.status
              : 'draft',
          items: const [
            DropdownMenuItem(value: 'draft', child: Text('Draft')),
            DropdownMenuItem(value: 'planned', child: Text('Planned')),
            DropdownMenuItem(value: 'assigned', child: Text('Assigned')),
            DropdownMenuItem(value: 'enroute', child: Text('En-route')),
            DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
            DropdownMenuItem(value: 'invoiced', child: Text('Invoiced')),
          ],
          onChanged: (v) => setState(() => _load.status = v ?? 'draft'),
          decoration: const InputDecoration(
            labelText: 'Status',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Tip: Use Parties and Stops tabs to add multi-client / multi-shipper / multi-receiver and multi-pickup/multi-drop.',
        ),
      ],
    );
  }

  Widget _partiesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _partySection('Clients', 'client', _load.clients,
            enableDepartment: true),
        const Divider(height: 24),
        _partySection('Shippers', 'shipper', _load.shippers,
            enableLocation: true),
        const Divider(height: 24),
        _partySection('Receivers', 'receiver', _load.receivers,
            enableLocation: true),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _partySection(
    String title,
    String type,
    List<PartyRef> list, {
    bool enableDepartment = false,
    bool enableLocation = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...list.map((p) => Card(
              child: ListTile(
                title: Text(p.name.isEmpty ? '(select)' : p.name),
                subtitle: Text(_oneLine(
                  '${enableDepartment && (p.department ?? '').isNotEmpty ? 'Dept: ${p.department} • ' : ''}'
                  '${enableLocation && (p.location ?? '').isNotEmpty ? 'Location: ${p.location}' : ''}',
                )),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _selectParty(
                        type,
                        existing: p,
                        enableDepartment: enableDepartment,
                        enableLocation: enableLocation,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          setState(() => list.removeWhere((x) => x.id == p.id)),
                    ),
                  ],
                ),
              ),
            )),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _selectParty(
              type,
              enableDepartment: enableDepartment,
              enableLocation: enableLocation,
            ),
            icon: const Icon(Icons.add),
            label: Text('Add ${title.substring(0, title.length - 1)}'),
          ),
        ),
      ],
    );
  }

  Future<void> _selectParty(
    String type, {
    PartyRef? existing,
    bool enableDepartment = false,
    bool enableLocation = false,
  }) async {
    final ctrl = TextEditingController();
    PartyRef? selected;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: 520,
            child: Column(
              children: [
                AppBar(
                  title: Text(
                      'Select ${type[0].toUpperCase()}${type.substring(1)}'),
                  automaticallyImplyLeading: false,
                  actions: [
                    if (type == 'client')
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ClientEditScreen(),
                              ));
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('New'),
                      ),
                    if (type == 'shipper')
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ShipperEditScreen(),
                              ));
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('New'),
                      ),
                    if (type == 'receiver')
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ReceiverEditScreen(),
                              ));
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('New'),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name…',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => (ctx as Element).markNeedsBuild(),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection(type == 'client'
                            ? 'clients'
                            : (type == 'shipper' ? 'shippers' : 'receivers'))
                        .orderBy('name') // keep it simple/portable
                        .limit(100)
                        .snapshots(),
                    builder: (c, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snap.data!.docs;
                      final q = ctrl.text.trim().toLowerCase();
                      final filtered = q.isEmpty
                          ? docs
                          : docs.where((d) {
                              final m = d.data();
                              final name = (m['displayName'] ?? m['name'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              return name.contains(q);
                            }).toList();

                      return ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final d = filtered[i];
                          final m = d.data();
                          final name =
                              (m['displayName'] ?? m['name'] ?? '').toString();
                          return ListTile(
                            title: Text(name),
                            subtitle: Text(_oneLine(
                              type == 'client'
                                  ? (m['legalName'] ?? '').toString()
                                  : (m['email'] ?? '').toString(),
                            )),
                            onTap: () {
                              selected =
                                  PartyRef(id: d.id, type: type, name: name);
                              Navigator.pop(ctx);
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
      },
    );

    String? dept;
    String? loc;
    if (enableDepartment) {
      final res = await _promptText(
        'Department (optional)',
        existing != null ? (existing.department ?? '') : '',
      );
      if (res != null) dept = res.trim();
    }
    if (enableLocation) {
      final res = await _promptText(
        'Location (optional)',
        existing != null ? (existing.location ?? '') : '',
      );
      if (res != null) loc = res.trim();
    }

    setState(() {
      final list = (type == 'client')
          ? _load.clients
          : (type == 'shipper' ? _load.shippers : _load.receivers);
      if (existing != null) {
        if (selected != null) {
          existing.name = selected!.name;
          existing.id = selected!.id;
        }
        existing.department = dept ?? existing.department;
        existing.location = loc ?? existing.location;
      } else if (selected != null) {
        selected!.department = dept;
        selected!.location = loc;
        list.add(selected!);
      }
    });
  }

  Future<String?> _promptText(String label, String? initial) async {
    final c = TextEditingController(text: initial ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return ok == true ? c.text : null;
  }

  Widget _stopsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Stops (default 1 pickup, 1 delivery). Add more as needed.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ..._load.stops.map((s) => _stopCard(s)).toList(),
        TextButton.icon(
          onPressed: () =>
              setState(() => _load.stops.add(Stop(kind: 'pickup'))),
          icon: const Icon(Icons.add_location_alt),
          label: const Text('Add Pickup'),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _load.stops.add(Stop(kind: 'drop'))),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add Delivery'),
        ),
        const SizedBox(height: 24),
        if (_load.stops.isEmpty)
          OutlinedButton(
            onPressed: () {
              setState(() {
                _load.stops.addAll([Stop(kind: 'pickup'), Stop(kind: 'drop')]);
              });
            },
            child: const Text('Add default 1 Pickup + 1 Delivery'),
          ),
      ],
    );
  }

  Widget _stopCard(Stop s) {
    final startText = TextEditingController(text: _fmtDate(s.apptStart));
    final endText = TextEditingController(text: _fmtDate(s.apptEnd));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  s.kind == 'pickup' ? 'Pickup' : 'Delivery',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(
                    () => _load.stops.removeWhere((x) => x.id == s.id)),
              ),
            ]),
            TextFormField(
              initialValue: s.partyName,
              readOnly: true,
              decoration: InputDecoration(
                labelText: s.kind == 'pickup' ? 'Shipper' : 'Receiver',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.list),
                  onPressed: () async {
                    final isPickup = s.kind == 'pickup';
                    final pool = isPickup ? _load.shippers : _load.receivers;
                    if (pool.isEmpty) {
                      final name = await _promptText(
                        'Enter ${isPickup ? 'Shipper' : 'Receiver'} name',
                        s.partyName,
                      );
                      if (name != null)
                        setState(() => s.partyName = name.trim());
                    } else {
                      final choice = await showDialog<PartyRef>(
                        context: context,
                        builder: (ctx) => SimpleDialog(
                          title: Text(
                              'Select ${isPickup ? 'Shipper' : 'Receiver'}'),
                          children: pool
                              .map((p) => SimpleDialogOption(
                                    onPressed: () => Navigator.pop(ctx, p),
                                    child: Text(p.name),
                                  ))
                              .toList(),
                        ),
                      );
                      if (choice != null) {
                        setState(() {
                          s.partyId = choice.id;
                          s.partyName = choice.name;
                          s.location = choice.location;
                        });
                      }
                    }
                  },
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if ((s.location ?? '').isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Location: ${s.location}',
                    style: const TextStyle(color: Colors.black54)),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: startText,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Appt Start (date)',
                    border: OutlineInputBorder(),
                  ),
                  onTap: () async {
                    final now = DateTime.now();
                    final pick = await showDatePicker(
                      context: context,
                      initialDate: s.apptStart ?? now,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (pick != null) setState(() => s.apptStart = pick);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: endText,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Appt End (date)',
                    border: OutlineInputBorder(),
                  ),
                  onTap: () async {
                    final now = DateTime.now();
                    final pick = await showDatePicker(
                      context: context,
                      initialDate: s.apptEnd ?? (s.apptStart ?? now),
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (pick != null) setState(() => s.apptEnd = pick);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: s.loadNo,
                  decoration: const InputDecoration(
                    labelText: 'Load No',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => s.loadNo = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: s.poNo,
                  decoration: const InputDecoration(
                    labelText: 'PO No',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => s.poNo = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: s.bolNo,
                  decoration: const InputDecoration(
                    labelText: 'BOL No',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => s.bolNo = v,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: s.notes,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => s.notes = v,
            ),
          ],
        ),
      ),
    );
  }

  Widget _crossBorderTab() {
    final cb = _load.crossBorder;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          value: cb.enabled,
          onChanged: (v) => setState(() => _load.crossBorder.enabled = v),
          title: const Text('Cross-border shipment'),
          subtitle: const Text(
              'Turn on to enter customs details (PARS/PAPS, broker, HS codes, etc.)'),
        ),
        if (cb.enabled) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: cb.exportCountry,
                items: const [
                  DropdownMenuItem(value: 'CA', child: Text('Canada (Export)')),
                  DropdownMenuItem(
                      value: 'US', child: Text('United States (Export)')),
                  DropdownMenuItem(value: 'MX', child: Text('Mexico (Export)')),
                ],
                onChanged: (v) => setState(() => cb.exportCountry = v ?? 'CA'),
                decoration: const InputDecoration(
                  labelText: 'Export Country',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: cb.importCountry,
                items: const [
                  DropdownMenuItem(
                      value: 'US', child: Text('United States (Import)')),
                  DropdownMenuItem(value: 'CA', child: Text('Canada (Import)')),
                  DropdownMenuItem(value: 'MX', child: Text('Mexico (Import)')),
                ],
                onChanged: (v) => setState(() => cb.importCountry = v ?? 'US'),
                decoration: const InputDecoration(
                  labelText: 'Import Country',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: cb.brokerName,
            decoration: const InputDecoration(
              labelText: 'Customs Broker Name',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => cb.brokerName = v,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: cb.brokerPhone,
                decoration: const InputDecoration(
                  labelText: 'Broker Phone',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => cb.brokerPhone = v,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: cb.brokerEmail,
                decoration: const InputDecoration(
                  labelText: 'Broker Email',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => cb.brokerEmail = v,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: cb.parsOrPaps,
                decoration: const InputDecoration(
                  labelText: 'PARS / PAPS',
                  border: OutlineInputBorder(),
                  hintText: 'For CA: PARS, for US: PAPS',
                ),
                onChanged: (v) => cb.parsOrPaps = v,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: cb.aceOrAci,
                decoration: const InputDecoration(
                  labelText: 'ACE / ACI Trip',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => cb.aceOrAci = v,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: cb.hsCodes,
            decoration: const InputDecoration(
              labelText: 'HS Codes (comma separated)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => cb.hsCodes = v,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: cb.totalValue,
                decoration: const InputDecoration(
                  labelText: 'Total Declared Value',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => cb.totalValue = v,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: cb.currency,
                items: const [
                  DropdownMenuItem(value: 'CAD', child: Text('CAD')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                  DropdownMenuItem(value: 'MXN', child: Text('MXN')),
                ],
                onChanged: (v) => setState(() => cb.currency = v ?? 'CAD'),
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: cb.incoterms,
                decoration: const InputDecoration(
                  labelText: 'Incoterms (FOB/EXW/DDP...)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => cb.incoterms = v,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: cb.portOfEntry,
                decoration: const InputDecoration(
                  labelText: 'Port of Entry',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => cb.portOfEntry = v,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: cb.carrierCode,
                decoration: const InputDecoration(
                  labelText: 'Carrier Code (SCAC/CBSA)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => cb.carrierCode = v,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: cb.trailerSeal,
                decoration: const InputDecoration(
                  labelText: 'Trailer Seal',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => cb.trailerSeal = v,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const Text(
            'Note: You can extend this with line-items (HS codes, origin, values) per stop later.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ],
    );
  }

  Widget _documentsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _docCategory,
              items: const [
                DropdownMenuItem(value: 'bol', child: Text('BOL')),
                DropdownMenuItem(value: 'invoice', child: Text('Invoice')),
                DropdownMenuItem(value: 'receipt', child: Text('Receipt')),
                DropdownMenuItem(value: 'photo', child: Text('Photo')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _docCategory = v ?? 'other'),
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _folderCtrl,
              decoration: const InputDecoration(
                labelText: 'Folder (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _uploadDocs,
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload'),
          ),
        ]),
        const SizedBox(height: 12),
        if (_load.documents.isEmpty)
          const Text(
            'No documents yet. Upload above, or save an eBOL on the eBOL tab.',
            style: TextStyle(color: Colors.black54),
          ),
        ..._groupDocs(_load.documents).entries.map((e) => Card(
              child: ExpansionTile(
                title: Text('${_catLabel(e.key)} (${e.value.length})'),
                children: e.value
                    .map((d) => ListTile(
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(d.name, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${d.contentType.isEmpty ? 'file' : d.contentType} • '
                            '${DateTime.fromMillisecondsSinceEpoch(d.uploadedAt.millisecondsSinceEpoch)}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteDoc(d),
                          ),
                          onTap: () => launchUrl(
                            Uri.parse(d.url),
                            mode: LaunchMode.externalApplication,
                          ),
                        ))
                    .toList(),
              ),
            )),
        const SizedBox(height: 80),
      ],
    );
  }

  Future<void> _uploadDocs() async {
    if (widget.loadId == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Save the load first, then upload.')),
      );
      return;
    }
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final String id = widget.loadId!;
      final folder = _folderCtrl.text.trim();

      for (final f in picked.files) {
        final name = f.name;
        final ct = _contentTypeFor(name);

        // Storage path: loads/{id}/{category}/[folder]/filename
        final base = 'loads/$id/$_docCategory';
        final refPath =
            folder.isNotEmpty ? '$base/$folder/$name' : '$base/$name';

        // Upload via helpers (adds uploaderUid metadata)
        String url;
        if (f.bytes != null) {
          url = await uploadBytesWithMeta(
            refPath: refPath,
            bytes: f.bytes!,
            contentType: ct,
            extraMeta: {'loadId': id, 'category': _docCategory},
          );
        } else if (f.path != null && !kIsWeb) {
          url = await uploadFilePathWithMeta(
            refPath: refPath,
            filePath: f.path!,
            contentType: ct,
            extraMeta: {'loadId': id, 'category': _docCategory},
          );
        } else {
          continue;
        }

        setState(() => _load.documents.add(LoadDoc(
              name: name,
              url: url,
              category: _docCategory,
              size: f.size,
              contentType: ct,
            )));
      }

      await FirebaseFirestore.instance.collection('loads').doc(id).update({
        'documents': _load.documents.map((e) => e.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Upload complete.')));
    } catch (e) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  Map<String, List<LoadDoc>> _groupDocs(List<LoadDoc> all) {
    final m = <String, List<LoadDoc>>{};
    for (final d in all) {
      m.putIfAbsent(d.category, () => []).add(d);
    }
    return m;
  }

  String _catLabel(String k) {
    switch (k) {
      case 'bol':
        return 'BOL';
      case 'invoice':
        return 'Invoice';
      case 'receipt':
        return 'Receipt';
      case 'photo':
        return 'Photos';
      default:
        return 'Other';
    }
  }

  Widget _ebolTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Electronic Bill of Lading (eBOL)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        RepaintBoundary(
          key: _ebolKey,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'BOL for ${_refCtrl.text.isEmpty ? 'Unassigned' : _refCtrl.text}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                    'Shipper: ${_load.shippers.isNotEmpty ? _load.shippers.first.name : '(set in Parties)'}'),
                Text(
                    'Consignee: ${_load.receivers.isNotEmpty ? _load.receivers.last.name : '(set in Parties)'}'),
                const Text('Carrier: Full Load'),
                const Divider(),
                TextFormField(
                  controller: _ebolCommodity,
                  decoration: const InputDecoration(
                    labelText: 'Commodity / Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ebolPieces,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Pieces',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _ebolWeight,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Weight (lb/kg)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ebolNotes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Special Instructions',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Signatures',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _sigBlock('Shipper', _shipperSig)),
                    const SizedBox(width: 8),
                    Expanded(child: _sigBlock('Receiver', _consigneeSig)),
                    const SizedBox(width: 8),
                    Expanded(child: _sigBlock('Driver', _driverSig)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton.icon(
            onPressed: _clearSigs,
            icon: const Icon(Icons.clear),
            label: const Text('Clear Signatures'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saveEbolImage,
            icon: const Icon(Icons.save_alt),
            label: const Text('Save BOL as image'),
          ),
        ]),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _sigBlock(String label, SignatureController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        Container(
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: GestureDetector(
            onPanStart: (d) => c.addPoint(d.localPosition),
            onPanUpdate: (d) => c.addPoint(d.localPosition),
            onPanEnd: (_) => c.addBreak(),
            child: CustomPaint(painter: _SigPainter(c.paths)),
          ),
        ),
      ],
    );
  }

  void _clearSigs() {
    setState(() {
      _driverSig.clear();
      _consigneeSig.clear();
      _shipperSig.clear();
    });
  }

  Future<void> _saveEbolImage() async {
    if (widget.loadId == null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Save the load first.')));
      return;
    }
    try {
      final boundary =
          _ebolKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final fileName = 'BOL_${DateTime.now().millisecondsSinceEpoch}.png';
      final refPath = 'loads/${widget.loadId!}/bol/$fileName';

      // Upload through helper (adds uploaderUid metadata)
      final url = await uploadBytesWithMeta(
        refPath: refPath,
        bytes: bytes,
        contentType: 'image/png',
        extraMeta: {'loadId': widget.loadId!, 'category': 'bol'},
      );

      setState(() => _load.documents.add(LoadDoc(
            name: fileName,
            url: url,
            category: 'bol',
            size: bytes.length,
            contentType: 'image/png',
          )));

      await FirebaseFirestore.instance
          .collection('loads')
          .doc(widget.loadId!)
          .update({
        'documents': _load.documents.map((e) => e.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('BOL saved to documents.')));
    } catch (e) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }
}

// ----------------- minimal signature capture -----------------

class SignatureController {
  final List<List<ui.Offset>> paths = [];
  void addPoint(ui.Offset p) {
    if (paths.isEmpty || paths.last.isEmpty) {
      paths.add([p]);
    } else {
      paths.last.add(p);
    }
  }

  void addBreak() => paths.add([]);
  void clear() => paths.clear();
  bool get isEmpty => paths.isEmpty || paths.every((p) => p.isEmpty);
}

class _SigPainter extends CustomPainter {
  final List<List<ui.Offset>> paths;
  _SigPainter(this.paths);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final seg in paths) {
      if (seg.length < 2) continue;
      final path = Path()..moveTo(seg.first.dx, seg.first.dy);
      for (int i = 1; i < seg.length; i++) {
        path.lineTo(seg[i].dx, seg[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter old) => old.paths != paths;
}
