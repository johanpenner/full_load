// lib/driver_upload_screen.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:full_load/auth/current_user_role.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// If you have these, keep them. Otherwise you can remove the menu import.
import 'document_viewer_screen.dart';
import 'widgets/main_menu_button.dart';

// Roles
import 'auth/roles.dart';

class DriverUploadScreen extends StatefulWidget {
  const DriverUploadScreen({super.key});

  @override
  State<DriverUploadScreen> createState() => _DriverUploadScreenState();
}

class _DriverUploadScreenState extends State<DriverUploadScreen> {
  // Role
  late Future<AppRole> _roleFut;

  // Selection
  String? _selectedLoadId;
  String? _selectedLoadLabel; // e.g., loadNumber or id
  String _docType = 'POD'; // default driver tag
  final _notesCtrl = TextEditingController();

  // Files
  final List<_Pick> _picks = [];
  bool _uploading = false;
  final Map<String, double> _progress = {}; // fileName -> 0..1

  // Driver scope
  final _search = TextEditingController();
  String _q = '';
  List<_LoadItem> _visibleLoads = [];
  bool _loadingLoads = true;

  @override
  void initState() {
    super.initState();
    _roleFut = currentUserRole();
    _search.addListener(() {
      setState(() => _q = _search.text.trim().toLowerCase());
    });
    _fetchLoads();
  }

  @override
  void dispose() {
    _search.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ===================== Loads (role-aware) =====================

  Future<void> _fetchLoads() async {
    setState(() => _loadingLoads = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _visibleLoads = [];
        _loadingLoads = false;
      });
      return;
    }

    final role = await _roleFut;

    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('loads');

    // Role-based query:
    if (role == AppRole.admin ||
        role == AppRole.manager ||
        role == AppRole.dispatcher) {
      // Can upload to any load; show recent loads (last 300)
      q = q.orderBy('createdAt', descending: true).limit(300);
    } else if (role == AppRole.mechanic ||
        role == AppRole.bookkeeper ||
        role == AppRole.viewer) {
      // read-only: still show their own delivered loads (for linking/viewing)
      q = q
          .where('driverId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'Delivered')
          .orderBy('createdAt', descending: true)
          .limit(200);
    } else {
      // driver: their own delivered loads (change to whereIn if you want more statuses)
      q = q
          .where('driverId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'Delivered')
          .orderBy('createdAt', descending: true)
          .limit(200);
    }

    final snap = await q.get();
    final items = snap.docs.map((d) {
      final m = d.data();
      final ref =
          (m['loadNumber'] ?? m['shippingNumber'] ?? m['poNumber'] ?? '')
              .toString();
      final client = (m['clientName'] ?? '').toString();
      final shipper = (m['shipperName'] ?? '').toString();
      final receiver = (m['receiverName'] ?? '').toString();
      final label = ref.isEmpty ? d.id : ref;
      final info =
          [client, shipper, receiver].where((s) => s.isNotEmpty).join(' • ');
      return _LoadItem(id: d.id, label: label, info: info);
    }).toList();

    setState(() {
      _visibleLoads = items;
      _loadingLoads = false;
      // If driver has exactly one delivered load and nothing selected, preselect
      if (_selectedLoadId == null && _visibleLoads.length == 1) {
        _selectedLoadId = _visibleLoads.first.id;
        _selectedLoadLabel = _visibleLoads.first.label;
      }
    });
  }

  List<_LoadItem> get _filteredLoads {
    if (_q.isEmpty) return _visibleLoads;
    return _visibleLoads.where((l) {
      final hay = '${l.label} ${l.info}'.toLowerCase();
      return hay.contains(_q);
    }).toList();
  }

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppRole>(
      future: _roleFut,
      builder: (context, roleSnap) {
        final role = roleSnap.data ?? AppRole.viewer;
        final canUpload = role == AppRole.admin ||
            role == AppRole.manager ||
            role == AppRole.dispatcher ||
            role == AppRole.driver;

        final readOnly = !(role == AppRole.admin ||
            role == AppRole.manager ||
            role == AppRole.dispatcher ||
            role == AppRole.driver);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Driver Document Upload'),
            actions: const [
              // remove this if you don't have the widget
              MainMenuButton(),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Role-aware hint
                if (readOnly)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Read-only: your role can view documents but cannot upload.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ),

                // LOAD FILTER + TYPE + LOAD selection row (responsive; no overflow)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1100;

                    final filterField = TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        labelText: 'Filter loads',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_loadingLoads,
                    );

                    final docTypeDropdown = DropdownButtonFormField<String>(
                      isExpanded: true, // prevent overflow with long labels
                      initialValue: _docType,
                      decoration: const InputDecoration(
                        labelText: 'Document Type',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'POD',
                          child: Text('POD (Proof of Delivery)',
                              overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'BOL',
                          child: Text('BOL (Bill of Lading)',
                              overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                            value: 'Receipt', child: Text('Receipt')),
                        DropdownMenuItem(value: 'Photo', child: Text('Photo')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: readOnly
                          ? null
                          : (v) => setState(() => _docType = v ?? 'Other'),
                    );

                    final bool selectedIsInFiltered = _selectedLoadId != null &&
                        _filteredLoads.any((l) => l.id == _selectedLoadId);

                    final loadField = _loadingLoads
                        ? InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Load',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: const SizedBox(
                              height: 24, // keep field height consistent
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          )
                        : DropdownButtonFormField<String>(
                            isExpanded: true, // prevent overflow
                            initialValue:
                                selectedIsInFiltered ? _selectedLoadId : null,
                            decoration: const InputDecoration(
                              labelText: 'Load',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _filteredLoads
                                .map(
                                  (l) => DropdownMenuItem(
                                    value: l.id,
                                    child: Text(
                                      '${l.label}  •  ${l.info}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: readOnly
                                ? null
                                : (v) {
                                    final picked = _visibleLoads.firstWhere(
                                      (x) => x.id == v,
                                      orElse: () => _LoadItem(
                                          id: v ?? '',
                                          label: v ?? '',
                                          info: ''),
                                    );
                                    setState(() {
                                      _selectedLoadId = v;
                                      _selectedLoadLabel = picked.label.isEmpty
                                          ? v
                                          : picked.label;
                                    });
                                  },
                          );

                    if (wide) {
                      // One line on wide screens
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: filterField),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: docTypeDropdown),
                          const SizedBox(width: 12),
                          Expanded(flex: 4, child: loadField),
                        ],
                      );
                    } else {
                      // Stack on narrow screens
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          filterField,
                          const SizedBox(height: 12),
                          docTypeDropdown,
                          const SizedBox(height: 12),
                          loadField,
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 10),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !readOnly,
                ),

                const SizedBox(height: 12),
                // Files row
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: readOnly || _uploading ? null : _pickFiles,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Select Files'),
                    ),
                    const SizedBox(width: 8),
                    if (_picks.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _uploading ? null : _clearPicks,
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                      ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DocumentViewerScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.folder_open),
                      label: const Text('View Documents'),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                Expanded(
                  child: _picks.isEmpty
                      ? const Center(child: Text('No files selected'))
                      : ListView.separated(
                          itemCount: _picks.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final p = _picks[i];
                            final prog = _progress[p.name] ?? 0;
                            return ListTile(
                              leading: Icon(_iconFor(p.contentType)),
                              title: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${_prettySize(p.size)} • ${p.contentType}'),
                                  if (_uploading)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: LinearProgressIndicator(
                                        value: prog == 0 ? null : prog,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: _uploading
                                  ? null
                                  : IconButton(
                                      tooltip: 'Remove',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () =>
                                          setState(() => _picks.removeAt(i)),
                                    ),
                            );
                          },
                        ),
                ),

                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: (canUpload &&
                          !_uploading &&
                          _selectedLoadId != null &&
                          _picks.isNotEmpty)
                      ? _uploadAll
                      : null,
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(_uploading ? 'Uploading…' : 'Upload'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===================== Pick files =====================

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;

    final picks = <_Pick>[];
    for (final f in res.files) {
      final name = f.name;
      final bytes = f.bytes;
      final filePath = f.path;
      final size = f.size;
      final contentType = _contentTypeFor(name);

      picks.add(_Pick(
        name: name,
        bytes: bytes,
        filePath: filePath,
        size: size,
        contentType: contentType,
      ));
    }
    setState(() => _picks.addAll(picks));
  }

  void _clearPicks() {
    setState(() {
      _picks.clear();
      _progress.clear();
    });
  }

  // ===================== Upload =====================

  Future<void> _uploadAll() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedLoadId == null || _picks.isEmpty) return;

    setState(() {
      _uploading = true;
      _progress.clear();
    });

    final uid = user.uid;
    int success = 0, failed = 0;

    // Load doc (for back-compat map write and label)
    final loadDoc = await FirebaseFirestore.instance
        .collection('loads')
        .doc(_selectedLoadId)
        .get();
    final loadData = loadDoc.data() ?? {};
    final loadRef = (loadData['loadNumber'] ??
            loadData['shippingNumber'] ??
            loadData['poNumber'] ??
            _selectedLoadLabel ??
            _selectedLoadId!)
        .toString();

    for (final p in _picks) {
      try {
        final refPath = _buildStoragePath(p.name, loadRef);
        final ref = FirebaseStorage.instance.ref(refPath);

        UploadTask task;
        final meta = SettableMetadata(
          contentType: p.contentType,
          customMetadata: _meta(uid, loadRef),
        );

        if (p.bytes != null) {
          task = ref.putData(p.bytes!, meta);
        } else if (!kIsWeb && p.filePath != null) {
          task = ref.putFile(File(p.filePath!), meta);
        } else {
          throw 'No file data available';
        }

        task.snapshotEvents.listen((snap) {
          if (snap.totalBytes > 0) {
            final v = snap.bytesTransferred / snap.totalBytes;
            setState(() => _progress[p.name] = v);
          }
        });

        await task;
        final url = await ref.getDownloadURL();

        // Write to central collection
        await FirebaseFirestore.instance.collection('documents').add({
          'name': p.name,
          'type': _docType,
          'url': url,
          'storagePath': ref.fullPath,
          'size': p.size,
          'contentType': p.contentType,
          'uploaderUid': uid,
          'loadId': _selectedLoadId,
          'loadRef': loadRef,
          'notes': _notesCtrl.text.trim(),
          'uploadedAt': FieldValue.serverTimestamp(),
        });

        // Optional: back-compat – write into load doc map `documents`
        final tag = _docType;
        final existing = (loadData['documents'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v)) ??
            {};
        existing[tag] = {
          'url': url,
          'uploadedBy': (user.email ?? uid),
          'timestamp': DateTime.now().toIso8601String(),
        };
        await loadDoc.reference
            .set({'documents': existing}, SetOptions(merge: true));

        success++;
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _uploading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Upload complete — $success succeeded, $failed failed')),
    );

    if (success > 0) {
      setState(() {
        _picks.clear();
        _progress.clear();
      });
    }
  }

  Map<String, String> _meta(String uid, String loadRef) => {
        'uploaderUid': uid,
        'docType': _docType,
        'loadRef': loadRef,
      };

  String _buildStoragePath(String originalName, String loadRef) {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final safeRef = _safe(loadRef.isEmpty ? 'misc' : loadRef);
    final safeName = _safe(originalName);
    return 'documents/$_docType/$y/$m/$safeRef/$safeName';
  }

  // ===================== utils =====================

  String _contentTypeFor(String name) {
    final ext = path.extension(name).toLowerCase().replaceFirst('.', '');
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'bmp':
        return 'image/bmp';
      case 'tif':
      case 'tiff':
        return 'image/tiff';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/vnd.rar';
      case '7z':
        return 'application/x-7z-compressed';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      default:
        return 'application/octet-stream';
    }
  }

  IconData _iconFor(String ct) {
    if (ct.startsWith('image/')) return Icons.image;
    if (ct == 'application/pdf') return Icons.picture_as_pdf;
    if (ct.startsWith('video/')) return Icons.videocam_outlined;
    if (ct.startsWith('audio/')) return Icons.audiotrack;
    if (ct.contains('excel') || ct.endsWith('sheet')) return Icons.grid_on;
    if (ct.contains('word') || ct.endsWith('document')) {
      return Icons.description_outlined;
    }
    if (ct == 'text/plain' || ct == 'text/csv' || ct == 'application/json') {
      return Icons.description_outlined;
    }
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

  String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_');
}

// ============== models ==============

class _Pick {
  final String name;
  final Uint8List? bytes;
  final String? filePath;
  final int size;
  final String contentType;
  _Pick({
    required this.name,
    required this.bytes,
    required this.filePath,
    required this.size,
    required this.contentType,
  });
}

class _LoadItem {
  final String id;
  final String label;
  final String info;
  _LoadItem({required this.id, required this.label, required this.info});
}
