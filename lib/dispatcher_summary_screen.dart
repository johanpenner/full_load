// lib/truck_detail_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'widgets/main_menu_button.dart';
import 'quick_load_screen.dart';
import 'update_load_status.dart';

class TruckDetailScreen extends StatefulWidget {
  final String truckId; // Firestore doc id in 'trucks'
  const TruckDetailScreen({super.key, required this.truckId});

  @override
  State<TruckDetailScreen> createState() => _TruckDetailScreenState();
}

class _TruckDetailScreenState extends State<TruckDetailScreen> {
  // Filters
  DateTimeRange? _range;
  String _statusFilter = 'All';
  final _search = TextEditingController();
  String _q = '';

  // Truck info
  bool _loadingTruck = true;
  String _truckNumber = '';
  String _truckName = '';
  String _plate = '';

  // Loads data
  bool _loading = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range =
        DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
    _search.addListener(
        () => setState(() => _q = _search.text.trim().toLowerCase()));
    _loadTruck();
    _fetch();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadTruck() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('trucks')
          .doc(widget.truckId)
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

  Future<void> _fetch() async {
    setState(() => _loading = true);
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('loads')
        .where('truckId', isEqualTo: widget.truckId);

    if (_range != null) {
      final start =
          DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(
          _range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59);
      q = q
          .where('createdAt', isGreaterThanOrEqualTo: start)
          .where('createdAt', isLessThanOrEqualTo: end);
    }

    if (_statusFilter != 'All') {
      q = q.where('status', isEqualTo: _statusFilter);
    }

    q = q.orderBy('createdAt', descending: true);

    final snap = await q.get();
    setState(() {
      _docs = snap.docs;
      _loading = false;
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visibleDocs {
    var ds = _docs;
    if (_q.isNotEmpty) {
      ds = ds.where((d) {
        final m = d.data();
        final hay = [
          (m['clientName'] ?? ''),
          (m['shipperName'] ?? ''),
          (m['receiverName'] ?? ''),
          (m['deliveryAddress'] ?? ''),
          (m['loadNumber'] ?? ''),
          (m['poNumber'] ?? ''),
          (m['shippingNumber'] ?? ''),
          (m['projectNumber'] ?? ''),
        ].join(' ').toString().toLowerCase();
        return hay.contains(_q);
      }).toList();
    }
    return ds;
  }

  // ---------- Metrics ----------
  double get _totalRevenue {
    double total = 0;
    for (final d in _visibleDocs) {
      final m = d.data();
      final pricing = m['pricing'];
      if (pricing is Map) {
        final est = pricing['estimatedTotal'];
        if (est is num) {
          total += est.toDouble();
          continue;
        }
      }
      final amount = double.tryParse(m['amount']?.toString() ?? '0');
      if (amount != null) total += amount;
    }
    return total;
  }

  int get _totalMeters {
    int sum = 0;
    for (final d in _visibleDocs) {
      final m = d.data();
      final routeMeters = m['routeMeters'];
      if (routeMeters is int) sum += routeMeters;
      final h = m['handoff'];
      if (routeMeters == null && h is Map) {
        final a = (h['firstLegMeters'] ?? 0) as int;
        final b = (h['secondLegMeters'] ?? 0) as int;
        sum += (a + b);
      }
    }
    return sum;
  }

  double get _onTimePct {
    if (_visibleDocs.isEmpty) return 0;
    int onTime = 0;
    for (final d in _visibleDocs) {
      final m = d.data();
      final expected =
          _parseDate(m['expectedDeliveryAt']) ?? _parseDate(m['deliveryDate']);
      final actual = _parseDate(m['deliveredAt']);
      if (expected != null && actual != null && !actual.isAfter(expected)) {
        onTime++;
      }
    }
    return (onTime / _visibleDocs.length) * 100.0;
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _formatDistance(int meters) {
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  // ---------- Export ----------
  Future<void> _exportCSV() async {
    final rows = <List<String>>[
      [
        'Load Ref',
        'Status',
        'Client',
        'Shipper',
        'Receiver',
        'Pickup',
        'Delivery',
        'Created'
      ]
    ];
    for (final d in _visibleDocs) {
      final m = d.data();
      rows.add([
        _ref(m),
        (m['status'] ?? '').toString(),
        (m['clientName'] ?? '').toString(),
        (m['shipperName'] ?? '').toString(),
        (m['receiverName'] ?? '').toString(),
        (m['pickupAddress'] ?? '').toString(),
        (m['deliveryAddress'] ?? '').toString(),
        _fmtTs(m['createdAt']),
      ]);
    }
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/truck_${_safe(_truckNumber.isEmpty ? widget.truckId : _truckNumber)}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(path)..writeAsStringSync(csv);
    await Share.shareXFiles([XFile(file.path)],
        text:
            'Loads for Truck ${_truckNumber.isEmpty ? widget.truckId : _truckNumber}');
  }

  Future<void> _exportPDF() async {
    final pdf = pw.Document();
    final headers = [
      'Load Ref',
      'Status',
      'Client',
      'Shipper',
      'Receiver',
      'Pickup',
      'Delivery',
      'Created'
    ];

    final dataRows = _visibleDocs.map((d) {
      final m = d.data();
      return [
        _ref(m),
        (m['status'] ?? '').toString(),
        (m['clientName'] ?? '').toString(),
        (m['shipperName'] ?? '').toString(),
        (m['receiverName'] ?? '').toString(),
        (m['pickupAddress'] ?? '').toString(),
        (m['deliveryAddress'] ?? '').toString(),
        _fmtTs(m['createdAt']),
      ];
    }).toList();

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
                'Truck Loads — ${_truckNumber.isEmpty ? widget.truckId : _truckNumber}',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            if (_truckName.isNotEmpty || _plate.isNotEmpty)
              pw.Text(
                  [_truckName, _plate].where((s) => s.isNotEmpty).join(' • '),
                  style: const pw.TextStyle(fontSize: 10)),
            if (_range != null)
              pw.Text(
                  'Range: ${_fmtDate(_range!.start)} – ${_fmtDate(_range!.end)}',
                  style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: headers,
              data: dataRows,
              border: pw.TableBorder.all(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellPadding: const pw.EdgeInsets.all(6),
            ),
          ],
        ),
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/truck_${_safe(_truckNumber.isEmpty ? widget.truckId : _truckNumber)}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(path)..writeAsBytesSync(await pdf.save());
    await Share.shareXFiles([XFile(file.path)],
        text:
            'Loads for Truck ${_truckNumber.isEmpty ? widget.truckId : _truckNumber}');
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final total = _visibleDocs.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Truck — ${_truckNumber.isEmpty ? widget.truckId : _truckNumber}'),
        actions: const [MainMenuButton()],
      ),
      body: Column(
        children: [
          // Truck header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: _loadingTruck
                      ? const Text('Loading truck...')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _truckNumber.isEmpty
                                  ? 'Truck ID: ${widget.truckId}'
                                  : _truckNumber,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                            if (_truckName.isNotEmpty || _plate.isNotEmpty)
                              Text(
                                  [_truckName, _plate]
                                      .where((s) => s.isNotEmpty)
                                      .join(' • '),
                                  style:
                                      const TextStyle(color: Colors.black54)),
                          ],
                        ),
                ),
              ],
            ),
          ),
          // KPI row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _kpi('Loads', '$total'),
                const SizedBox(width: 8),
                _kpi('On-Time', '${_onTimePct.toStringAsFixed(1)}%'),
                const SizedBox(width: 8),
                _kpi('Revenue', _money(_totalRevenue)),
                const SizedBox(width: 8),
                _kpi('Distance', _formatDistance(_totalMeters)),
              ],
            ),
          ),

          // Filters
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search loads…',
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
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    value: _statusFilter,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('All')),
                      DropdownMenuItem(
                          value: 'Planned', child: Text('Planned')),
                      DropdownMenuItem(
                          value: 'Assigned', child: Text('Assigned')),
                      DropdownMenuItem(
                          value: 'En Route', child: Text('En Route')),
                      DropdownMenuItem(
                          value: 'Delivered', child: Text('Delivered')),
                    ],
                    onChanged: (v) async {
                      setState(() => _statusFilter = v ?? 'All');
                      await _fetch();
                    },
                  ),
                ),
                IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: _fetch),
              ],
            ),
          ),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (total == 0
                    ? const Center(child: Text('No loads found'))
                    : ListView.separated(
                        itemCount: _visibleDocs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final d = _visibleDocs[i];
                          final id = d.id;
                          final m = d.data();

                          final ref = _ref(m);
                          final status = (m['status'] ?? 'Planned').toString();
                          final client = (m['clientName'] ?? '').toString();
                          final shipper = (m['shipperName'] ?? '').toString();
                          final receiver = (m['receiverName'] ?? '').toString();
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
                                              ? 'Load $id'
                                              : 'Load $ref',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.edit, size: 18),
                                        label: const Text('Edit'),
                                        onPressed: () async {
                                          final changed = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) => QuickLoadScreen(
                                                    loadId: id)),
                                          );
                                          if (changed == true && mounted)
                                            _fetch();
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _summaryLine(client, shipper, receiver),
                                    style:
                                        const TextStyle(color: Colors.black54),
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
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: status,
                                          decoration: const InputDecoration(
                                            labelText: 'Status',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
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
                                          onChanged: (v) async {
                                            if (v == null) return;
                                            await updateLoadStatus(
                                                context, id, v);
                                            _fetch();
                                          },
                                        ),
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

          // Export row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Export CSV'),
                  onPressed: _visibleDocs.isEmpty ? null : _exportCSV,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                  onPressed: _visibleDocs.isEmpty ? null : _exportPDF,
                ),
              ],
            ),
          ),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${_visibleDocs.length} loads',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

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
      await _fetch();
    }
  }

  // tiny helpers
  String _ref(Map<String, dynamic> m) =>
      (m['loadNumber'] ?? m['shippingNumber'] ?? m['poNumber'] ?? '')
          .toString();

  String _fmtTs(dynamic v) {
    DateTime? dt;
    if (v is Timestamp) dt = v.toDate();
    if (v is DateTime) dt = v;
    if (v == null) return '';
    dt ??= DateTime.tryParse(v.toString());
    if (dt == null) return '';
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
            Text(value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9\-_]'), '_');
}
