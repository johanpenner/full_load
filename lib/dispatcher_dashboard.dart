// lib/dispatcher_dashboard.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'update_load_status.dart';
import 'quick_load_screen.dart';
import 'widgets/main_menu_button.dart';

class DispatcherDashboard extends StatefulWidget {
  const DispatcherDashboard({super.key});

  @override
  State<DispatcherDashboard> createState() => _DispatcherDashboardState();
}

class _DispatcherDashboardState extends State<DispatcherDashboard> {
  final _search = TextEditingController();
  String _q = '';
  String _statusFilter =
      'All'; // All | Planned | Assigned | En Route | Delivered

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
        .limit(500)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatcher Dashboard'),
        actions: const [
          MainMenuButton(),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText:
                        'Search by client, shipper, receiver, load #, PO #',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
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
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  var docs = snap.data!.docs;

                  // Filter by status
                  if (_statusFilter != 'All') {
                    docs = docs.where((d) {
                      final s = (d.data()['status'] ?? '').toString();
                      return s.toLowerCase() == _statusFilter.toLowerCase();
                    }).toList();
                  }

                  // Search
                  if (_q.isNotEmpty) {
                    docs = docs.where((d) {
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

                  if (docs.isEmpty) {
                    return const Center(child: Text('No loads to show'));
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final id = d.id;
                      final m = d.data();

                      final status = (m['status'] ?? 'Planned').toString();
                      final loadRef = (m['loadNumber'] ??
                              m['shippingNumber'] ??
                              m['poNumber'] ??
                              '')
                          .toString();
                      final client = (m['clientName'] ?? '').toString();
                      final shipper = (m['shipperName'] ?? '').toString();
                      final receiver = (m['receiverName'] ?? '').toString();
                      final pickup = (m['pickupAddress'] ?? '').toString();
                      final delivery = (m['deliveryAddress'] ?? '').toString();
                      final driverId = (m['driverId'] ?? '').toString();
                      final truckId = (m['truckId'] ?? '').toString();

                      return _LoadCard(
                        loadId: id,
                        status: status,
                        loadRef: loadRef,
                        client: client,
                        shipper: shipper,
                        receiver: receiver,
                        pickup: pickup,
                        delivery: delivery,
                        driverId: driverId.isEmpty ? null : driverId,
                        truckId: truckId.isEmpty ? null : truckId,
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
}

class _LoadCard extends StatefulWidget {
  final String loadId;
  final String status;
  final String loadRef;
  final String client;
  final String shipper;
  final String receiver;
  final String pickup;
  final String delivery;
  final String? driverId;
  final String? truckId;

  const _LoadCard({
    required this.loadId,
    required this.status,
    required this.loadRef,
    required this.client,
    required this.shipper,
    required this.receiver,
    required this.pickup,
    required this.delivery,
    required this.driverId,
    required this.truckId,
  });

  @override
  State<_LoadCard> createState() => _LoadCardState();
}

class _LoadCardState extends State<_LoadCard> {
  late String _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.status;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.loadRef.isEmpty
        ? 'Load ${widget.loadId.substring(0, 6)}'
        : 'Load ${widget.loadRef}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: title + actions
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    // Edit button
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                      onPressed: () async {
                        final changed = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  QuickLoadScreen(loadId: widget.loadId)),
                        );
                        if (changed == true && mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Summary line
            Text(
              _buildSummary(widget.client, widget.shipper, widget.receiver),
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 6),
            // Addresses
            Text('Pickup: ${widget.pickup}',
                maxLines: 2, overflow: TextOverflow.ellipsis),
            Text('Delivery: ${widget.delivery}',
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),

            // Driver row (with call/text if phone available)
            _DriverRow(driverId: widget.driverId, truckId: widget.truckId),

            const SizedBox(height: 8),

            // Status row
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'Planned', child: Text('Planned')),
                      DropdownMenuItem(
                          value: 'Assigned', child: Text('Assigned')),
                      DropdownMenuItem(
                          value: 'En Route', child: Text('En Route')),
                      DropdownMenuItem(
                          value: 'Delivered', child: Text('Delivered')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedStatus = v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.update),
                  label: const Text('Update'),
                  onPressed: () async {
                    await updateLoadStatus(
                        context, widget.loadId, _selectedStatus);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildSummary(String client, String shipper, String receiver) {
    final parts = <String>[];
    if (client.isNotEmpty) parts.add(client);
    if (shipper.isNotEmpty) parts.add(shipper);
    if (receiver.isNotEmpty) parts.add(receiver);
    return parts.join(' • ');
  }
}

class _DriverRow extends StatelessWidget {
  final String? driverId;
  final String? truckId;
  const _DriverRow({required this.driverId, required this.truckId});

  @override
  Widget build(BuildContext context) {
    if (driverId == null && (truckId == null || truckId!.isEmpty)) {
      return const Text('Driver/Truck: Unassigned');
    }

    // Load driver document to fetch name + phone
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: driverId != null
          ? FirebaseFirestore.instance
              .collection('employees')
              .doc(driverId)
              .get()
          : Future.value(null),
      builder: (context, snap) {
        String driverName = 'Unassigned';
        String phone = '';
        if (snap.hasData && snap.data != null && snap.data!.exists) {
          final m = snap.data!.data() ?? {};
          driverName = (m['name'] ??
                  (('${m['firstName'] ?? ''} ${m['lastName'] ?? ''}').trim()))
              .toString();
          phone = (m['mobilePhone'] ?? m['workPhone'] ?? '').toString();
        }

        final truckLabel = (truckId == null || truckId!.isEmpty)
            ? 'No truck'
            : 'Truck: $truckId';
        return Row(
          children: [
            Expanded(
              child: Text('Driver: $driverName • $truckLabel',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (phone.isNotEmpty) ...[
              IconButton(
                tooltip: 'Call driver',
                icon: const Icon(Icons.call),
                onPressed: () => _callNumber(context, phone),
              ),
              IconButton(
                tooltip: 'Text driver',
                icon: const Icon(Icons.sms_outlined),
                onPressed: () => _sendSms(context, phone),
              ),
            ],
          ],
        );
      },
    );
  }

  // local helpers (simple dial/SMS using url_launcher)
  String _digitsOnlyForDial(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'[^0-9+*#]'), '');

  Future<void> _callNumber(BuildContext context, String? raw) async {
    final s = _digitsOnlyForDial(raw);
    if (s.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: s);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _sendSms(BuildContext context, String? raw,
      {String? body}) async {
    final s = _digitsOnlyForDial(raw);
    if (s.isEmpty) return;
    final smsUri = Uri(
      scheme: 'sms',
      path: s,
      queryParameters: {
        if ((body ?? '').trim().isNotEmpty) 'body': body!.trim()
      },
    );
    var ok = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
    if (!ok) {
      final alt = Uri(scheme: 'smsto', path: s);
      await launchUrl(alt, mode: LaunchMode.externalApplication);
    }
  }
}
