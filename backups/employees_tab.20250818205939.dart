// lib/employees_tab.dart
//
// Employees tab (array-based docs, with new features)
// - Search + role filter
// - Role-based UI (admin/dispatcher manage all; a user can manage self)
// - Upload files to Storage (uploaderUid metadata) -> employees/{uid}/{filename}
// - Files viewer (open/delete) using employee.documents (array field)
// - Export one employee's files as ZIP (desktop)
// - Export filtered employees as CSV (uses array length as count)
// - Change profile photo (safe picker)
// - Time Off manager (all-day or partial time, optional reason) at employees/{uid}/time_off/{doc}

import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:url_launcher/url_launcher.dart';

import 'util/storage_upload.dart';
import 'util/safe_image_picker.dart';

class EmployeesTab extends StatefulWidget {
  const EmployeesTab({super.key});
  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab> {
  final _search = TextEditingController();
  String _query = '';
  String _roleFilter = 'all';
  bool _busy = false;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userRoleStream;

  @override
  void initState() {
    super.initState();
    if (_currentUid != null) {
      _userRoleStream = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUid)
          .snapshots();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _employeesStream() {
    return FirebaseFirestore.instance
        .collection('employees')
        .orderBy('name', descending: false)
        .limit(500)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userRoleStream,
      builder: (ctx, roleSnap) {
        final currentRole =
            roleSnap.data?.data()?['role']?.toString() ?? 'viewer';
        return Column(
          children: [
            _toolbar(currentRole),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _employeesStream(),
                builder: (ctx, snap) {
                  if (snap.hasError)
                    return Center(child: Text('Error: ${snap.error}'));
                  if (!snap.hasData)
                    return const Center(child: CircularProgressIndicator());

                  final all = snap.data!.docs;
                  final filtered = _applyFilters(all);

                  return Column(
                    children: [
                      _summary(all.length, filtered.length, currentRole),
                      const SizedBox(height: 6),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text('No employees match your filters.'))
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (c, i) =>
                                    _employeeCard(filtered[i], currentRole),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------- Top toolbar ----------

  Widget _toolbar(String currentRole) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 380,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search employees (name/email/role)…',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Role',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _roleFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'driver', child: Text('Driver')),
                  DropdownMenuItem(
                      value: 'dispatcher', child: Text('Dispatcher')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'mechanic', child: Text('Mechanic')),
                  DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                ],
                onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _exportFilteredCsv,
            icon: const Icon(Icons.table_chart),
            label: const Text('Export CSV (filtered)'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summary(int allCount, int filteredCount, String currentRole) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.people_alt_outlined),
          const SizedBox(width: 8),
          Text('Employees: $filteredCount / $allCount shown'),
          const Spacer(),
          Text(
            'Role: $currentRole • Filters: role=${_roleFilter == 'all' ? 'any' : _roleFilter}'
            '${_query.isEmpty ? '' : ', search="$_query"'}',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // ---------- Employee card ----------

  Widget _employeeCard(
      QueryDocumentSnapshot<Map<String, dynamic>> d, String currentRole) {
    final m = d.data();
    final uid = d.id;
    final name = (m['name'] ?? '(no name)').toString();
    final email = (m['email'] ?? '').toString();
    final phone = (m['phone'] ?? '').toString();
    final role = (m['role'] ?? '').toString();
    final photoUrl = (m['photoUrl'] ?? '').toString();
    final docs = (m['documents'] is List) ? (m['documents'] as List) : const [];

    final canManage = _canManageEmployee(uid, currentRole);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage:
                        photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.isEmpty
                        ? Text(_initials(name),
                            style: const TextStyle(fontWeight: FontWeight.bold))
                        : null,
                  ),
                  if (canManage)
                    Positioned(
                      right: -8,
                      bottom: -8,
                      child: IconButton.filledTonal(
                        tooltip: 'Change photo',
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        onPressed: () =>
                            _changeEmployeePhoto(uid, photoUrl, context),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (role.isNotEmpty) role,
                          if (email.isNotEmpty) email,
                          if (phone.isNotEmpty) phone,
                        ].join(' • '),
                        style: const TextStyle(color: Colors.black54),
                      ),
                      if (docs.isNotEmpty)
                        Text('${docs.length} files',
                            style: const TextStyle(color: Colors.black54)),
                    ]),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: canManage
                        ? () => _uploadEmployeeFiles(uid, context)
                        : null,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openFilesSheet(uid, name),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Files'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canManage
                        ? () => _exportEmployeeZip(uid, name, docs)
                        : null,
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Export ZIP'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openTimeOffSheet(uid, name, canManage),
                    icon: const Icon(Icons.event_busy),
                    label: const Text('Time Off'),
                  ),
                ],
              ),
            ],
          ),
        ]),
      ),
    );
  }

  // ---------- Helpers ----------

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> all) {
    return all.where((d) {
      final m = d.data();
      final name = (m['name'] ?? '').toString().toLowerCase();
      final email = (m['email'] ?? '').toString().toLowerCase();
      final role = (m['role'] ?? '').toString().toLowerCase();
      if (_roleFilter != 'all' && role != _roleFilter) return false;
      if (_query.isEmpty) return true;
      return name.contains(_query) ||
          email.contains(_query) ||
          role.contains(_query);
    }).toList();
  }

  bool _canManageEmployee(String employeeUid, String currentRole) {
    if (currentRole == 'admin' || currentRole == 'dispatcher') return true;
    if (_currentUid != null && _currentUid == employeeUid) return true;
    return false;
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1)
      return parts.first.isEmpty ? '?' : parts.first[0].toUpperCase();
    return (parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '') +
        (parts.last.isNotEmpty ? parts.last[0].toUpperCase() : '');
  }

  String _contentTypeForName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  String _fmtWhen(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}';
    }
    return '';
  }

  String _2(int n) => n.toString().padLeft(2, '0');

  // ---------- Uploads (array-based documents) ----------

  Future<void> _uploadEmployeeFiles(
      String employeeUid, BuildContext context) async {
    try {
      final picked = await FilePicker.platform
          .pickFiles(allowMultiple: true, withData: true);
      if (picked == null || picked.files.isEmpty) return;

      final docRef =
          FirebaseFirestore.instance.collection('employees').doc(employeeUid);

      for (final f in picked.files) {
        final name = f.name;
        final ct = _contentTypeForName(name);
        final storagePath = 'employees/$employeeUid/$name';

        // Upload via helpers so Storage metadata includes uploaderUid
        final url = f.bytes != null
            ? await uploadBytesWithMeta(
                refPath: storagePath,
                bytes: f.bytes!,
                contentType: ct,
                extraMeta: {'employeeUid': employeeUid},
              )
            : await uploadFilePathWithMeta(
                refPath: storagePath,
                filePath: f.path!,
                contentType: ct,
                extraMeta: {'employeeUid': employeeUid},
              );

        await docRef.set({
          'documents': FieldValue.arrayUnion([
            {
              'name': name,
              'url': url,
              'storagePath': storagePath,
              'size': f.size,
              'contentType': ct,
              'uploadedAt': FieldValue.serverTimestamp(),
            }
          ])
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee files uploaded')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  // ---------- Files viewer (array) ----------

  Future<void> _openFilesSheet(String employeeUid, String name) async {
    final snap = await FirebaseFirestore.instance
        .collection('employees')
        .doc(employeeUid)
        .get();
    final m = snap.data() ?? {};
    final List docs = (m['documents'] ?? []) as List;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Files — $name',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (docs.isEmpty)
                  const Expanded(
                      child: Center(child: Text('No files uploaded yet.')))
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (c, i) {
                        final Map<String, dynamic> it = (docs[i] as Map)
                            .map((k, v) => MapEntry(k.toString(), v));
                        final fname = (it['name'] ?? '').toString();
                        final url = (it['url'] ?? '').toString();
                        final ct = (it['contentType'] ?? '').toString();
                        final ts = it['uploadedAt'];
                        final when = _fmtWhen(ts);

                        return ListTile(
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(fname, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${ct.isEmpty ? 'file' : ct} • $when'),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Open',
                                icon: const Icon(Icons.open_in_new),
                                onPressed: () => launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    _confirmDeleteEmployeeFile(employeeUid, it),
                              ),
                            ],
                          ),
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
  }

  Future<void> _confirmDeleteEmployeeFile(
      String employeeUid, Map<String, dynamic> item) async {
    if (!mounted) return;
    final fname = (item['name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text('Remove "$fname" from Storage and employee record?'),
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
    if (ok == true) {
      await _deleteEmployeeFile(employeeUid, item);
    }
  }

  Future<void> _deleteEmployeeFile(
      String employeeUid, Map<String, dynamic> item) async {
    try {
      final url = (item['url'] ?? '').toString();
      final storagePath = (item['storagePath'] ?? '').toString();

      try {
        if (storagePath.isNotEmpty) {
          await FirebaseStorage.instance.ref(storagePath).delete();
        } else if (url.isNotEmpty) {
          await FirebaseStorage.instance.refFromURL(url).delete();
        }
      } catch (_) {/* ignore */}

      // Remove from the array
      final docRef =
          FirebaseFirestore.instance.collection('employees').doc(employeeUid);
      final snap = await docRef.get();
      final data = snap.data() ?? {};
      final List docs = (data['documents'] ?? []) as List;
      final newDocs = docs.where((x) {
        final mx = (x as Map).map((k, v) => MapEntry(k.toString(), v));
        return (mx['url'] ?? '') != url;
      }).toList();

      await docRef.update({'documents': newDocs});

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('File deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  // ---------- Export ZIP (array) ----------

  Future<void> _exportEmployeeZip(
      String employeeUid, String name, List docs) async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ZIP export not supported on Web.')),
      );
      return;
    }
    try {
      setState(() => _busy = true);

      if (docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No files to export.')));
        }
        setState(() => _busy = false);
        return;
      }

      final archive = Archive();
      for (final entry in docs) {
        final mx = (entry as Map).map((k, v) => MapEntry(k.toString(), v));
        final url = (mx['url'] ?? '').toString();
        final fname = (mx['name'] ?? 'file').toString();
        if (url.isEmpty) continue;

        final res = await http.get(Uri.parse(url));
        if (res.statusCode == 200) {
          final data = res.bodyBytes;
          archive.addFile(ArchiveFile(fname, data.length, data));
        }
      }

      final bytes = ZipEncoder().encode(archive);
      final safeName = name.trim().isEmpty
          ? 'employee'
          : name.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '_');
      final ts = DateTime.now();
      final base =
          io.Platform.environment['USERPROFILE'] ?? io.Directory.current.path;
      final path = io.Platform.isWindows
          ? '$base\\Downloads\\${safeName}_files_${ts.year}${_2(ts.month)}${_2(ts.day)}_${_2(ts.hour)}${_2(ts.minute)}.zip'
          : '$base/${safeName}_files_${ts.year}${_2(ts.month)}${_2(ts.day)}_${_2(ts.hour)}${_2(ts.minute)}.zip';

      final file = io.File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!, flush: true);

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ZIP saved: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ZIP export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Export CSV (filtered list) ----------

  Future<void> _exportFilteredCsv() async {
    if (kIsWeb) {
      // Show CSV so you can copy on web
      try {
        setState(() => _busy = true);
        final snap = await _employeesStream().first;
        final data = _applyFilters(snap.docs);
        final csv = _buildCsvFromDocs(data);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('CSV (copy to clipboard)'),
            content: SizedBox(
                width: 600,
                child: SingleChildScrollView(child: SelectableText(csv))),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'))
            ],
          ),
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    try {
      setState(() => _busy = true);
      final snap = await _employeesStream().first;
      final data = _applyFilters(snap.docs);
      final csv = _buildCsvFromDocs(data);

      final ts = DateTime.now();
      final base =
          io.Platform.environment['USERPROFILE'] ?? io.Directory.current.path;
      final path = io.Platform.isWindows
          ? '$base\\Downloads\\employees_filtered_${ts.year}${_2(ts.month)}${_2(ts.day)}_${_2(ts.hour)}${_2(ts.minute)}.csv'
          : '$base/employees_filtered_${ts.year}${_2(ts.month)}${_2(ts.day)}_${_2(ts.hour)}${_2(ts.minute)}.csv';

      final file = io.File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(csv, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('CSV saved: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('CSV export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _buildCsvFromDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> data) {
    final header = ['uid', 'name', 'email', 'phone', 'role', 'filesCount'];
    final rows = <List<String>>[header];

    for (final d in data) {
      final m = d.data();
      final docs =
          (m['documents'] is List) ? (m['documents'] as List).length : 0;
      rows.add([
        d.id,
        (m['name'] ?? '').toString(),
        (m['email'] ?? '').toString(),
        (m['phone'] ?? '').toString(),
        (m['role'] ?? '').toString(),
        docs.toString(),
      ]);
    }

    String esc(String s) {
      if (s.contains(',') || s.contains('"') || s.contains('\n')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    return rows.map((r) => r.map(esc).join(',')).join('\n');
  }

  // ---------- Profile photo ----------

  Future<void> _changeEmployeePhoto(
      String employeeUid, String existingUrl, BuildContext context) async {
    try {
      final x =
          await safePickImage(); // camera fallback handled internally for desktop
      if (x == null) return;

      final bytes = await x.readAsBytes();
      final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'employees/$employeeUid/profile/$fileName';

      final url = await uploadBytesWithMeta(
        refPath: storagePath,
        bytes: bytes,
        contentType: 'image/jpeg',
        extraMeta: {'employeeUid': employeeUid, 'kind': 'profilePhoto'},
      );

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeUid)
          .set({'photoUrl': url}, SetOptions(merge: true));

      if (existingUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(existingUrl).delete();
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Photo updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Photo update failed: $e')));
    }
  }

  // =========================
  //       TIME OFF (NEW)
  // =========================

  Future<void> _openTimeOffSheet(
      String employeeUid, String name, bool canManage) async {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final q = FirebaseFirestore.instance
            .collection('employees')
            .doc(employeeUid)
            .collection('time_off')
            .orderBy('start', descending: true);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('Time Off — $name',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  if (canManage)
                    FilledButton.icon(
                      onPressed: () => _showTimeOffDialog(employeeUid),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: q.snapshots(),
                    builder: (c, snap) {
                      if (!snap.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final docs = snap.data!.docs;
                      if (docs.isEmpty)
                        return const Center(
                            child: Text('No time off entries yet.'));
                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (c, i) {
                          final d = docs[i];
                          final m = d.data();
                          final tsStart = m['start'] as Timestamp?;
                          final tsEnd = m['end'] as Timestamp?;
                          final allDay = (m['allDay'] ?? false) as bool;
                          final reason = (m['reason'] ?? '').toString();
                          final s = tsStart?.toDate();
                          final e = tsEnd?.toDate();
                          final title = (s != null && e != null)
                              ? _fmtRange(s, e, allDay)
                              : '(invalid range)';

                          return ListTile(
                            leading: const Icon(Icons.event_busy),
                            title: Text(title),
                            subtitle: reason.isNotEmpty ? Text(reason) : null,
                            trailing: canManage
                                ? IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () =>
                                        _deleteTimeOff(employeeUid, d.id),
                                  )
                                : null,
                            onTap: canManage
                                ? () => _showTimeOffDialog(employeeUid,
                                    existingId: d.id, existing: m)
                                : null,
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
  }

  String _fmtRange(DateTime s, DateTime e, bool allDay) {
    String d(DateTime x) =>
        '${x.year}-${_2(x.month)}-${_2(x.day)}${allDay ? '' : ' ${_2(x.hour)}:${_2(x.minute)}'}';
    return '${d(s)}  →  ${d(e)}${allDay ? '  (all day)' : ''}';
  }

  Future<void> _deleteTimeOff(String employeeUid, String entryId) async {
    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeUid)
          .collection('time_off')
          .doc(entryId)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Time off removed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _showTimeOffDialog(
    String employeeUid, {
    String? existingId,
    Map<String, dynamic>? existing,
  }) async {
    DateTime now = DateTime.now();
    bool allDay = (existing?['allDay'] ?? true) as bool;
    DateTime startDate = (existing?['start'] is Timestamp)
        ? (existing!['start'] as Timestamp).toDate()
        : now;
    DateTime endDate = (existing?['end'] is Timestamp)
        ? (existing!['end'] as Timestamp).toDate()
        : now;

    TimeOfDay startTime =
        TimeOfDay(hour: startDate.hour, minute: startDate.minute);
    TimeOfDay endTime = TimeOfDay(hour: endDate.hour, minute: endDate.minute);

    final reasonCtrl =
        TextEditingController(text: (existing?['reason'] ?? '').toString());

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          Future<void> pickStartDate() async {
            final pick = await showDatePicker(
              context: ctx,
              initialDate: startDate,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 3),
            );
            if (pick != null) setSt(() => startDate = pick);
          }

          Future<void> pickEndDate() async {
            final pick = await showDatePicker(
              context: ctx,
              initialDate: endDate.isBefore(startDate) ? startDate : endDate,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 3),
            );
            if (pick != null) setSt(() => endDate = pick);
          }

          Future<void> pickStartTime() async {
            final pick =
                await showTimePicker(context: ctx, initialTime: startTime);
            if (pick != null) setSt(() => startTime = pick);
          }

          Future<void> pickEndTime() async {
            final pick =
                await showTimePicker(context: ctx, initialTime: endTime);
            if (pick != null) setSt(() => endTime = pick);
          }

          return AlertDialog(
            title: Text(existingId == null ? 'Add Time Off' : 'Edit Time Off'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: allDay,
                    onChanged: (v) => setSt(() => allDay = v),
                    title: const Text('All day (dates only)'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: pickStartDate,
                        icon: const Icon(Icons.event),
                        label: Text(
                            'Start: ${startDate.year}-${_2(startDate.month)}-${_2(startDate.day)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: pickEndDate,
                        icon: const Icon(Icons.event),
                        label: Text(
                            'End: ${endDate.year}-${_2(endDate.month)}-${_2(endDate.day)}'),
                      ),
                    ),
                  ]),
                  if (!allDay) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: pickStartTime,
                          icon: const Icon(Icons.schedule),
                          label: Text(
                              'From: ${_2(startTime.hour)}:${_2(startTime.minute)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: pickEndTime,
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                              'To: ${_2(endTime.hour)}:${_2(endTime.minute)}'),
                        ),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final start = allDay
                      ? DateTime(startDate.year, startDate.month, startDate.day,
                          0, 0, 0)
                      : DateTime(startDate.year, startDate.month, startDate.day,
                          startTime.hour, startTime.minute);
                  final end = allDay
                      ? DateTime(
                          endDate.year, endDate.month, endDate.day, 23, 59, 59)
                      : DateTime(endDate.year, endDate.month, endDate.day,
                          endTime.hour, endTime.minute);

                  if (!end.isAfter(start)) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('End must be after start')),
                      );
                    }
                    return;
                  }

                  final data = {
                    'start': Timestamp.fromDate(start),
                    'end': Timestamp.fromDate(end),
                    'allDay': allDay,
                    'reason': reasonCtrl.text.trim(),
                    'createdAt': FieldValue.serverTimestamp(),
                    'createdBy': _currentUid,
                  };

                  final col = FirebaseFirestore.instance
                      .collection('employees')
                      .doc(employeeUid)
                      .collection('time_off');

                  try {
                    if (existingId == null) {
                      await col.add(data);
                    } else {
                      await col.doc(existingId).update(data);
                    }
                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(existingId == null
                                ? 'Time off added'
                                : 'Time off updated')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Save failed: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }
}
