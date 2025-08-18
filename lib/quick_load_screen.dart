import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// TODO: Replace with your actual Google Maps Distance Matrix API key.
/// Make sure Distance Matrix API is enabled in your project.
const String kGoogleMapsApiKey = 'PASTE_YOUR_REAL_KEY_HERE';

/// A compact, one-page "Quick Load" creator.
/// - Pick/enter Client, Shipper, Receiver, their addresses
/// - Choose Truck and Start Location source (Live Truck / Last Delivery / Yard / Custom)
/// - Calculate distances (Truck→Pickup, Pickup→Delivery)
/// - Save to Firestore and pop back
class QuickLoadScreen extends StatefulWidget {
  const QuickLoadScreen({super.key});

  @override
  State<QuickLoadScreen> createState() => _QuickLoadScreenState();
}

class _QuickLoadScreenState extends State<QuickLoadScreen> {
  // Text controllers
  final _clientCtrl = TextEditingController();
  final _shipperCtrl = TextEditingController();
  final _shipperAddrCtrl = TextEditingController();
  final _receiverCtrl = TextEditingController();
  final _receiverAddrCtrl = TextEditingController();
  final _customStartCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Truck selection
  String? _selectedTruckId;
  String? _selectedTruckName;

  // Units toggle
  bool _useMetric = true; // true = km, false = miles

  // Start location mode
  StartOrigin _startOrigin = StartOrigin.liveTruck;

  // Derived distances
  DistanceResult? _truckToPickup;
  DistanceResult? _pickupToDelivery;

  bool _saving = false;
  bool _calculating = false;

  @override
  void dispose() {
    _clientCtrl.dispose();
    _shipperCtrl.dispose();
    _shipperAddrCtrl.dispose();
    _receiverCtrl.dispose();
    _receiverAddrCtrl.dispose();
    _customStartCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Load')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _linePicker(
                label: 'Client',
                controller: _clientCtrl,
                onPick: () => _pickFromCollection('clients', (doc) {
                  _clientCtrl.text = (doc.data()['name'] ?? '').toString();
                }),
                trailing: IconButton(
                  icon: const Icon(Icons.phone),
                  tooltip: 'Call (tap number after save in client screen)',
                  onPressed:
                      null, // kept placeholder - future client card tap-to-call
                ),
              ),
              const SizedBox(height: 8),
              _linePicker(
                label: 'Shipper (Company)',
                controller: _shipperCtrl,
                onPick: () => _pickFromCollection('shippers', (doc) {
                  _shipperCtrl.text = (doc.data()['name'] ?? '').toString();
                }),
              ),
              const SizedBox(height: 8),
              _linePicker(
                label: 'Pickup Address (Shipper Location)',
                controller: _shipperAddrCtrl,
                onPick: () => _pickAddressFromSaved(
                    'shippers', _shipperCtrl.text, (addr) {
                  _shipperAddrCtrl.text = addr;
                }),
                keyboardType: TextInputType.streetAddress,
              ),
              const SizedBox(height: 8),
              _linePicker(
                label: 'Receiver (Company)',
                controller: _receiverCtrl,
                onPick: () => _pickFromCollection('receivers', (doc) {
                  _receiverCtrl.text = (doc.data()['name'] ?? '').toString();
                }),
              ),
              const SizedBox(height: 8),
              _linePicker(
                label: 'Delivery Address (Receiver Location)',
                controller: _receiverAddrCtrl,
                onPick: () => _pickAddressFromSaved(
                    'receivers', _receiverCtrl.text, (addr) {
                  _receiverAddrCtrl.text = addr;
                }),
                keyboardType: TextInputType.streetAddress,
              ),
              const SizedBox(height: 12),
              _truckPicker(),
              const SizedBox(height: 12),
              _startOriginPicker(),
              if (_startOrigin == StartOrigin.custom) ...[
                const SizedBox(height: 8),
                _linePicker(
                  label: 'Custom Start Address',
                  controller: _customStartCtrl,
                  keyboardType: TextInputType.streetAddress,
                ),
              ],
              const SizedBox(height: 12),
              _unitToggle(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _calculating ? null : _calculateAll,
                      icon: const Icon(Icons.route),
                      label: Text(_calculating
                          ? 'Calculating…'
                          : 'Calculate Distances'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _distancesView(),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveLoad,
                      icon: const Icon(Icons.save),
                      label: Text(_saving ? 'Saving…' : 'Save Load'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // --- Widgets ---

  Widget _linePicker({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    VoidCallback? onPick,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Select from saved',
          onPressed: onPick,
          icon: const Icon(Icons.list_alt),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 4),
          trailing,
        ],
      ],
    );
  }

  Widget _truckPicker() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future:
          FirebaseFirestore.instance.collection('trucks').orderBy('name').get(),
      builder: (context, snap) {
        final items = <DropdownMenuItem<String>>[];
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final id = d.id;
            final name = d.data()['name']?.toString() ?? 'Truck $id';
            items.add(DropdownMenuItem(value: id, child: Text(name)));
          }
        }
        return InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Truck',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedTruckId,
              hint: const Text('Select truck (optional)'),
              items: items,
              onChanged: (v) {
                setState(() {
                  _selectedTruckId = v;
                  _selectedTruckName =
                      items.firstWhere((e) => e.value == v).child.toString();
                });
              },
            ),
          ),
        );
      },
    );
  }

  Widget _startOriginPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Start Location',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 0,
          children: [
            _originRadio(StartOrigin.liveTruck, 'Live Truck GPS'),
            _originRadio(StartOrigin.lastDelivery, 'Truck’s Last Delivery'),
            _originRadio(StartOrigin.yard, 'Yard'),
            _originRadio(StartOrigin.custom, 'Custom'),
          ],
        ),
      ],
    );
  }

  Widget _originRadio(StartOrigin v, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<StartOrigin>(
          value: v,
          groupValue: _startOrigin,
          onChanged: (nv) => setState(() => _startOrigin = nv ?? _startOrigin),
        ),
        Text(label),
      ],
    );
  }

  Widget _unitToggle() {
    return Row(
      children: [
        const Text('Units:', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        ChoiceChip(
          label: const Text('km'),
          selected: _useMetric,
          onSelected: (_) => setState(() => _useMetric = true),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('mi'),
          selected: !_useMetric,
          onSelected: (_) => setState(() => _useMetric = false),
        ),
      ],
    );
  }

  Widget _distancesView() {
    if (_truckToPickup == null && _pickupToDelivery == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (_truckToPickup != null)
          _distCard('Truck ➜ Pickup', _truckToPickup!),
        if (_pickupToDelivery != null)
          _distCard('Pickup ➜ Delivery', _pickupToDelivery!),
      ],
    );
  }

  Widget _distCard(String title, DistanceResult r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.straighten),
        title: Text(title),
        subtitle: Text('${r.distanceText} • ${r.durationText}'),
      ),
    );
  }

  // --- Selection helpers ---

  Future<void> _pickFromCollection(
    String collection,
    void Function(QueryDocumentSnapshot<Map<String, dynamic>>) onSelect,
  ) async {
    await showDialog(
      context: context,
      builder: (_) =>
          _SelectDocDialog(collection: collection, onSelect: onSelect),
    );
    setState(() {});
  }

  Future<void> _pickAddressFromSaved(
    String collection,
    String parentName,
    void Function(String address) onSelect,
  ) async {
    // If you store addresses as subcollection (e.g., shippers/{id}/locations), adapt this.
    await showDialog(
      context: context,
      builder: (_) => _SelectAddressDialog(
        collection: collection,
        parentName: parentName,
        onSelect: onSelect,
      ),
    );
    setState(() {});
  }

  // --- Calculate ---

  Future<void> _calculateAll() async {
    final pickup = _shipperAddrCtrl.text.trim();
    final delivery = _receiverAddrCtrl.text.trim();

    if (pickup.isEmpty || delivery.isEmpty) {
      _snack('Enter pickup and delivery addresses first.');
      return;
    }

    setState(() => _calculating = true);

    try {
      // Pickup → Delivery
      _pickupToDelivery = await _distanceMatrix(
        origin: pickup,
        destination: delivery,
        unitsMetric: _useMetric,
      );

      // Start → Pickup (choose start origin)
      final origin = await _resolveStartOriginAddress();
      if (origin != null && origin.isNotEmpty) {
        _truckToPickup = await _distanceMatrix(
          origin: origin,
          destination: pickup,
          unitsMetric: _useMetric,
        );
      } else {
        _truckToPickup = null;
      }

      setState(() {});
    } catch (e) {
      _snack('Failed to calculate distances: $e');
    } finally {
      setState(() => _calculating = false);
    }
  }

  Future<String?> _resolveStartOriginAddress() async {
    switch (_startOrigin) {
      case StartOrigin.custom:
        return _customStartCtrl.text.trim();
      case StartOrigin.yard:
        // read settings/app.yardAddress
        final doc = await FirebaseFirestore.instance
            .collection('settings')
            .doc('app')
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          final yardAddr = (data['yardAddress'] ?? '').toString();
          final yardLat = data['yardLat'];
          final yardLng = data['yardLng'];
          if (yardAddr.isNotEmpty) return yardAddr;
          if (yardLat != null && yardLng != null) return '$yardLat,$yardLng';
        }
        return null;

      case StartOrigin.lastDelivery:
        if (_selectedTruckId == null) return null;
        final q = await FirebaseFirestore.instance
            .collection('loads')
            .where('truckId', isEqualTo: _selectedTruckId)
            .where('status', isEqualTo: 'Delivered')
            .orderBy('deliveredAt', descending: true)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          final addr = (d['deliveryAddress'] ?? '').toString();
          final lat = d['deliveryLat'];
          final lng = d['deliveryLng'];
          if (addr.isNotEmpty) return addr;
          if (lat != null && lng != null) return '$lat,$lng';
        }
        return null;

      case StartOrigin.liveTruck:
        if (_selectedTruckId == null) return null;
        // vehicles/{truckId}.live.lat/lng — write this from your ELD integration
        final v = await FirebaseFirestore.instance
            .collection('vehicles')
            .doc(_selectedTruckId)
            .get();
        if (v.exists) {
          final live = v.data()?['live'] as Map<String, dynamic>?;
          final lat = live?['lat'];
          final lng = live?['lng'];
          if (lat != null && lng != null) return '$lat,$lng';
        }
        return null;
    }
  }

  Future<DistanceResult> _distanceMatrix({
    required String origin,
    required String destination,
    required bool unitsMetric,
  }) async {
    if (kGoogleMapsApiKey == 'PASTE_YOUR_REAL_KEY_HERE' ||
        kGoogleMapsApiKey.isEmpty) {
      throw 'Add your Google Maps API key in kGoogleMapsApiKey.';
    }
    final units = unitsMetric ? 'metric' : 'imperial';
    final url =
        'https://maps.googleapis.com/maps/api/distancematrix/json?origins=${Uri.encodeComponent(origin)}&destinations=${Uri.encodeComponent(destination)}&units=$units&key=$kGoogleMapsApiKey';

    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw 'Distance Matrix error HTTP ${res.statusCode}';
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') {
      throw 'Distance Matrix status ${data['status']}';
    }
    final rows = data['rows'] as List<dynamic>;
    if (rows.isEmpty) throw 'No rows in Distance Matrix response';
    final elements =
        (rows.first as Map<String, dynamic>)['elements'] as List<dynamic>;
    if (elements.isEmpty) throw 'No elements in Distance Matrix response';
    final el = elements.first as Map<String, dynamic>;
    if (el['status'] != 'OK') throw 'Element status ${el['status']}';

    final dist = el['distance'] as Map<String, dynamic>;
    final dur = el['duration'] as Map<String, dynamic>;
    return DistanceResult(
      distanceMeters: (dist['value'] as num).toInt(),
      distanceText: dist['text'] as String,
      durationSeconds: (dur['value'] as num).toInt(),
      durationText: dur['text'] as String,
    );
  }

  // --- Save ---

  Future<void> _saveLoad() async {
    final client = _clientCtrl.text.trim();
    final shipper = _shipperCtrl.text.trim();
    final shipperAddr = _shipperAddrCtrl.text.trim();
    final receiver = _receiverCtrl.text.trim();
    final receiverAddr = _receiverAddrCtrl.text.trim();

    if (client.isEmpty ||
        shipper.isEmpty ||
        shipperAddr.isEmpty ||
        receiver.isEmpty ||
        receiverAddr.isEmpty) {
      _snack('Please fill Client, Shipper, Pickup, Receiver, Delivery.');
      return;
    }

    // Calculate if not done yet
    if (_pickupToDelivery == null ||
        (_selectedTruckId != null && _truckToPickup == null)) {
      await _calculateAll();
    }
    setState(() => _saving = true);

    try {
      final loads = FirebaseFirestore.instance.collection('loads');
      final now = DateTime.now();

      final docData = {
        'createdAt': now,
        'status': 'Planned',
        'clientName': client,
        'shipperName': shipper,
        'pickupAddress': shipperAddr,
        'receiverName': receiver,
        'deliveryAddress': receiverAddr,
        'truckId': _selectedTruckId,
        'units': _useMetric ? 'metric' : 'imperial',
        'notes': _notesCtrl.text.trim(),
        // Distance snapshots
        if (_truckToPickup != null) ...{
          'truckToPickup': _truckToPickup!.toMap(),
        },
        if (_pickupToDelivery != null) ...{
          'pickupToDelivery': _pickupToDelivery!.toMap(),
        },
      };

      await loads.add(docData);

      if (!mounted) return;
      _snack('Load saved.');
      Navigator.pop(context, true); // ✅ go back after save
    } catch (e) {
      _snack('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// --- Dialogs (simple selectors from Firestore) ---

class _SelectDocDialog extends StatefulWidget {
  final String collection;
  final void Function(QueryDocumentSnapshot<Map<String, dynamic>>) onSelect;
  const _SelectDocDialog({required this.collection, required this.onSelect});

  @override
  State<_SelectDocDialog> createState() => _SelectDocDialogState();
}

class _SelectDocDialogState extends State<_SelectDocDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance.collection(widget.collection);
    final stream = col.limit(100).snapshots();

    return AlertDialog(
      title: Text('Select ${widget.collection}'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name…',
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs.where((d) {
                    final name =
                        (d.data()['name'] ?? '').toString().toLowerCase();
                    return _query.isEmpty || name.contains(_query);
                  }).toList();
                  if (docs.isEmpty) {
                    return const Center(child: Text('No matches.'));
                  }
                  return ListView.separated(
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final name = (d.data()['name'] ?? '').toString();
                      return ListTile(
                        title: Text(name),
                        onTap: () {
                          widget.onSelect(d);
                          Navigator.pop(context);
                        },
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: docs.length,
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

class _SelectAddressDialog extends StatefulWidget {
  final String collection;
  final String parentName;
  final void Function(String address) onSelect;
  const _SelectAddressDialog({
    required this.collection,
    required this.parentName,
    required this.onSelect,
  });

  @override
  State<_SelectAddressDialog> createState() => _SelectAddressDialogState();
}

class _SelectAddressDialogState extends State<_SelectAddressDialog> {
  final _manualAddrCtrl = TextEditingController();
  @override
  void dispose() {
    _manualAddrCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This assumes addresses are stored on the entity doc as an array `addresses: [ "123 Main...", ... ]`
    // If you keep them elsewhere, adjust this loader.
    final col = FirebaseFirestore.instance.collection(widget.collection);
    final stream =
        col.where('name', isEqualTo: widget.parentName).limit(1).snapshots();

    return AlertDialog(
      title: Text('Pick ${widget.collection} address'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                final addresses = <String>[];
                if (snap.hasData && snap.data!.docs.isNotEmpty) {
                  final data = snap.data!.docs.first.data();
                  final list = (data['addresses'] ?? []) as List<dynamic>;
                  addresses.addAll(list.map((e) => e.toString()));
                }
                if (addresses.isEmpty) {
                  return const Text(
                      'No saved addresses found. Enter manually below.');
                }
                return SizedBox(
                  height: 180,
                  child: ListView.separated(
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.place),
                      title: Text(addresses[i]),
                      onTap: () {
                        widget.onSelect(addresses[i]);
                        Navigator.pop(context);
                      },
                    ),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: addresses.length,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manualAddrCtrl,
              decoration: const InputDecoration(
                labelText: 'Or enter address',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final a = _manualAddrCtrl.text.trim();
            if (a.isNotEmpty) {
              widget.onSelect(a);
              Navigator.pop(context);
            }
          },
          child: const Text('Use this address'),
        ),
      ],
    );
  }
}

// --- Models ---

class DistanceResult {
  final int distanceMeters;
  final String distanceText;
  final int durationSeconds;
  final String durationText;
  DistanceResult({
    required this.distanceMeters,
    required this.distanceText,
    required this.durationSeconds,
    required this.durationText,
  });
  Map<String, dynamic> toMap() => {
        'distanceMeters': distanceMeters,
        'distanceText': distanceText,
        'durationSeconds': durationSeconds,
        'durationText': durationText,
      };
}

enum StartOrigin { liveTruck, lastDelivery, yard, custom }
