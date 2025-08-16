import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NewLoadScreen extends StatefulWidget {
  const NewLoadScreen({super.key});
  @override
  State<NewLoadScreen> createState() => _NewLoadScreenState();
}

  // Dev: UI always enabled; server-side Firestore rules still apply
  static const bool kDevAllowAllWrites = true;

  // -------- Reference data --------
  List<_ClientOpt> _clients = [];
  List<_PartyOpt> _shippers = [];
  List<_PartyOpt> _receivers = [];
  bool _loadingRefs = true;
  String? _loadError;

  // -------- Form state --------
  String? _clientId;
  final List<_Pickup> _pickups = [_Pickup()];

  // Page meta
  final TextEditingController _refCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchReferenceData();
  }

  Future<void> _fetchReferenceData() async {
    setState(() {
      _loadingRefs = true;
      _loadError = null;
    });
    try {
      final clientsSnap =
          await FirebaseFirestore.instance.collection('clients').orderBy('name').get();
      final shippersSnap =
          await FirebaseFirestore.instance.collection('shippers').orderBy('name').get();
      final receiversSnap =
          await FirebaseFirestore.instance.collection('receivers').orderBy('name').get();

      _clients = [
        for (final d in clientsSnap.docs)
          _ClientOpt(id: d.id, name: (d.data()['name'] ?? '') as String),
      ];

      _shippers = [
        for (final d in shippersSnap.docs)
          _PartyOpt(
            id: d.id,
            name: (d.data()['name'] ?? '') as String,
            mainAddress:
                (d.data()['mainAddress'] ?? d.data()['address'] ?? '') as String,
            locations: List<Map<String, dynamic>>.from(d.data()['locations'] ?? []),
          ),
      ];

      _receivers = [
        for (final d in receiversSnap.docs)
          _PartyOpt(
            id: d.id,
            name: (d.data()['name'] ?? '') as String,
            mainAddress:
                (d.data()['mainAddress'] ?? d.data()['address'] ?? '') as String,
            locations: List<Map<String, dynamic>>.from(d.data()['locations'] ?? []),
          ),
      ];

      _clientId ??= _clients.isNotEmpty ? _clients.first.id : null;

      setState(() => _loadingRefs = false);
    } catch (e) {
      setState(() {
        _loadError = 'Failed to load reference data: $e';
        _loadingRefs = false;
      });
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // -------- Helpers --------

  // Short, readable label for a location map
  String _locLabel(Map<String, dynamic> loc) {
    final name = (loc['locationName'] ?? '') as String;
    final addr = (loc['address'] ?? '') as String;
    final type = (loc['type'] ?? '') as String;
    final base = name.isNotEmpty ? name : (addr.isNotEmpty ? _oneLine(addr) : 'Location');
    return type.isEmpty ? base : '$base ($type)';
  }

  // One-line text (collapse whitespace/newlines)
  String _oneLine(String s) =>
      s.replaceAll('\n', ', ').replaceAll(RegExp(r'\s+'), ' ').trim();

  // Build a “main address” location object
  Map<String, dynamic> _mainLoc(String addr, String type) => {
        'locationName': 'Main address',
        'address': addr,
        'type': type,
      };

  // Date+time picker -> DateTime
  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial ?? now,
    );
    if (date == null) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  // Reference data
  List<_ClientOpt> _clients = [];
  List<_PartyOpt> _shippers = [];
  List<_PartyOpt> _receivers = [];
  bool _loadingRefs = true;
  String? _loadError;

  // Form state
  String? _clientId;
  final List<_Pickup> _pickups = [_Pickup()];

  // Page meta
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchReferenceData();
  }

  Future<void> _fetchReferenceData() async {
    setState(() {
      _loadingRefs = true;
      _loadError = null;
    });
    try {
      final clients = await FirebaseFirestore.instance
          .collection('clients')
          .orderBy('name')
          .get();
      final shippers = await FirebaseFirestore.instance
          .collection('shippers')
          .orderBy('name')
          .get();
      final receivers = await FirebaseFirestore.instance
          .collection('receivers')
          .orderBy('name')
          .get();

      _clients = [
        for (final d in clients.docs)
          _ClientOpt(id: d.id, name: (d.data()['name'] ?? '') as String)
      ];
      _shippers = [
        for (final d in shippers.docs)
          _PartyOpt(
            id: d.id,
            name: (d.data()['name'] ?? '') as String,
            mainAddress: (d.data()['mainAddress'] ?? d.data()['address'] ?? '')
                as String,
            locations:
                List<Map<String, dynamic>>.from(d.data()['locations'] ?? []),
          )
      ];
      _receivers = [
        for (final d in receivers.docs)
          _PartyOpt(
            id: d.id,
            name: (d.data()['name'] ?? '') as String,
            mainAddress: (d.data()['mainAddress'] ?? d.data()['address'] ?? '')
                as String,
            locations:
                List<Map<String, dynamic>>.from(d.data()['locations'] ?? []),
          )
      ];

      _clientId ??= _clients.isNotEmpty ? _clients.first.id : null;
      setState(() => _loadingRefs = false);
    } catch (e) {
      setState(() {
        _loadError = 'Failed to load reference data: $e';
        _loadingRefs = false;
      });
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // Helpers
  String _oneLine(String s) =>
      s.replaceAll('\n', ', ').replaceAll(RegExp(r'\s+'), ' ').trim();
  Map<String, dynamic> _mainLoc(String addr, String type) => {
        'locationName': 'Main address',
        'address': addr,
        'type': type,
      };

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDate: initial ?? now);
    if (d == null) return null;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial ?? now));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRefs)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
                onPressed: _fetchReferenceData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry')),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('New Load')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Meta row
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _refCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Reference (optional)',
                          border: OutlineInputBorder()))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 12),
            // Two-column layout: left client, right pickups/deliveries
            Expanded(
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 360,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: const [
                              Icon(Icons.business, size: 20),
                              SizedBox(width: 8),
                              Text('Client',
                                  style: TextStyle(fontWeight: FontWeight.w600))
                            ]),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _clientId,
                              items: _clients
                                  .map((c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name.isEmpty
                                          ? '(unnamed)'
                                          : c.name)))
                                  .toList(),
                              onChanged: (v) => setState(() => _clientId = v),
                              decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'Select client'),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                                'Tip: add new clients in the Clients tab.',
                                style: TextStyle(color: Colors.black54)),
                          ]),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Right side: Pickups & Deliveries
                Expanded(child: _pickupsPane()),
              ]),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                  onPressed: _saveLoad,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Load')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickupsPane() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Pickups & Deliveries',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            OutlinedButton.icon(
                onPressed: () => setState(() => _pickups.add(_Pickup())),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add Pickup')),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: _pickups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _pickupCard(i),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pickupCard(int idx) {
    final p = _pickups[idx];

    _PartyOpt shipper = _shippers.firstWhere((s) => s.id == p.shipperId,
        orElse: () => _PartyOpt.empty());
    List<DropdownMenuItem<int>> shipperLocItems() {
      final items = <DropdownMenuItem<int>>[];
      for (int i = 0; i < shipper.locations.length; i++) {
        items.add(DropdownMenuItem(
            value: i, child: Text(_locLabel(shipper.locations[i]))));
      }
      if (shipper.locations.isEmpty && shipper.mainAddress.isNotEmpty) {
        items.add(
            const DropdownMenuItem(value: -1, child: Text('Main address')));
      }
      return items;
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // SHIPPER ROW
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: p.shipperId,
                items: _shippers
                    .map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.name.isEmpty ? '(unnamed)' : s.name)))
                    .toList(),
                onChanged: (v) => setState(() {
                  p.shipperId = v;
                  p.shipperLocIdx = null;
                  shipper = _shippers.firstWhere((s) => s.id == v,
                      orElse: () => _PartyOpt.empty());
                }),
                decoration: const InputDecoration(
                    labelText: 'Shipper', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                value: p.shipperLocIdx,
                items: shipperLocItems(),
                onChanged: (v) => setState(() => p.shipperLocIdx = v),
                decoration: const InputDecoration(
                    labelText: 'Location', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final dt = await _pickDateTime(p.pickupAt);
                  if (dt != null) setState(() => p.pickupAt = dt);
                },
                icon: const Icon(Icons.schedule),
                label: Text(p.pickupAt == null
                    ? 'Pickup time'
                    : 'Pickup: ${p.pickupAt}'),
              ),
            ),
            IconButton(
              tooltip: 'Remove pickup',
              onPressed: _pickups.length == 1
                  ? null
                  : () => setState(() => _pickups.removeAt(idx)),
              icon: const Icon(Icons.delete_outline),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: p.po,
                    decoration: const InputDecoration(
                        labelText: 'PO#', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: p.load,
                    decoration: const InputDecoration(
                        labelText: 'Load#', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: p.project,
                    decoration: const InputDecoration(
                        labelText: 'Project#', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 10),
          const Divider(),
          Row(children: [
            const Text('Deliveries (Receivers)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            OutlinedButton.icon(
                onPressed: () => _addDeliveryDialog(idx),
                icon: const Icon(Icons.add),
                label: const Text('Add Delivery')),
          ]),
          const SizedBox(height: 6),
          if (p.drops.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No deliveries added yet.'))
          else
            Column(children: [
              for (int j = 0; j < p.drops.length; j++)
                _deliveryRow(idx, j, p.drops[j])
            ]),
        ]),
      ),
    );
  }

  Widget _deliveryRow(int pickupIdx, int dropIdx, _Drop d) {
    final recv = _receivers.firstWhere((r) => r.id == d.receiverId,
        orElse: () => _PartyOpt.empty());
    List<DropdownMenuItem<int>> receiverLocItems() {
      final items = <DropdownMenuItem<int>>[];
      for (int i = 0; i < recv.locations.length; i++) {
        items.add(DropdownMenuItem(
            value: i, child: Text(_locLabel(recv.locations[i]))));
      }
      if (recv.locations.isEmpty && recv.mainAddress.isNotEmpty) {
        items.add(
            const DropdownMenuItem(value: -1, child: Text('Main address')));
      }
      return items;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: d.receiverId,
            items: _receivers
                .map((r) => DropdownMenuItem(
                    value: r.id,
                    child: Text(r.name.isEmpty ? '(unnamed)' : r.name)))
                .toList(),
            onChanged: (v) => setState(() {
              d.receiverId = v;
              d.receiverLocIdx = null;
            }),
            decoration: const InputDecoration(
                labelText: 'Receiver', border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            value: d.receiverLocIdx,
            items: receiverLocItems(),
            onChanged: (v) => setState(() => d.receiverLocIdx = v),
            decoration: const InputDecoration(
                labelText: 'Location', border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final dt = await _pickDateTime(d.deliveryAt);
              if (dt != null) setState(() => d.deliveryAt = dt);
            },
            icon: const Icon(Icons.event_available),
            label: Text(d.deliveryAt == null
                ? 'Delivery time'
                : 'Delivery: ${d.deliveryAt}'),
          ),
        ),
        IconButton(
          tooltip: 'Remove',
          onPressed: () =>
              setState(() => _pickups[pickupIdx].drops.removeAt(dropIdx)),
          icon: const Icon(Icons.delete_outline),
        ),
      ]),
    );
  }

  Future<void> _addDeliveryDialog(int pickupIdx) async {
    final p = _pickups[pickupIdx];
    String? chosenId;
    int? locIdx;
    DateTime? at;
    final search = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final q = search.text.trim().toLowerCase();
        final list = q.isEmpty
            ? _receivers
            : _receivers
                .where((r) => r.name.toLowerCase().contains(q))
                .toList();
        return AlertDialog(
          title: const Text('Add Delivery'),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: search,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search receiver',
                      border: OutlineInputBorder())),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final r = list[i];
                    return RadioListTile<String>(
                      value: r.id,
                      groupValue: chosenId,
                      onChanged: (v) => setLocal(() {
                        chosenId = v;
                        locIdx = null;
                      }),
                      title: Text(r.name.isEmpty ? '(unnamed)' : r.name),
                      subtitle: Text(r.mainAddress.isEmpty
                          ? 'No main address'
                          : _oneLine(r.mainAddress)),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (chosenId != null)
                DropdownButtonFormField<int>(
                  value: locIdx,
                  items: () {
                    final r = _receivers.firstWhere((x) => x.id == chosenId,
                        orElse: () => _PartyOpt.empty());
                    final items = <DropdownMenuItem<int>>[];
                    for (int i = 0; i < r.locations.length; i++) {
                      items.add(DropdownMenuItem(
                          value: i, child: Text(_locLabel(r.locations[i]))));
                    }
                    if (r.locations.isEmpty && r.mainAddress.isNotEmpty) {
                      items.add(const DropdownMenuItem(
                          value: -1, child: Text('Main address')));
                    }
                    return items;
                  }(),
                  onChanged: (v) => setLocal(() => locIdx = v),
                  decoration: const InputDecoration(
                      labelText: 'Location', border: OutlineInputBorder()),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  at = await _pickDateTime(at);
                  setLocal(() {});
                },
                icon: const Icon(Icons.event_available),
                label: Text(at == null ? 'Delivery time' : 'Delivery: $at'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (chosenId == null) return;
                Navigator.of(ctx).pop(true);
                setState(() {
                  p.drops.add(_Drop(
                      receiverId: chosenId,
                      receiverLocIdx: locIdx,
                      deliveryAt: at));
                });
              },
              child: const Text('Add'),
            ),
          ],
        );
      }),
    );
    search.dispose();
  }

  Future<void> _saveLoad() async {
    final client = _clients.firstWhere((c) => c.id == _clientId,
        orElse: () => _ClientOpt(id: '', name: ''));
    if (client.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a client.')));
      return;
    }
    if (_pickups.any((p) => p.shipperId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick a shipper for each pickup.')));
      return;
    }
    if (_pickups.any((p) => p.pickupAt == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Set a pickup time for each pickup.')));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final shipments = _pickups.map((p) {
      final shipper = _shippers.firstWhere((s) => s.id == p.shipperId,
          orElse: () => _PartyOpt.empty());
      final shipLoc = (p.shipperLocIdx == null || shipper.locations.isEmpty)
          ? _mainLoc(shipper.mainAddress, 'pickup')
          : (p.shipperLocIdx == -1
              ? _mainLoc(shipper.mainAddress, 'pickup')
              : shipper.locations[p.shipperLocIdx!]);

      return {
        'shipper': {
          'id': shipper.id,
          'name': shipper.name,
          'locationIndex': p.shipperLocIdx,
          'location': shipLoc
        },
        'poNumber': p.po.text.trim(),
        'loadNumber': p.load.text.trim(),
        'projectNumber': p.project.text.trim(),
        'pickupAt': Timestamp.fromDate(p.pickupAt!),
        'drops': p.drops.map((d) {
          final recv = _receivers.firstWhere((r) => r.id == d.receiverId,
              orElse: () => _PartyOpt.empty());
          final recLoc = (d.receiverLocIdx == null || recv.locations.isEmpty)
              ? _mainLoc(recv.mainAddress, 'delivery')
              : (d.receiverLocIdx == -1
                  ? _mainLoc(recv.mainAddress, 'delivery')
                  : recv.locations[d.receiverLocIdx!]);
          return {
            'receiver': {
              'id': recv.id,
              'name': recv.name,
              'locationIndex': d.receiverLocIdx,
              'location': recLoc
            },
            'deliveryAt':
                d.deliveryAt == null ? null : Timestamp.fromDate(d.deliveryAt!),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Load created.')));
      setState(() {
        _refCtrl.clear();
        _notesCtrl.clear();
        _pickups
          ..clear()
          ..add(_Pickup());
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }
}

// Models
class _Pickup {
  String? shipperId;
  int? shipperLocIdx; // -1 = main address
  final po = TextEditingController();
  final load = TextEditingController();
  final project = TextEditingController();
  DateTime? pickupAt;
  final List<_Drop> drops = [];
}

class _Drop {
  _Drop({this.receiverId, this.receiverLocIdx, this.deliveryAt});
  String? receiverId;
  int? receiverLocIdx; // -1 = main address
  DateTime? deliveryAt; // single datetime
}

class _ClientOpt {
  final String id;
  final String name;
  _ClientOpt({required this.id, required this.name});
}

class _PartyOpt {
  final String id;
  final String name;
  final String mainAddress;
  final List<Map<String, dynamic>> locations;
  const _PartyOpt(
      {required this.id,
      required this.name,
      required this.mainAddress,
      required this.locations});
  factory _PartyOpt.empty() =>
      const _PartyOpt(id: '', name: '', mainAddress: '', locations: []);
}
