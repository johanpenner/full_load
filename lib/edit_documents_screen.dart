// lib/edit_documents_screen.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'document_viewer_screen.dart';
import 'widgets/main_menu_button.dart';

// Roles system
import 'auth/roles.dart';
import 'auth/current_user_role.dart';

class EditDocumentsScreen extends StatefulWidget {
  final String loadNumber;
  final Map<String, dynamic> documents; // legacy map on loads doc

  const EditDocumentsScreen({
    super.key,
    required this.loadNumber,
    required this.documents,
  });

  @override
  State<EditDocumentsScreen> createState() => _EditDocumentsScreenState();
}

class _EditDocumentsScreenState extends State<EditDocumentsScreen> {
  // ---- Role / Scope ----
  late Future<AppRole> _roleFut;
  AppRole _role = AppRole.viewer;
  String? _uid;
  bool _loadingLoad = true;
  String? _loadId;
  String? _loadDriverId;
  Map<String, dynamic> documentMap = {}; // working copy of widget.documents

  // ---- Files (new uploads) ----
  final Map<String, _Pick> _selected = {}; // tag -> pick
  bool _uploading = false;
  double _overallProgress = 0.0;
  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB

  @override
  void initState() {
    super.initState();
    documentMap = Map<String, dynamic>.from(widget.documents);
    _roleFut = fetchCurrentUserRole();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _loadByNumber();
  }

  Future<void> _loadByNumber() async {
    try {
      // Find the load document by loadNumber; fallback to shippingNumber/poNumber if you use those instead
      final snap = await FirebaseFirestore.instance
          .collection('loads')
          .where('loadNumber', isEqualTo: widget.loadNumber)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first;
        _loadId = d.id;
        final m = d.data();
        _loadDriverId = (m['driverId'] ?? '').toString().trim();
      }
    } catch (_) {
      // ignore
    }
    if (!mounted) return;
    _role = await _roleFut;
    setState(() => _loadingLoad = false);
  }

  bool get _readOnly {
    // Admin / Manager / Dispatcher can always edit
    if (_role == AppRole.admin ||
        _role == AppRole.manager ||
        _role == AppRole.dispatcher) return false;
    // Driver can edit only their own load
    if (_role == AppRole.driver &&
        _uid != null &&
        _loadDriverId != null &&
        _uid == _loadDriverId) return false;
    // Others are read-only
    return true;
  }

  // =================== Picking Files ===================

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: true);
    if (res == null || res.files.isEmpty) return;

    for (final f in res.files) {
      final bytes = f.bytes;
      final filePath = f.path;
      int size = f.size;

      if (size <= 0 && !kIsWeb && filePath != null) {
        try {
          size = await File(filePath).length();
        } catch (_) {}
      }

      if (size > maxFileSizeBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${f.name} is too large. Max 10 MB.')),
        );
        continue;
      }

      final tag = path.basenameWithoutExtension(f.name);
      _selected[tag] = _Pick(
        name: f.name,
        bytes: bytes,
        filePath: filePath,
        size: size,
        contentType: _contentTypeFor(f.name),
      );
    }
    setState(() {});
  }

  void _removePick(String tag) {
    setState(() => _selected.remove(tag));
  }

  // =================== Upload ===================

  Future<void> _uploadAll() async {
    if (_selected.isEmpty || _readOnly) return;
    setState(() {
      _uploading = true;
      _overallProgress = 0.0;
    });

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    final email = user?.email ?? uid;

    // Ensure we know the loadId (for central collection); if not found, we can still update the legacy map
    if (_loadId == null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('loads')
            .where('loadNumber', isEqualTo: widget.loadNumber)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) _loadId = snap.docs.first.id;
      } catch (_) {}
    }

    int total = _selected.length;
    int done = 0;

    // Figure a readable loadRef for storage path and central doc
    String loadRef = widget.loadNumber;
    try {
      if (_loadId != null) {
        final d = await FirebaseFirestore.instance
            .collection('loads')
            .doc(_loadId)
            .get();
        final m = d.data() ?? {};
        final ref =
            (m['loadNumber'] ?? m['shippingNumber'] ?? m['poNumber'] ?? '')
                .toString();
        if (ref.isNotEmpty) loadRef = ref;
      }
    } catch (_) {}

    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');

    for (final entry in _selected.entries) {
      final tagBase = entry.key;
      final pick = entry.value;

      try {
        // Versioned tag in legacy map
        final tag = _versionedTag(tagBase);

        final safeRef = _safe(loadRef.isEmpty ? 'misc' : loadRef);
        final safeName = _safe(pick.name);
        final storagePath = 'documents/Other/$y/$m/$safeRef/$safeName';

        final ref = FirebaseStorage.instance.ref(storagePath);

        UploadTask task;
        if (pick.bytes != null) {
          task = ref.putData(
            pick.bytes!,
            SettableMetadata(
              contentType: pick.contentType,
              customMetadata: {
                'uploaderUid': uid,
                'docType': 'Other',
                'loadRef': loadRef,
              },
            ),
          );
        } else if (!kIsWeb && pick.filePath != null) {
          task = ref.putFile(
            File(pick.filePath!),
            SettableMetadata(
              contentType: pick.contentType,
              customMetadata: {
                'uploaderUid': uid,
                'docType': 'Other',
                'loadRef': loadRef,
              },
            ),
          );
        } else {
          throw 'No file data available';
        }

        final snap = await task;
        final url = await snap.ref.getDownloadURL();

        // Update legacy map on the load doc
        documentMap[tag] = {
          'url': url,
          'uploadedBy': email,
          'timestamp': DateTime.now().toIso8601String(),
        };

        // Write to central collection as well (if we know loadId)
        if (_loadId != null) {
          await FirebaseFirestore.instance.collection('documents').add({
            'name': pick.name,
            'type': 'Other',
            'url': url,
            'storagePath': storagePath,
            'size': pick.size,
            'contentType': pick.contentType,
            'uploaderUid': uid,
            'loadId': _loadId,
            'loadRef': loadRef,
            'notes': '', // optional on this screen
            'uploadedAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        // continue with next
      } finally {
        done++;
        setState(() => _overallProgress = done / total);
      }
    }

    setState(() {
      _selected.clear();
      _uploading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Upload complete')),
    );
  }

  String _versionedTag(String baseTag) {
    if (!documentMap.containsKey(baseTag)) return baseTag;
    int v = 2;
    while (documentMap.containsKey('${baseTag}_v$v')) {
      v++;
    }
    return '${baseTag}_v$v';
  }

  // =================== Delete & Save ===================

  Future<void> _deleteDoc(String tag) async {
    if (_readOnly) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Document?'),
            content: Text(
                'Delete "$tag"? This will remove the file and its record.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    try {
      final data = documentMap[tag];
      final url = data is String ? data : data?['url'];
      if (url != null && url.toString().contains('https://')) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
    } catch (_) {
      // ignore
    }

    setState(() => documentMap.remove(tag));
  }

  Future<void> _saveChanges() async {
    if (_readOnly) return;

    // Write back to the load's legacy map
    try {
      final snap = await FirebaseFirestore.instance
          .collection('loads')
          .where('loadNumber', isEqualTo: widget.loadNumber)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({'documents': documentMap});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Changes saved')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  // =================== UI ===================

  @override
  Widget build(BuildContext context) {
    final canEdit = !_readOnly;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Documents (${widget.loadNumber})'),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveChanges,
              tooltip: 'Save changes',
            ),
          const MainMenuButton(),
        ],
      ),
      body: _loadingLoad
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Existing documents
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Existing Documents',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('View All'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DocumentViewerScreen()),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (documentMap.isEmpty)
                  const Text('No documents on this load.')
                else
                  ...documentMap.entries.map((entry) {
                    final tag = entry.key;
                    final docData = entry.value;
                    final url = docData is String ? docData : docData['url'];
                    final uploader =
                        docData is Map ? docData['uploadedBy'] : null;
                    final uploadedAt =
                        docData is Map ? docData['timestamp'] : null;

                    return Card(
                      child: ListTile(
                        leading: _previewIcon(url?.toString() ?? ''),
                        title: Text(tag),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (url != null)
                              Text(url.toString(),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (uploader != null || uploadedAt != null)
                              Text(
                                  'Uploaded by: ${uploader ?? '-'}  •  At: ${uploadedAt ?? '-'}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        trailing: canEdit
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () => _deleteDoc(tag),
                              )
                            : null,
                        onTap: () async {
                          final uri = Uri.tryParse(url?.toString() ?? '');
                          if (uri != null) {
                            // ignore: use_build_context_synchronously
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Opening...')),
                            );
                            await _openUrl(uri);
                          }
                        },
                      ),
                    );
                  }),

                const Divider(height: 40),

                // Upload new
                Row(
                  children: [
                    const Text('Upload New Documents',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (canEdit && _selected.isNotEmpty && !_uploading)
                      TextButton.icon(
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                        onPressed: () => setState(_selected.clear),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Select Files'),
                      onPressed: canEdit && !_uploading ? _pickFiles : null,
                    ),
                    const SizedBox(width: 12),
                    if (_uploading)
                      Expanded(
                        child: Row(
                          children: [
                            const Text('Uploading...',
                                style: TextStyle(color: Colors.black54)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: LinearProgressIndicator(
                                    value: _overallProgress == 0
                                        ? null
                                        : _overallProgress)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._selected.entries
                    .map((e) => _filePreview(e.key, e.value, canEdit)),
                if (canEdit && _selected.isNotEmpty)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Upload All'),
                    onPressed: _uploading ? null : _uploadAll,
                  ),
              ],
            ),
    );
  }

  // =================== Small UI helpers ===================

  Widget _filePreview(String tag, _Pick p, bool canEdit) {
    final lower = p.name.toLowerCase();
    final leading = (lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.png'))
        ? (p.bytes != null
            ? Image.memory(p.bytes!, width: 50, height: 50, fit: BoxFit.cover)
            : (p.filePath != null
                ? Image.file(File(p.filePath!),
                    width: 50, height: 50, fit: BoxFit.cover)
                : const Icon(Icons.image)))
        : (lower.endsWith('.pdf')
            ? const Icon(Icons.picture_as_pdf, size: 40, color: Colors.red)
            : const Icon(Icons.insert_drive_file,
                size: 40, color: Colors.blue));

    return ListTile(
      leading: leading,
      title: Text(tag),
      subtitle: Text('${_prettySize(p.size)} • ${p.contentType}'),
      trailing: canEdit
          ? IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removePick(tag))
          : null,
    );
  }

  Widget _previewIcon(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png')) {
      return Image.network(url, width: 50, height: 50, fit: BoxFit.cover);
    } else if (lower.endsWith('.pdf')) {
      return const Icon(Icons.picture_as_pdf, size: 40, color: Colors.red);
    } else {
      return const Icon(Icons.insert_drive_file, size: 40, color: Colors.blue);
    }
  }

  Future<void> _openUrl(Uri uri) async {
    // Using url_launcher is fine; if you prefer share, add that too
    // import 'package:url_launcher/url_launcher.dart';
    // await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // =================== Utils ===================

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

// =================== Internal models ===================

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
