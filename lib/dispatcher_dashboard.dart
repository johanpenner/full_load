<DOCUMENT filename="dispatcher_dashboard.dart">
// lib/dispatcher_dashboard.dart
// Updated: Merged dispatcher_summary_screen.dart (truck-focused elements: truck info loading, date range filter, KPIs, exports to CSV/PDF/Share).
// Now includes truck summaries/KPIs in the dashboard, with filters integrated. Retained original load list/actions. Added companyId for multi-tenant.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart'; // Add to pubspec for CSV export
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:pdf/widgets.dart' as pw; // Add pdf: ^3.10.9 to pubspec for PDF
import 'package:printing/printing.dart'; // For print/share PDF
import 'package:share_plus/share_plus.dart'; // For sharing
import 'package:path_provider/path_provider.dart'; // For temp files

import 'auth/current_user_role.dart';
import 'auth/roles.dart';
import 'util/utils.dart';
import 'load_editor.dart';
import 'update_load_status.dart';

class DispatcherDashboard extends StatefulWidget {
  final String companyId; // Added for multi-tenant
  const DispatcherDashboard({super.key, required this.companyId});

  @override
  State<DispatcherDashboard> createState() => _DispatcherDashboardState();
}

class _DispatcherDashboardState extends State<DispatcherDashboard> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _status = 'all'; // normalized value from kStatus
  AppRole _role = AppRole.viewer;

  // Merged from dispatcher_summary_screen.dart: Filters & truck data
  DateTimeRange? _range;
  final String _statusFilter = 'All';
  bool _loadingTruck = true;
  String _truckNumber = '';
  String _truckName = '';
  String _plate = '';

  // Loads data (merged)
  bool _loading = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  static const List<_StatusOpt> kStatus = [
    _StatusOpt(value: 'all', label: 'All'),
    _StatusOpt(value: 'draft', label: 'Draft'),
    _StatusOpt(value: 'planned', label: 'Planned'),
    _StatusOpt(value: 'assigned', label: 'Assigned'),
    _StatusOpt(value: 'enroute', label: 'Enroute'),
    _StatusOpt(value: 'delivered', label: 'Delivered'),
    _StatusOpt(value: 'invoiced', label: 'Invoiced'),
    _StatusOpt(value: 'on_hold', label: 'On Hold'),
    _StatusOpt(value: 'cancelled', label: 'Cancelled'),
    _StatusOpt(value: 'waiting', label: 'Waiting'),
  ];

  @override
  void initState() {
    super.initState();
    _loadRole();
    final now = DateTime.now();
    _range = DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
    _searchCtrl.addListener(
      () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()),
    );
    _loadTruck(); // Merged: Load truck info (assuming dashboard now includes truck context; adjust if per-truck)
    _fetchLoads();
  }

  Future<void> _loadRole() async {
    try {
      final r = await currentUserRole();
      if (mounted) setState(() => _role = r);
    } catch (_) {}
  }

  // Merged: Load truck info (from dispatcher_summary_screen.dart)
  Future<void> _loadTruck() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('companies/${widget.companyId}/trucks')
          .doc('default-truck-id') // Adjust: If dashboard is general, remove or make selectable
          .get();
      final m = snap.data() ?? {};
      _truckNumber = (m['number'] ?? '').toString();
      _truckName = (m['name'] ?? '').toString();
      _plate = (m['plate'] ?? '').toString();
    } catch (_) {
      // keep defaults
    } finally {
      if (mounted) setState(() => _loadingTruck = false);
    }
  }

  Query<Map<String, dynamic>> _baseQuery() {
    var q = FirebaseFirestore.instance
        .collection('companies/${widget.companyId}/loads') // Updated path
        .orderBy('createdAt', descending: true)
        .limit(50);
    if (_status != 'all') {
      q = q.where('status', isEqualTo: _status);
    }
    // Merged: Add range filter
    if (_range != null) {
      final start = DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59);
      q = q
          .where('createdAt', isGreaterThanOrEqualTo: start)
          .where('createdAt', isLessThanOrEqualTo: end);
    }
    return q;
  }

  Future<void> _fetchLoads() async {
    setState(() => _loading = true);
    Query<Map<String, dynamic>> q = _baseQuery(); // Use updated query

    try {
      final snap = await q.get();
      _docs = snap.docs;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fetch failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canEdit =>
      _role == AppRole.admin ||
      _role == AppRole.manager ||
      _role == AppRole.dispatcher;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visibleDocs {
    return _docs.where((d) {
      final m = d.data();
      final hay = [
        _ref(m),
        (m['client'] ?? '').toString(),
        (m['shipper'] ?? '').toString(),
        (m['receiver'] ?? '').toString(),
      ].join(' ').toLowerCase();
      return _query.isEmpty || hay.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatcher Dashboard'),
      ),
      body: _loading || _loadingTruck
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Merged: Truck info header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$_truckName ($_truckNumber)', style: Theme.of(context).textTheme.titleLarge),
                            Text('Plate: $_plate'),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: _pickRange,
                        tooltip: 'Date Range',
                      ),
                    ],
                  ),
                ),
                // Merged: KPIs
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _kpi('Loads', '${_visibleDocs.length}'),
                      const SizedBox(width: 8),
                      _kpi('Delivered', '${_visibleDocs.where((d) => d['status'] == 'delivered').length}'),
                      // Add more KPIs as needed
                    ],
                  ),
                ),
                // Search & status filter (original)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search load #, client, etc.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                DropdownButton<String>(
                  value: _status,
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _status = v);
                      _fetchLoads();
                    }
                  },
                  items: kStatus.map((s) => DropdownMenuItem(value: s.value, child: Text(s.label))).toList(),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _visibleDocs.length,
                    itemBuilder: (ctx, i) {
                      final d = _visibleDocs[i];
                      final m = d.data();
                      return ListTile(
                        title: Text(_ref(m)),
                        subtitle: Text(_summaryLine(m['client'] ?? '', m['shipper'] ?? '', m['receiver'] ?? '')),
                        trailing: _statusChip(m['status'] ?? 'draft'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => LoadEditor(loadId: d.id)),
                        ),
                      );
                    },
                  ),
                ),
                // Merged: Export buttons
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(onPressed: _exportCsv, child: const Text('CSV')),
                      ElevatedButton(onPressed: _exportPdf, child: const Text('PDF')),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // Merged methods from dispatcher_summary_screen.dart
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final init = _range ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
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

  Future<void> _exportCsv() async {
    final rows = [
      ['Load #', 'Client', 'Status', 'Date'],
      ..._visibleDocs.map((d) {
        final m = d.data();
        return [_ref(m), m['client'], m['status'], _fmtTs(m['createdAt'])];
      }),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = await File('${dir.path}/loads.csv').writeAsString(csv);
    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (ctx) => pw.Column(
          children: [
            pw.Text('Loads Report'),
            pw.Table.fromTextArray(data: [
              ['Load #', 'Client', 'Status', 'Date'],
              ..._visibleDocs.map((d) {
                final m = d.data();
                return [_ref(m), m['client'], m['status'], _fmtTs(m['createdAt'])];
              }),
            ]),
          ],
        ),
      ),
    );
    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final file = await File('${dir.path}/loads.pdf').writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)]);
  }

  String _ref(Map<String, dynamic> m) =>
      (m['loadNumber'] ?? m['shippingNumber'] ?? m['poNumber'] ?? '').toString();

  String _fmtTs(dynamic v) {
    DateTime? dt;
    if (v is Timestamp) dt = v.toDate();
    if (v is DateTime) dt = v;
    if (dt == null) return '';
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  String _summaryLine(String client, String shipper, String receiver) {
    final parts = <String>[];
    if (client.isNotEmpty) parts.add(client);
    if (shipper.isNotEmpty) parts.add(shipper);
    if (receiver.isNotEmpty) parts.add(receiver);
    return parts.join(' • ');
  }

  Widget _kpi(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final s = status.toLowerCase();
    Color base;
    switch (s) {
      case 'planned':
        base = Colors.blueGrey;
        break;
      case 'assigned':
        base = Colors.blue;
        break;
      case 'enroute':
        base = Colors.deepPurple;
        break;
      case 'delivered':
        base = Colors.green;
        break;
      case 'invoiced':
        base = Colors.teal;
        break;
      case 'on_hold':
        base = Colors.orange;
        break;
      case 'cancelled':
        base = Colors.red;
        break;
      case 'waiting':
        base = Colors.amber;
        break;
      case 'draft':
      default:
        base = Colors.grey;
    }
    return Chip(
      label: Text(_cap(s)),
      backgroundColor: base.withOpacity(0.12),
      labelStyle: TextStyle(color: base, fontWeight: FontWeight.w600),
      side: BorderSide(color: base.withOpacity(0.35)),
    );
  }

  String _cap(String s) => s.isEmpty
      ? s
      : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';
}

class _StatusOpt {
  final String value;
  final String label;
  const _StatusOpt({required this.value, required this.label});
}
</DOCUMENT>