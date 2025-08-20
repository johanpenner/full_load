// lib/document_viewer_screen.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets/main_menu_button.dart';

class DocumentViewerScreen extends StatefulWidget {
  const DocumentViewerScreen({super.key});

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  // Filters
  String _type = 'All';
  String? _loadId;
  String? _loadLabel;
  String? _uploaderUid;
  String? _uploaderLabel;
  DateTimeRange? _range;
  final _search = TextEditingController();
  String _q = '';

  // Data
  bool _loading = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  @override
  void initState() {
    super.initState();
    _search.addListener(
        () => setState(() => _q = _search.text.trim().toLowerCase()));
    // Default to last 30 days
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 30)),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    _fetch();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);

    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('documents');

    if (_type != 'All') {
      q = q.where('type', isEqualTo: _type);
    }
    if (_loadId != null) {
      q = q.where('loadId', isEqualTo: _loadId);
    }
    if (_uploaderUid != null) {
      q = q.where('uploaderUid', isEqualTo: _uploaderUid);
    }
    if (_range != null) {
      final start =
          DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(
          _range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59);
      q = q
          .where('uploadedAt', isGreaterThanOrEqualTo: start)
          .where('uploadedAt', isLessThanOrEqualTo: end);
    }

    q = q.orderBy('uploadedAt', descending: true);

    final snap = await q.get();
    var ds = snap.docs;

    // Client-side name search
    if (_q.isNotEmpty) {
      ds = ds.where((d) {
        final m = d.data();
        final name = (m['name'] ?? '').toString().toLowerCase();
        final notes = (m['notes'] ?? '').toString().toLowerCase();
        final loadRef = (m['loadRef'] ?? '').toString().toLowerCase();
        return name.contains(_q) || notes.contains(_q) || loadRef.contains(_q);
      }).toList();
    }

    if (mounted) {
      setState(() {
        _docs = ds;
        _loading = false;
      });
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final total = _visibleDocs.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: const [MainMenuButton()],
      ),
      body: Column(
        children: [
          // Filters row #1: type, load, uploader
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                // Type
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('All')),
                      DropdownMenuItem(value: 'BOL', child: Text('BOL')),
                      DropdownMenuItem(value: 'POD', child: Text('POD')),
                      DropdownMenuItem(
                          value: 'Receipt', child: Text('Receipt')),
                      DropdownMenuItem(
                          value: 'Invoice', child: Text('Invoice')),
                      DropdownMenuItem(value: 'Hazmat', child: Text('Hazmat')),
                      DropdownMenuItem(value: 'Photo', child: Text('Photo')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (v) async {
                      setState(() => _type = v ?? 'All');
                      await _fetch();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Load
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickLoad,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: Text(_loadLabel == null
                        ? 'Filter by Load'
                        : 'Load: $_loadLabel'),
                  ),
                ),
                const SizedBox(width: 8),
                // Uploader
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickUploader,
                    icon: const Icon(Icons.person_outline),
                    label: Text(_uploaderLabel == null
                        ? 'Filter by Uploader'
                        : 'Uploader: $_uploaderLabel'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear filters',
                  icon: const Icon(Icons.filter_alt_off),
                  onPressed: () async {
                    setState(() {
                      _type = 'All';
                      _loadId = null;
                      _loadLabel = null;
                      _uploaderUid = null;
                      _uploaderLabel = null;
                    });
                    await _fetch();
                  },
                ),
              ],
            ),
          ),

          // Filters row #2: date range + search + refresh
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search file name / notes / load ref…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(_range == null
                      ? 'Pick range'
                      : '${_fmtDate(_range!.start)} – ${_fmtDate(_range!.end)}'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _fetch,
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (total == 0
                    ? const Center(child: Text('No documents found'))
                    : ListView.separated(
                        itemCount: _visibleDocs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final d = _visibleDocs[i];
                          final id = d.id;
                          final m = d.data();

                          final name = (m['name'] ?? '').toString();
                          final url = (m['url'] ?? '').toString();
                          final storagePath =
                              (m['storagePath'] ?? '').toString();
                          final type = (m['type'] ?? '').toString();
                          final size = (m['size'] ?? 0) as int;
                          final contentType =
                              (m['contentType'] ?? '').toString();
                          final uploadedAt = m['uploadedAt'];
                          final loadRef = (m['loadRef'] ?? '').toString();
                          final notes = (m['notes'] ?? '').toString();

                          final subtitle = [
                            if (type.isNotEmpty) 'Type: $type',
                            if (contentType.isNotEmpty) contentType,
                            if (size > 0) _prettySize(size),
                            if (loadRef.isNotEmpty) 'Load: $loadRef',
                            if (uploadedAt != null) 'At: ${_fmtTs(uploadedAt)}',
                          ].join(' • ');

                          return Card(
                            child: ListTile(
                              leading: Icon(_iconFor(contentType)),
                              title: Text(name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  if (notes.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(notes,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.black54)),
                                    ),
                                ],
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'Open',
                                    icon: const Icon(Icons.open_in_new),
                                    onPressed: url.isEmpty
                                        ? null
                                        : () => _openUrl(url),
                                  ),
                                  IconButton(
                                    tooltip: 'Copy link',
                                    icon: const Icon(Icons.link),
                                    onPressed:
                                        url.isEmpty ? null : () => _copy(url),
                                  ),
                                  IconButton(
                                    tooltip: 'Share link',
                                    icon: const Icon(Icons.share),
                                    onPressed: url.isEmpty
                                        ? null
                                        : () => _share(url, name),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    onPressed: () => _deleteDoc(
                                        id: id,
                                        storagePath: storagePath,
                                        url: url,
                                        name: name),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )),
          ),

          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${_visibleDocs.length} documents',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visibleDocs {
    var ds = _docs;
    if (_q.isNotEmpty) {
      ds = ds.where((d) {
        final m = d.data();
        final name = (m['name'] ?? '').toString().toLowerCase();
        final notes = (m['notes'] ?? '').toString().toLowerCase();
        final loadRef = (m['loadRef'] ?? '').toString().toLowerCase();
        return name.contains(_q) || notes.contains(_q) || loadRef.contains(_q);
      }).toList();
    }
    return ds;
  }

  // ---------- actions ----------

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Link copied')));
    }
  }

  Future<void> _share(String url, String name) async {
    if (kIsWeb) {
      await _copy(url);
      return;
    }
    // On desktop/mobile we can invoke share
    final tempName = name.isEmpty ? 'document' : name;
    final text = 'Document: $tempName\n$url';
    await Share.share(text);
  }

  Future<void> _deleteDoc({
    required String id,
    required String storagePath,
    required String url,
    required String name,
  }) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Document?'),
            content: Text(
                'Delete "$name"? This will remove the file and its record.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    try {
      // 1) delete storage
      if (storagePath.isNotEmpty) {
        await FirebaseStorage.instance.ref(storagePath).delete();
      } else if (url.isNotEmpty) {
        // fallback (slower) if storagePath missing
        await FirebaseStorage.instance.refFromURL(url).delete();
      }
    } catch (_) {
      // file might already be gone; continue
    }

    // 2) delete firestore doc
    await FirebaseFirestore.instance.collection('documents').doc(id).delete();

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Deleted')));
      _fetch();
    }
  }

  // ---------- pickers ----------

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final init = _range ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 30)),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: init,
      saveText: 'Apply',
    );
    if (picked != null) {
      setState(() => _range = picked);
      await _fetch();
    }
  }

  Future<void> _pickLoad() async {
    final res = await showDialog<_PickLoadRes>(
      context: context,
      builder: (_) => const _LoadPickerDialogDV(),
    );
    if (res == null) return;
    setState(() {
      _loadId = res.id;
      _loadLabel = res.label;
    });
    await _fetch();
  }

  Future<void> _pickUploader() async {
    final res = await showDialog<_PickUploaderRes>(
      context: context,
      builder: (_) => const _UploaderPickerDialogDV(),
    );
    if (res == null) return;
    setState(() {
      _uploaderUid = res.uid;
      _uploaderLabel = res.label;
    });
    await _fetch();
  }

  // ---------- small utils ----------

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTs(dynamic v) {
    DateTime? dt;
    if (v is Timestamp) dt = v.toDate();
    if (v is DateTime) dt = v;
    dt ??= DateTime.tryParse(v?.toString() ?? '');
    if (dt == null) return '';
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  IconData _iconFor(String ct) {
    if (ct.startsWith('image/')) return Icons.image;
    if (ct == 'application/pdf') return Icons.picture_as_pdf;
    if (ct.startsWith('video/')) return Icons.videocam_outlined;
    if (ct.startsWith('audio/')) return Icons.audiotrack;
    if (ct.contains('excel') || ct.endsWith('sheet')) return Icons.grid_on;
    if (ct.contains('word') || ct.endsWith('document'))
      return Icons.description_outlined;
    if (ct == 'text/plain' || ct == 'text/csv' || ct == 'application/json')
      return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _prettySize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(2)} KB';
    return '$bytes B';
  }
}

// ======== Load picker dialog (DV) ========

class _PickLoadRes {
  final String id;
  final String label;
  _PickLoadRes(this.id, this.label);
}

class _LoadPickerDialogDV extends StatefulWidget {
  const _LoadPickerDialogDV();

  @override
  State<_LoadPickerDialogDV> createState() => _LoadPickerDialogDVState();
}

class _LoadPickerDialogDVState extends State<_LoadPickerDialogDV> {
  String _q = '';
  final _search = TextEditingController();

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
        .collection('loads')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return AlertDialog(
      title: const Text('Filter by Load'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by load # / PO / client / shipper / receiver',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snap) {
                  if (!snap.hasData)
                    return const Center(child: CircularProgressIndicator());
                  var docs = snap.data!.docs;

                  if (_q.isNotEmpty) {
                    docs = docs.where((d) {
                      final m = d.data();
                      final hay = [
                        (m['loadNumber'] ?? ''),
                        (m['poNumber'] ?? ''),
                        (m['shippingNumber'] ?? ''),
                        (m['clientName'] ?? ''),
                        (m['shipperName'] ?? ''),
                        (m['receiverName'] ?? ''),
                        (m['deliveryAddress'] ?? ''),
                      ].join(' ').toString().toLowerCase();
                      return hay.contains(_q);
                    }).toList();
                  }

                  if (docs.isEmpty)
                    return const Center(child: Text('No matching loads'));

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data();
                      final ref = (m['loadNumber'] ??
                              m['shippingNumber'] ??
                              m['poNumber'] ??
                              '')
                          .toString();
                      final client = (m['clientName'] ?? '').toString();
                      final shipper = (m['shipperName'] ?? '').toString();
                      final receiver = (m['receiverName'] ?? '').toString();
                      final label = ref.isEmpty ? d.id : ref;

                      return ListTile(
                        title: Text(ref.isEmpty ? 'Load ${d.id}' : 'Load $ref'),
                        subtitle: Text(
                            [client, shipper, receiver]
                                .where((s) => s.isNotEmpty)
                                .join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        trailing: OutlinedButton(
                          onPressed: () =>
                              Navigator.pop(context, _PickLoadRes(d.id, label)),
                          child: const Text('Select'),
                        ),
                        onTap: () =>
                            Navigator.pop(context, _PickLoadRes(d.id, label)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}

// ======== Uploader picker dialog (DV) ========

class _PickUploaderRes {
  final String uid;
  final String label;
  _PickUploaderRes(this.uid, this.label);
}

class _UploaderPickerDialogDV extends StatefulWidget {
  const _UploaderPickerDialogDV();

  @override
  State<_UploaderPickerDialogDV> createState() =>
      _UploaderPickerDialogDVState();
}

class _UploaderPickerDialogDVState extends State<_UploaderPickerDialogDV> {
  String _q = '';
  final _search = TextEditingController();

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
        .collection('users')
        .orderBy('email')
        .limit(200)
        .snapshots();

    return AlertDialog(
      title: const Text('Filter by Uploader'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by email / name',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snap) {
                  if (!snap.hasData)
                    return const Center(child: CircularProgressIndicator());
                  var docs = snap.data!.docs;

                  if (_q.isNotEmpty) {
                    docs = docs.where((d) {
                      final m = d.data();
                      final hay = [
                        (m['email'] ?? ''),
                        (m['name'] ?? ''),
                      ].join(' ').toString().toLowerCase();
                      return hay.contains(_q);
                    }).toList();
                  }

                  if (docs.isEmpty)
                    return const Center(child: Text('No matching users'));

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data();

                      final email = (m['email'] ?? '').toString();
                      final name = (m['name'] ?? '').toString();
                      final label =
                          [name, email].where((s) => s.isNotEmpty).join(' • ');
                      final uid = d.id;

                      return ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.person_outline)),
                        title: Text(label.isEmpty ? uid : label),
                        trailing: OutlinedButton(
                          onPressed: () => Navigator.pop(
                              context,
                              _PickUploaderRes(
                                  uid, label.isEmpty ? uid : label)),
                          child: const Text('Select'),
                        ),
                        onTap: () => Navigator.pop(context,
                            _PickUploaderRes(uid, label.isEmpty ? uid : label)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}
