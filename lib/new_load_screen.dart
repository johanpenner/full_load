// lib/new_load_screen.dart
// Clean, easy-to-use builder for NEW LOADS with:
// - Client selector (left)
// - Multiple Shippers / pickups (middle)
//   * each with PO# / Load# / Project# and pickup window
//   * each with multiple Receivers (drops)
// - Receivers library (right) to quickly attach drops to the active pickup
// - Saves to Firestore collection `loads` as a structured document
// - Uses DEV mode to allow saving for any signed-in user

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NewLoadScreen extends StatefulWidget {
  const NewLoadScreen({super.key});

  @override
  State<NewLoadScreen> createState() => _NewLoadScreenState();
}

class _NewLoadScreenState extends State<NewLoadScreen> {
  static const bool kDevAllowAllWrites = true; // gate for prod later

  // ==== Cached reference data ====
  List<_ClientOpt> _clients = [];
  List<_PartyOpt> _shippers = [];
  List<_PartyOpt> _receivers = [];
  bool _loadingRefs = true;
  String? _loadError;

  // ==== Form state ====
  String? _clientId;
  int _activePickupIndex = 0; // which pickup gets drops from the right column

  final List<_Pickup> _pickups = [
    _Pickup(),
  ];

  // Top-level fields
  final TextEditingController _refCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchReferenceData();
  }

  Future<void> _fetchReferenceData() async {
    setState(() { _loadingRefs = true; _loadError = null; });
    try {
      final clientsSnap = await FirebaseFirestore.instance
          .collection('clients')
          .orderBy('name')
          .get();
      final shippersSnap = await FirebaseFirestore.instance
          .collection('shippers')
          .orderBy('name')
          .get();
      final receiversSnap = await FirebaseFirestore.instance
          .collection('receivers')
          .orderBy('name')
          .get();

      _clients = clientsSnap.docs
          .map((d) => _ClientOpt(id: d.id, name: (d.data()['name'] ?? '') as String))
          .toList();

      _shippers = shippersSnap.docs
          .map((d) => _PartyOpt(
                id: d.id,
                name: (d.data()['name'] ?? '') as String,
                locations: List<Map<String, dynamic>>.from(d.data()['locations'] ?? []),
              ))
          .toList();

      _receivers = receiversSnap.docs
          .map((d) => _PartyOpt(
                id: d.id,
                name: (d.data()['name'] ?? '') as String,
                locations: List<Map<String, dynamic>>.from(d.data()['locations'] ?? []),
              ))
          .toList();

      if (_clients.isNotEmpty && _clientId == null) {
        _clientId = _clients.first.id;
      }

      setState(() { _loadingRefs = false; });
    } catch (e) {
      setState(() { _loadError = 'Failed to load reference data: $e'; _loadingRefs = false; });
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ===== Helpers =====
  String _oneLine(String s) => s.replaceAll('\n', ', ').replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<DateTime?> _pickDateTime({required DateTime initial}) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (date == null) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  // ===== Build =====
  @override
  Widget build(BuildContext context) {
    if (_loadingRefs) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(onPressed: _fetchReferenceData, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('New Load')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTopMetaRow(),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Client selector
                  Expanded(child: _buildClientCard()),

                  const SizedBox(width: 12),

                  // Middle: Pickups (Shippers)
                  Expanded(flex: 2, child: _buildPickupsColumn()),

                  const SizedBox(width: 12),

                  // Right: Receivers library
                  Expanded(child: _buildReceiversLibrary()),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saveLoad,
                icon: const Icon(Icons.save),
                label: const Text('Save Load'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopMetaRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _refCtrl,
            decoration: const InputDecoration(
              labelText: 'Reference (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClientCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.business, size: 20),
                const SizedBox(width: 8),
                const Text('Client', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _clientId,
              items: _clients
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name.isEmpty ? '(unnamed)' : c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _clientId = v),
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Select client'),
            ),
            const Spacer(),
            const Text('Tip: add new clients in the Clients tab.', style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildPickupsColumn() {
    return Column(
      children: [
        Row(
          children: [
            const Text('Pickups (Shippers)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => setState(() => _pickups.add(_Pickup())),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add Pickup'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: _pickups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _pickupCard(i),
          ),
        ),
      ],
    );
  }

  Widget _pickupCard(int index) {
    final p = _pickups[index];
    final shipperItems = _shippers
        .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name.isEmpty ? '(unnamed)' : s.name)))
        .toList();

    final selectedShipper = _shippers.firstWhere(
      (s) => s.id == p.shipperId,
      orElse: () => _PartyOpt(id: '', name: '', locations: const []),
    );

    return Card(
      elevation: index == _activePickupIndex ? 2 : 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: index == _activePickupIndex ? Theme.of(context).colorScheme.primary : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Radio<int>(
                  value: index,
                  groupValue: _activePickupIndex,
                  onChanged: (v) => setState(() => _activePickupIndex = v ?? 0),
                ),
                const SizedBox(width: 4),
                const Text('Active for adding receivers'),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove pickup',
                  onPressed: _pickups.length == 1
                      ? null
                      : () => setState(() => _pickups.removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: p.shipperId,
                    items: shipperItems,
                    onChanged: (v) => setState(() {
                      p.shipperId = v;
                      p.shipperLocationIndex = null; // reset location when shipper changes
                    }),
                    decoration: const InputDecoration(labelText: 'Shipper', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: p.shipperLocationIndex,
                    items: [
                      for (int i = 0; i < selectedShipper.locations.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(_locLabel(selectedShipper.locations[i])),
                        )
                    ],
                    onChanged: (v) => setState(() => p.shipperLocationIndex = v),
                    decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: p.poCtrl, decoration: const InputDecoration(labelText: 'PO#', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: p.loadCtrl, decoration: const InputDecoration(labelText: 'Load#', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: p.projectCtrl, decoration: const InputDecoration(labelText: 'Project#', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final dt = await _pickDateTime(initial: p.pickupStart ?? DateTime.now());
                      if (dt != null) setState(() => p.pickupStart = dt);
                    },
                    icon: const Icon(Icons.schedule),
                    label: Text(p.pickupStart == null
                        ? 'Pickup start time'
                        : 'Pickup start: ${p.pickupStart}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final dt = await _pickDateTime(initial: p.pickupEnd ?? (p.pickupStart ?? DateTime.now()));
                      if (dt != null) setState(() => p.pickupEnd = dt);
                    },
                    icon: const Icon(Icons.schedule),
                    label: Text(p.pickupEnd == null
                        ? 'Pickup end time'
                        : 'Pickup end: ${p.pickupEnd}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            Row(
              children: [
                const Text('Receivers for this pickup', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _addReceiverViaDialog(index),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add Receiver'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (p.drops.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No receivers added yet.'),
              )
            else
              Column(
                children: [
                  for (int j = 0; j < p.drops.length; j++) _dropTile(index, j, p.drops[j])
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _dropTile(int pickupIndex, int dropIndex, _Drop d) {
    final rec = _receivers.firstWhere((r) => r.id == d.receiverId, orElse: () => _PartyOpt(id: '', name: '', locations: const []));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.local_shipping_outlined),
      title: Text(rec.name.isEmpty ? '(select receiver)' : rec.name),
      subtitle: Text(d.receiverLocationIndex == null
          ? 'No location selected'
          : _locLabel(rec.locations[d.receiverLocationIndex!])),
      trailing: Wrap(spacing: 8, children: [
        IconButton(
          tooltip: 'Time window',
          icon: const Icon(Icons.schedule),
          onPressed: () async {
            final start = await _pickDateTime(initial: d.deliveryStart ?? DateTime.now());
            if (start != null) setState(() => d.deliveryStart = start);
            final end = await _pickDateTime(initial: d.deliveryEnd ?? (d.deliveryStart ?? DateTime.now()));
            if (end != null) setState(() => d.deliveryEnd = end);
          },
        ),
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit),
          onPressed: () => _editReceiverOnPickup(pickupIndex, dropIndex),
        ),
        IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() => _pickups[pickupIndex].drops.removeAt(dropIndex)),
        ),
      ]),
    );
  }

  Widget _buildReceiversLibrary() {
    final searchCtrl = TextEditingController();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.store_mall_directory_outlined, size: 20),
              SizedBox(width: 8),
              Text('Receivers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search receiver', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _receivers.length,
                itemBuilder: (_, i) {
                  final r = _receivers[i];
                  final q = searchCtrl.text.trim().toLowerCase();
                  if (q.isNotEmpty && !r.name.toLowerCase().contains(q)) return const SizedBox.shrink();
                  return ListTile(
                    title: Text(r.name.isEmpty ? '(unnamed)' : r.name),
                    subtitle: Text(r.locations.isEmpty ? 'No locations' : _locLabel(r.locations.first)),
                    trailing: FilledButton.tonalIcon(
                      onPressed: () => _attachReceiverFromLibrary(r),
                      icon: const Icon(Icons.add),
                      label: const Text('Add to active'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _locLabel(Map<String, dynamic> loc) {
    final name = (loc['locationName'] ?? '') as String;
    final addr = (loc['address'] ?? '') as String;
    final type = (loc['type'] ?? '') as String;
    final base = name.isNotEmpty ? name : (addr.isNotEmpty ? _oneLine(addr) : 'Location');
    return type.isEmpty ? base : '$base ($type)';
  }

  Future<void> _attachReceiverFromLibrary(_PartyOpt r) async {
    final p = _pickups[_activePickupIndex];

    int? locIndex;
    DateTime? start;
    DateTime? end;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${r.name} to Pickup ${_activePickupIndex + 1}')
            ,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: locIndex,
                items: [for (int i = 0; i < r.locations.length; i++) DropdownMenuItem(value: i, child: Text(_locLabel(r.locations[i])))],
                onChanged: (v) => locIndex = v,
                decoration: const InputDecoration(labelText: 'Receiver Location', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  start = await _pickDateTime(initial: DateTime.now());
                  setState(() {});
                },
                icon: const Icon(Icons.schedule),
                label: Text(start == null ? 'Delivery start' : 'Start: $start'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  end = await _pickDateTime(initial: start ?? DateTime.now());
                  setState(() {});
                },
                icon: const Icon(Icons.schedule),
                label: Text(end == null ? 'Delivery end' : 'End: $end'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (locIndex == null) return; // require location
              Navigator.of(ctx).pop(true);
              setState(() {
                p.drops.add(_Drop(receiverId: r.id, receiverLocationIndex: locIndex, deliveryStart: start, deliveryEnd: end));
              });
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addReceiverViaDialog(int pickupIndex) async {
    _PartyOpt? selected;
    int? locIndex;
    DateTime? start;
    DateTime? end;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Add Receiver to Pickup ${pickupIndex + 1}'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<_PartyOpt>(
                  value: selected,
                  items: _receivers.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
                  onChanged: (v) => setLocal(() { selected = v; locIndex = null; }),
                  decoration: const InputDecoration(labelText: 'Receiver', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: locIndex,
                  items: [
                    if (selected != null)
                      for (int i = 0; i < selected!.locations.length; i++)
                        DropdownMenuItem(value: i, child: Text(_locLabel(selected!.locations[i])))
                  ],
                  onChanged: (v) => setLocal(() => locIndex = v),
                  decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    start = await _pickDateTime(initial: DateTime.now());
                    setLocal(() {});
                  },
                  icon: const Icon(Icons.schedule),
                  label: Text(start == null ? 'Delivery start' : 'Start: $start'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    end = await _pickDateTime(initial: start ?? DateTime.now());
                    setLocal(() {});
                  },
                  icon: const Icon(Icons.schedule),
                  label: Text(end == null ? 'Delivery end' : 'End: $end'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (selected == null || locIndex == null) return;
                Navigator.of(ctx).pop(true);
                setState(() {
                  _pickups[pickupIndex].drops.add(
                    _Drop(receiverId: selected!.id, receiverLocationIndex: locIndex, deliveryStart: start, deliveryEnd: end),
                  );
                });
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editReceiverOnPickup(int pickupIndex, int dropIndex) async {
    final drop = _pickups[pickupIndex].drops[dropIndex];
    _PartyOpt? selected = _receivers.firstWhere((r) => r.id == drop.receiverId, orElse: () => _PartyOpt(id: '', name: '', locations: const []));
    int? locIndex = drop.receiverLocationIndex;
    DateTime? start = drop.deliveryStart;
    DateTime? end = drop.deliveryEnd;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Edit Receiver (Pickup ${pickupIndex + 1})'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<_PartyOpt>(
                  value: selected.id.isEmpty ? null : selected,
                  items: _receivers.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
                  onChanged: (v) => setLocal(() { selected = v; locIndex = null; }),
                  decoration: const InputDecoration(labelText: 'Receiver', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: locIndex,
                  items: [
                    if (selected.id.isNotEmpty)
                      for (int i = 0; i < selected.locations.length; i++)
                        DropdownMenuItem(value: i, child: Text(_locLabel(selected.locations[i])))
                  ],
                  onChanged: (v) => setLocal(() => locIndex = v),
                  decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async { start = await _pickDateTime(initial: start ?? DateTime.now()); setLocal(() {}); },
                  icon: const Icon(Icons.schedule),
                  label: Text(start == null ? 'Delivery start' : 'Start: $start'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async { end = await _pickDateTime(initial: end ?? (start ?? DateTime.now())); setLocal(() {}); },
                  icon: const Icon(Icons.schedule),
                  label: Text(end == null ? 'Delivery end' : 'End: $end'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (selected.id.isEmpty || locIndex == null) return;
                Navigator.of(ctx).pop(true);
                setState(() {
                  drop
                    ..receiverId = selected!.id
                    ..receiverLocationIndex = locIndex
                    ..deliveryStart = start
                    ..deliveryEnd = end;
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Save =====
  Future<void> _saveLoad() async {
    // Basic validation
    final client = _clients.firstWhere((c) => c.id == _clientId, orElse: () => _ClientOpt(id: '', name: ''));
    if (client.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a client.')));
      return;
    }
    if (_pickups.any((p) => p.shipperId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a shipper for each pickup.')));
      return;
    }
    if (_pickups.any((p) => p.shipperLocationIndex == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a location for each pickup.')));
      return;
    }
    if (_pickups.any((p) => p.drops.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Each pickup must have at least one receiver.')));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    final shipments = _pickups.map((p) {
      final shipper = _shippers.firstWhere((s) => s.id == p.shipperId);
      final loc = shipper.locations[p.shipperLocationIndex!];
      return {
        'shipper': {
          'id': shipper.id,
          'name': shipper.name,
          'locationIndex': p.shipperLocationIndex,
          'location': loc,
        },
        'poNumber': p.poCtrl.text.trim(),
        'loadNumber': p.loadCtrl.text.trim(),
        'projectNumber': p.projectCtrl.text.trim(),
        'pickupWindow': {
          'start': p.pickupStart == null ? null : Timestamp.fromDate(p.pickupStart!),
          'end': p.pickupEnd == null ? null : Timestamp.fromDate(p.pickupEnd!),
        },
        'drops': p.drops.map((d) {
          final recv = _receivers.firstWhere((r) => r.id == d.receiverId);
          final rloc = recv.locations[d.receiverLocationIndex!];
          return {
            'receiver': {
              'id': recv.id,
              'name': recv.name,
              'locationIndex': d.receiverLocationIndex,
              'location': rloc,
            },
            'deliveryWindow': {
              'start': d.deliveryStart == null ? null : Timestamp.fromDate(d.deliveryStart!),
              'end': d.deliveryEnd == null ? null : Timestamp.fromDate(d.deliveryEnd!),
            }
          };
        }).toList(),
      };
    }).toList();

    final payload = {
      'ref': _refCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
      'clientId': client.id,
      'clientName': client.name,
      'status': 'open',
      'shipments': shipments,
      'totals': {
        'numPickups': _pickups.length,
        'numDrops': _pickups.fold<int>(0, (sum, p) => sum + p.drops.length),
      },
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': user?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': user?.uid,
    };

    try {
      await FirebaseFirestore.instance.collection('loads').add(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Load created.')));
      // Reset form
      setState(() {
        _refCtrl.clear();
        _notesCtrl.clear();
        _pickups
          ..clear()
          ..add(_Pickup());
        _activePickupIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }
}

// ===== models for form state =====
class _Pickup {
  String? shipperId;
  int? shipperLocationIndex;
  final TextEditingController poCtrl = TextEditingController();
  final TextEditingController loadCtrl = TextEditingController();
  final TextEditingController projectCtrl = TextEditingController();
  DateTime? pickupStart;
  DateTime? pickupEnd;
  final List<_Drop> drops = [];
}

class _Drop {
  _Drop({this.receiverId, this.receiverLocationIndex, this.deliveryStart, this.deliveryEnd});
  String? receiverId;
  int? receiverLocationIndex;
  DateTime? deliveryStart;
  DateTime? deliveryEnd;
}

class _ClientOpt {
  final String id; final String name;
  _ClientOpt({required this.id, required this.name});
}

class _PartyOpt {
  final String id; final String name; final List<Map<String, dynamic>> locations;
  const _PartyOpt({required this.id, required this.name, required this.locations});
}
