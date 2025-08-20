// lib/employee_detail_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets/main_menu_button.dart';
import 'quick_load_screen.dart';
import 'document_viewer_screen.dart';

// roles
import 'auth/roles.dart';
import 'auth/current_user_role.dart';

class EmployeeDetailScreen extends StatefulWidget {
  final String employeeId;
  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen>
    with SingleTickerProviderStateMixin {
  late Future<AppRole> _roleFut;
  AppRole _role = AppRole.viewer;

  // employee core
  bool _loading = true;
  Map<String, dynamic> _emp = {};
  String _name = '';
  String _email = '';
  String _mobile = '';
  String _work = '';
  String _position = '';

  late TabController _tabs;

  // Loads filters
  DateTimeRange? _range;
  String _statusFilter = 'All';
  bool _loadingLoads = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _loads = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _roleFut = fetchCurrentUserRole();
    _init();
  }

  Future<void> _init() async {
    final r = await _roleFut;
    if (!mounted) return;
    _role = r;

    await _loadEmployee();
    await _fetchLoads();
  }

  Future<void> _loadEmployee() async {
    setState(() => _loading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .get();
      final m = doc.data() ?? {};
      _emp = m;
      _name = ((m['firstName'] ?? '') + ' ' + (m['lastName'] ?? '')).trim();
      _email = (m['email'] ?? '').toString();
      _mobile = (m['mobilePhone'] ?? '').toString();
      _work = (m['workPhone'] ?? '').toString();
      _position = (m['position'] ?? '').toString();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ===================== LOADS =====================
  Future<void> _fetchLoads() async {
    setState(() => _loadingLoads = true);
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('loads')
        .where('driverId', isEqualTo: widget.employeeId);

    if (_range != null) {
      final s =
          DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final e = DateTime(
          _range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59);
      q = q
          .where('createdAt', isGreaterThanOrEqualTo: s)
          .where('createdAt', isLessThanOrEqualTo: e);
    }
    if (_statusFilter != 'All') {
      q = q.where('status', isEqualTo: _statusFilter);
    }
    q = q.orderBy('createdAt', descending: true);

    try {
      final snap = await q.get();
      if (!mounted) return;
      setState(() {
        _loads = snap.docs;
        _loadingLoads = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLoads = false);
    }
  }

  // ===================== ACTIONS =====================
  Future<void> _updateStatus(String loadId, String newStatus) async {
    await FirebaseFirestore.instance.collection('loads').doc(loadId).update({
      'status': newStatus,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status updated')),
      );
      _fetchLoads();
    }
  }

  // ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    final canDispatch =
        can(_role, AppPerm.editDispatch) || can(_role, AppPerm.manageUsers);
    final canManageTimeOff = _role == AppRole.admin || _role == AppRole.manager;
    final canDeleteDocs = _role == AppRole.admin || _role == AppRole.manager;

    return Scaffold(
      appBar: AppBar(
        title: Text(_name.isEmpty ? 'Employee' : _name),
        actions: const [MainMenuButton()],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Loads'),
            Tab(icon: Icon(Icons.event_busy), text: 'Time Off'),
            Tab(icon: Icon(Icons.folder_open), text: 'Documents'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _headerCard(),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _loadsTab(canDispatch),
                      _timeOffTab(canManageTimeOff),
                      _docsTab(canDeleteDocs),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _headerCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              child: Text(_name.isEmpty ? '?' : _name[0].toUpperCase()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_name.isEmpty ? '(Unnamed)' : _name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  if (_position.isNotEmpty)
                    Text(_position,
                        style: const TextStyle(color: Colors.black54)),
                  if (_email.isNotEmpty)
                    Text(_email, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            Wrap(
              spacing: 6,
              children: [
                if (_mobile.isNotEmpty)
                  IconButton(
                    tooltip: 'Call mobile',
                    icon: const Icon(Icons.call),
                    onPressed: () => _call(_mobile),
                  ),
                if (_mobile.isNotEmpty)
                  IconButton(
                    tooltip: 'Text mobile',
                    icon: const Icon(Icons.sms_outlined),
                    onPressed: () => _sms(_mobile),
                  ),
                if (_email.isNotEmpty)
                  IconButton(
                    tooltip: 'Email',
                    icon: const Icon(Icons.email_outlined),
                    onPressed: () => _emailTo(_email),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Loads tab ----------
  Widget _loadsTab(bool canDispatch) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(_range == null
                      ? 'Pick date range'
                      : '${_fmtDate(_range!.start)} – ${_fmtDate(_range!.end)}'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All')),
                    DropdownMenuItem(value: 'Planned', child: Text('Planned')),
                    DropdownMenuItem(
                        value: 'Assigned', child: Text('Assigned')),
                    DropdownMenuItem(
                        value: 'En Route', child: Text('En Route')),
                    DropdownMenuItem(
                        value: 'Delivered', child: Text('Delivered')),
                  ],
                  onChanged: (v) async {
                    setState(() => _statusFilter = v ?? 'All');
                    await _fetchLoads();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: _fetchLoads,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingLoads
              ? const Center(child: CircularProgressIndicator())
              : (_loads.isEmpty
                  ? const Center(child: Text('No loads found'))
                  : ListView.separated(
                      itemCount: _loads.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final d = _loads[i];
                        final m = d.data();

                        final ref = (m['loadNumber'] ??
                                m['shippingNumber'] ??
                                m['poNumber'] ??
                                '')
                            .toString();
                        final status = (m['status'] ?? 'Planned').toString();
                        final pickup = (m['pickupAddress'] ?? '').toString();
                        final delivery =
                            (m['deliveryAddress'] ?? '').toString();

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ref.isEmpty
                                            ? 'Load ${d.id}'
                                            : 'Load $ref',
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (canDispatch)
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.edit, size: 18),
                                        label: const Text('Edit'),
                                        onPressed: () async {
                                          final changed = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  QuickLoadScreen(loadId: d.id),
                                            ),
                                          );
                                          if (changed == true && mounted)
                                            _fetchLoads();
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('Pickup: $pickup',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                Text('Delivery: $delivery',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Chip(label: Text(status)),
                                    const Spacer(),
                                    if (canDispatch)
                                      DropdownButton<String>(
                                        value: status,
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'Planned',
                                              child: Text('Planned')),
                                          DropdownMenuItem(
                                              value: 'Assigned',
                                              child: Text('Assigned')),
                                          DropdownMenuItem(
                                              value: 'En Route',
                                              child: Text('En Route')),
                                          DropdownMenuItem(
                                              value: 'Delivered',
                                              child: Text('Delivered')),
                                        ],
                                        onChanged: (v) {
                                          if (v != null) _updateStatus(d.id, v);
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )),
        ),
      ],
    );
  }

  // ---------- Time off tab ----------
  Widget _timeOffTab(bool canManage) {
    final q = FirebaseFirestore.instance
        .collection('employees')
        .doc(widget.employeeId)
        .collection('time_off')
        .orderBy('start', descending: true);

    return Column(
      children: [
        if (canManage)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: FilledButton.icon(
                onPressed: () => _openTimeOffDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add Time Off'),
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (c, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text('No time off entries.'));
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final d = docs[i];
                  final m = d.data();
                  final s = _toDate(m['start']);
                  final e = _toDate(m['end']);
                  final allDay = (m['allDay'] ?? false) as bool;
                  final reason = (m['reason'] ?? '').toString();

                  final range = (s == null || e == null)
                      ? '(invalid range)'
                      : '${_fmtDate(s)} ${allDay ? '' : ' ${_two(s.hour)}:${_two(s.minute)}'}'
                          '  →  ${_fmtDate(e)}${allDay ? '' : ' ${_two(e.hour)}:${_two(e.minute)}'}';

                  return ListTile(
                    leading: const Icon(Icons.event_busy),
                    title: Text(range),
                    subtitle: reason.isNotEmpty ? Text(reason) : null,
                    trailing: canManage
                        ? Wrap(
                            spacing: 6,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _openTimeOffDialog(
                                    existingId: d.id, existing: m),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () async {
                                  await FirebaseFirestore.instance
                                      .collection('employees')
                                      .doc(widget.employeeId)
                                      .collection('time_off')
                                      .doc(d.id)
                                      .delete();
                                },
                              ),
                            ],
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openTimeOffDialog(
      {String? existingId, Map<String, dynamic>? existing}) async {
    DateTime now = DateTime.now();
    bool allDay = (existing?['allDay'] ?? true) as bool;
    DateTime startDate = _toDate(existing?['start']) ?? now;
    DateTime endDate = _toDate(existing?['end']) ?? now;
    final reasonCtrl =
        TextEditingController(text: (existing?['reason'] ?? '').toString());

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existingId == null ? 'Add Time Off' : 'Edit Time Off'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  value: allDay,
                  onChanged: (v) => setLocal(() => allDay = v),
                  title: const Text('All day (dates only)'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final pick = await showDatePicker(
                          context: ctx,
                          initialDate: startDate,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 3),
                        );
                        if (pick != null) setLocal(() => startDate = pick);
                      },
                      icon: const Icon(Icons.event),
                      label: Text('Start: ${_fmtDate(startDate)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final pick = await showDatePicker(
                          context: ctx,
                          initialDate:
                              endDate.isBefore(startDate) ? startDate : endDate,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 3),
                        );
                        if (pick != null) setLocal(() => endDate = pick);
                      },
                      icon: const Icon(Icons.event),
                      label: Text('End: ${_fmtDate(endDate)}'),
                    ),
                  ),
                ]),
                if (!allDay) ...[
                  const SizedBox(height: 8),
                  Text('Time mode not implemented here (all-day only).',
                      style: TextStyle(color: Colors.black54)),
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
                if (!endDate.isAfter(startDate)) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('End must be after start')),
                  );
                  return;
                }
                final data = {
                  'start': Timestamp.fromDate(
                      DateTime(startDate.year, startDate.month, startDate.day)),
                  'end': Timestamp.fromDate(DateTime(
                      endDate.year, endDate.month, endDate.day, 23, 59, 59)),
                  'allDay': true,
                  'reason': reasonCtrl.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                final col = FirebaseFirestore.instance
                    .collection('employees')
                    .doc(widget.employeeId)
                    .collection('time_off');
                if (existingId == null) {
                  await col.add(data);
                } else {
                  await col.doc(existingId).update(data);
                }
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Documents tab ----------
  Widget _docsTab(bool canDelete) {
    // Show employee root files array
    final files = (_emp['files'] is List) ? (_emp['files'] as List) : const [];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Text('Documents (${files.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DocumentViewerScreen()));
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Document Viewer'),
              ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? const Center(child: Text('No documents found.'))
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = files[i];
                    if (f is! Map) return const SizedBox.shrink();
                    final name = (f['name'] ?? '').toString();
                    final url = (f['url'] ?? '').toString();
                    final ct = (f['contentType'] ?? '').toString();
                    final folder = (f['folder'] ?? '').toString();
                    final cat = (f['category'] ?? '').toString();

                    return ListTile(
                      leading: Icon(_iconFor(ct)),
                      title: Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          cat.isEmpty ? 'file' : cat,
                          folder.isEmpty ? '—' : folder,
                          ct.isEmpty ? 'mime' : ct
                        ].join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Open',
                            icon: const Icon(Icons.open_in_new),
                            onPressed: url.isEmpty ? null : () => _openUrl(url),
                          ),
                          IconButton(
                            tooltip: 'Copy link',
                            icon: const Icon(Icons.link),
                            onPressed: url.isEmpty ? null : () => _copy(url),
                          ),
                          if (canDelete)
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () async {
                                // remove from storage + array
                                await _deleteEmployeeFile(name, url);
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _deleteEmployeeFile(String name, String url) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete document?'),
            content: Text(
                'Delete "$name"? This will remove the file and its record.'),
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
      if (url.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
      // remove from array
      final files = (_emp['files'] as List).cast<dynamic>();
      files.removeWhere(
          (x) => (x is Map) && x['url'] == url && x['name'] == name);
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .update({'files': files});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Deleted')));
        _loadEmployee();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  // ---------- utilities ----------
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final init = _range ??
        DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: init,
      saveText: 'Apply',
    );
    if (picked != null) {
      setState(() => _range = picked);
      await _fetchLoads();
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _call(String raw) {
    final s = raw.replaceAll(RegExp(r'[^0-9+*#]'), '');
    if (s.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: s);
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _sms(String raw) async {
    final s = raw.replaceAll(RegExp(r'[^0-9+*#]'), '');
    if (s.isEmpty) return;
    final uri = Uri(scheme: 'sms', path: s);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _emailTo(String email) {
    final e = email.trim();
    if (e.isEmpty) return;
    final uri = Uri(scheme: 'mailto', path: e);
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copy(String url) async {
    // import 'package:flutter/services.dart' if you want copy to clipboard here
    // Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Link copied (clipboard not wired here)')));
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

  String _two(int n) => n.toString().padLeft(2, '0');
}
