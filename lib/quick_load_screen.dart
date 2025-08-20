// lib/quick_load_screen.dart
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'widgets/main_menu_button.dart';

// inside AppBar
actions: [
  MainMenuButton(
    onSettingsApplied: (seedColor, companyName) {
      // (optional) live theme apply if you manage ThemeMode dynamically
    },
  ),
],

/// Minimal LatLng so we don't depend on google_maps_flutter (good for Windows)
class LatLng {
  final double latitude;
  final double longitude;
  const LatLng(this.latitude, this.longitude);
}

/// TODO: Replace with your real Google API key (Distance Matrix + Geocoding)
const String kGoogleMapsApiKey = 'PASTE_YOUR_REAL_KEY_HERE';

class QuickLoadScreen extends StatefulWidget {
  /// Pass a loadId to edit an existing load; null = create new
  final String? loadId;
  const QuickLoadScreen({super.key, this.loadId});

  @override
  State<QuickLoadScreen> createState() => _QuickLoadScreenState();
}

class _QuickLoadScreenState extends State<QuickLoadScreen> {
  // ----------- create/edit flags -----------
  bool _loadingExisting = false;
  bool get _isEdit => widget.loadId != null;

  // ----------- form controllers -----------
  final _clientCtrl = TextEditingController();

  final _shipperCtrl = TextEditingController();
  final _shipperAddrCtrl = TextEditingController();
  LatLng? _shipperLatLng;

  final _receiverCtrl = TextEditingController(); // primary receiver name
  final _receiverAddrCtrl = TextEditingController(); // primary receiver address
  LatLng? _receiverLatLng;

  // Multi-drop (extra deliveries after the primary)
  final List<Stop> _extraDeliveries = <Stop>[];

  // Toggles
  bool _pickupSameAsShipper = true;

  // Numbers/IDs
  final _shippingNumCtrl = TextEditingController();
  final _poNumCtrl = TextEditingController();
  final _loadNumCtrl = TextEditingController();
  final _projectNumCtrl = TextEditingController();

  // Notes
  final _notesCtrl = TextEditingController();

  // Start origin & units
  StartOrigin _startOrigin = StartOrigin.liveTruck;
  final _customStartCtrl = TextEditingController();
  LatLng? _customStartLatLng;

  bool _useMetric = true; // km vs mi

  // Drivers/Trucks
  String? _selectedDriverId;
  String? _selectedTruckId;

  // Handoff / Relay
  bool _handoffEnabled = false;
  final _handoffAddrCtrl = TextEditingController();
  LatLng? _handoffLatLng;
  String? _handoffDriverId;
  String? _handoffTruckId;

  // Pricing
  RateMode _rateMode = RateMode.perDistance;
  final _ratePerUnitCtrl = TextEditingController();
  final _flatRateCtrl = TextEditingController();
  double? _estimatedTotal;

  // Distances
  DistanceResult? _truckToPickup;
  DistanceResult?
      _pickupToPrimary; // pickup->handoff (if enabled) OR pickup->first delivery

  int _routeMeters = 0; // full route meters (handoff->drops or pickup->drops)
  int _firstLegMeters = 0; // pickup->handoff
  int _secondLegMeters = 0; // handoff->drops
  double? _firstPct; // distance % split
  double? _secondPct;

  bool _saving = false;
  bool _calculating = false;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadExisting();
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _shipperCtrl.dispose();
    _shipperAddrCtrl.dispose();
    _receiverCtrl.dispose();
    _receiverAddrCtrl.dispose();
    _shippingNumCtrl.dispose();
    _poNumCtrl.dispose();
    _loadNumCtrl.dispose();
    _projectNumCtrl.dispose();
    _notesCtrl.dispose();
    _customStartCtrl.dispose();
    _handoffAddrCtrl.dispose();
    _ratePerUnitCtrl.dispose();
    _flatRateCtrl.dispose();
    super.dispose();
  }

  // ================= Create/Edit loader =================

  Future<void> _loadExisting() async {
    setState(() => _loadingExisting = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('loads')
          .doc(widget.loadId)
          .get();
      if (!doc.exists) {
        _snack('Load not found.');
        if (mounted) Navigator.pop(context);
        return;
      }
      final m = doc.data() ?? {};

      // Core names/addresses
      _clientCtrl.text = (m['clientName'] ?? '').toString();
      _shipperCtrl.text = (m['shipperName'] ?? '').toString();
      _shipperAddrCtrl.text = (m['pickupAddress'] ?? '').toString();
      _receiverCtrl.text = (m['receiverName'] ?? '').toString();
      _receiverAddrCtrl.text = (m['deliveryAddress'] ?? '').toString();

      // LatLngs (if present)
      final pLat = m['pickupLat'];
      final pLng = m['pickupLng'];
      _shipperLatLng = (pLat is num && pLng is num)
          ? LatLng(pLat.toDouble(), pLng.toDouble())
          : null;
      final dLat = m['deliveryLat'];
      final dLng = m['deliveryLng'];
      _receiverLatLng = (dLat is num && dLng is num)
          ? LatLng(dLat.toDouble(), dLng.toDouble())
          : null;

      // Units
      final units = (m['units'] ?? 'metric').toString();
      _useMetric = units == 'metric';

      // Links
      _selectedDriverId = ((m['driverId'] ?? '') as String?)?.isEmpty == true
          ? null
          : (m['driverId'] as String?);
      _selectedTruckId = ((m['truckId'] ?? '') as String?)?.isEmpty == true
          ? null
          : (m['truckId'] as String?);

      // Numbers
      _shippingNumCtrl.text = (m['shippingNumber'] ?? '').toString();
      _poNumCtrl.text = (m['poNumber'] ?? '').toString();
      _loadNumCtrl.text = (m['loadNumber'] ?? '').toString();
      _projectNumCtrl.text = (m['projectNumber'] ?? '').toString();

      // Notes
      _notesCtrl.text = (m['notes'] ?? '').toString();

      // Extra deliveries
      _extraDeliveries.clear();
      if (m['extraDeliveries'] is List) {
        for (final x in (m['extraDeliveries'] as List)) {
          final mm = (x as Map?) ?? {};
          final stop = Stop();
          stop.nameCtrl.text = (mm['name'] ?? '').toString();
          stop.addrCtrl.text = (mm['address'] ?? '').toString();
          final lat = mm['lat'];
          final lng = mm['lng'];
          if (lat is num && lng is num) {
            stop.latLng = LatLng(lat.toDouble(), lng.toDouble());
          }
          _extraDeliveries.add(stop);
        }
      }

      // Handoff
      final h = (m['handoff'] is Map)
          ? m['handoff'] as Map<String, dynamic>
          : const {};
      _handoffEnabled = (h['enabled'] ?? false) as bool;
      _handoffAddrCtrl.text = (h['address'] ?? '').toString();
      final hLat = h['lat'];
      final hLng = h['lng'];
      _handoffLatLng = (hLat is num && hLng is num)
          ? LatLng(hLat.toDouble(), hLng.toDouble())
          : null;
      _handoffDriverId = ((h['driverId'] ?? '') as String?)?.isEmpty == true
          ? null
          : (h['driverId'] as String?);
      _handoffTruckId = ((h['truckId'] ?? '') as String?)?.isEmpty == true
          ? null
          : (h['truckId'] as String?);

      // Pricing
      final pr = (m['pricing'] is Map)
          ? m['pricing'] as Map<String, dynamic>
          : const {};
      final mode = (pr['mode'] ?? 'per_distance').toString();
      _rateMode = mode == 'flat' ? RateMode.flat : RateMode.perDistance;
      if (_rateMode == RateMode.perDistance) {
        final rate = pr['ratePerUnit'];
        _ratePerUnitCtrl.text = rate == null ? '' : rate.toString();
      } else {
        final flat = pr['flatRate'];
        _flatRateCtrl.text = flat == null ? '' : flat.toString();
      }
      final est = pr['estimatedTotal'];
      _estimatedTotal = (est is num) ? est.toDouble() : null;

      // (Optional) cached distances
      final firstLeg = m['firstLeg'];
      if (firstLeg is Map) {
        _pickupToPrimary = DistanceResult(
          distanceMeters: (firstLeg['distanceMeters'] ?? 0) as int,
          distanceText: (firstLeg['distanceText'] ?? '').toString(),
          durationSeconds: (firstLeg['durationSeconds'] ?? 0) as int,
          durationText: (firstLeg['durationText'] ?? '').toString(),
        );
      }
      _routeMeters = (m['routeMeters'] is int) ? m['routeMeters'] as int : 0;

      // Split (if present)
      if (_handoffEnabled) {
        _firstLegMeters = (h['firstLegMeters'] ?? 0) as int;
        _secondLegMeters = (h['secondLegMeters'] ?? 0) as int;
        final fp = h['firstPct'];
        final sp = h['secondPct'];
        _firstPct = (fp is num) ? fp.toDouble() : null;
        _secondPct = (sp is num) ? sp.toDouble() : null;
      }

      setState(() {});
    } catch (e) {
      _snack('Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final isKm = _useMetric;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Load' : 'Quick Load')),
      body: _loadingExisting
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _linePicker(
                      label: 'Client',
                      controller: _clientCtrl,
                      onPick: () => _pickFromCollection('clients', (d) {
                        _clientCtrl.text =
                            (d.data()['name'] ?? d.data()['displayName'] ?? '')
                                .toString();
                      }),
                    ),

                    const SizedBox(height: 12),

                    // Shipper + Pickup
                    _linePicker(
                      label: 'Shipper (Company)',
                      controller: _shipperCtrl,
                      onPick: () => _pickFromCollection('shippers', (d) async {
                        _shipperCtrl.text = (d.data()['name'] ?? '').toString();
                        if (_pickupSameAsShipper) {
                          final addr = await _resolveDefaultAddress(
                              'shippers', _shipperCtrl.text);
                          if (addr != null) _shipperAddrCtrl.text = addr;
                          setState(() {});
                        }
                      }),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Pickup address same as shipper'),
                      value: _pickupSameAsShipper,
                      onChanged: (v) async {
                        setState(() => _pickupSameAsShipper = v);
                        if (v) {
                          final addr = await _resolveDefaultAddress(
                              'shippers', _shipperCtrl.text);
                          if (addr != null) _shipperAddrCtrl.text = addr;
                          setState(() {});
                        }
                      },
                    ),
                    _addressRow(
                      label: 'Pickup Address',
                      controller: _shipperAddrCtrl,
                      current: _shipperLatLng,
                      onPickSaved: () => _pickAddressFromSaved(
                        'shippers',
                        _shipperCtrl.text,
                        (a) {
                          _shipperAddrCtrl.text = a;
                          setState(() {});
                        },
                      ),
                      onPickMap: () async {
                        final picked = await _openManualPicker(
                          initial: _shipperLatLng,
                          initialQuery: _shipperAddrCtrl.text,
                        );
                        if (picked != null) {
                          _shipperLatLng = picked.latLng;
                          _shipperAddrCtrl.text = picked.address;
                          setState(() {});
                        }
                      },
                    ),

                    const SizedBox(height: 12),

                    // Primary receiver
                    _linePicker(
                      label: 'Receiver (Company)',
                      controller: _receiverCtrl,
                      onPick: () => _pickFromCollection('receivers', (d) async {
                        _receiverCtrl.text =
                            (d.data()['name'] ?? '').toString();
                        final addr = await _resolveDefaultAddress(
                            'receivers', _receiverCtrl.text);
                        if (addr != null) _receiverAddrCtrl.text = addr;
                        setState(() {});
                      }),
                    ),
                    _addressRow(
                      label: 'Primary Delivery Address',
                      controller: _receiverAddrCtrl,
                      current: _receiverLatLng,
                      onPickSaved: () => _pickAddressFromSaved(
                        'receivers',
                        _receiverCtrl.text,
                        (a) {
                          _receiverAddrCtrl.text = a;
                          setState(() {});
                        },
                      ),
                      onPickMap: () async {
                        final picked = await _openManualPicker(
                          initial: _receiverLatLng,
                          initialQuery: _receiverAddrCtrl.text,
                        );
                        if (picked != null) {
                          _receiverLatLng = picked.latLng;
                          _receiverAddrCtrl.text = picked.address;
                          setState(() {});
                        }
                      },
                    ),

                    // Extra deliveries
                    const SizedBox(height: 12),
                    _extraDeliveriesBlock(),

                    const SizedBox(height: 12),

                    // Driver & Truck (first leg)
                    _driverPicker(
                      title: 'Driver (First Leg)',
                      value: _selectedDriverId,
                      onChanged: (v) async {
                        setState(() => _selectedDriverId = v);
                        if (v != null) {
                          final d = await FirebaseFirestore.instance
                              .collection('employees')
                              .doc(v)
                              .get();
                          final driverTruckId = d.data()?['truckId'] ??
                              d.data()?['defaultTruckId'];
                          if (driverTruckId is String &&
                              driverTruckId.isNotEmpty) {
                            setState(() => _selectedTruckId = driverTruckId);
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    _truckPicker(
                      title: 'Truck (First Leg)',
                      value: _selectedTruckId,
                      onChanged: (v) => setState(() => _selectedTruckId = v),
                    ),

                    const SizedBox(height: 12),
                    _startOriginPicker(),
                    if (_startOrigin == StartOrigin.custom) ...[
                      const SizedBox(height: 8),
                      _addressRow(
                        label: 'Custom Start Address',
                        controller: _customStartCtrl,
                        current: _customStartLatLng,
                        onPickSaved: null,
                        onPickMap: () async {
                          final picked = await _openManualPicker(
                            initial: _customStartLatLng,
                            initialQuery: _customStartCtrl.text,
                          );
                          if (picked != null) {
                            _customStartLatLng = picked.latLng;
                            _customStartCtrl.text = picked.address;
                            setState(() {});
                          }
                        },
                      ),
                    ],

                    const SizedBox(height: 12),
                    _unitToggle(),

                    const SizedBox(height: 12),
                    _numbersRow(),

                    const SizedBox(height: 12),
                    _handoffSection(),

                    const SizedBox(height: 12),
                    _pricingCard(isKm),

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
                    _splitView(),

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
                            label: Text(_saving
                                ? (_isEdit ? 'Updating…' : 'Saving…')
                                : (_isEdit ? 'Update Load' : 'Save Load')),
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

  // ---------- Small UI helpers ----------

  Widget _linePicker({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    VoidCallback? onPick,
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
            onChanged: (_) async {
              if (label.startsWith('Shipper') && _pickupSameAsShipper) {
                final addr =
                    await _resolveDefaultAddress('shippers', _shipperCtrl.text);
                if (addr != null) setState(() => _shipperAddrCtrl.text = addr);
              }
              if (label.startsWith('Receiver')) {
                final addr = await _resolveDefaultAddress(
                    'receivers', _receiverCtrl.text);
                if (addr != null) setState(() => _receiverAddrCtrl.text = addr);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Select from saved',
          onPressed: onPick,
          icon: const Icon(Icons.list_alt),
        ),
      ],
    );
  }

  Widget _addressRow({
    required String label,
    required TextEditingController controller,
    required LatLng? current,
    VoidCallback? onPickSaved,
    required Future<void> Function()? onPickMap,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.streetAddress,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Pick coordinates',
          icon: const Icon(Icons.place),
          onPressed: onPickMap,
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Pick saved address',
          icon: const Icon(Icons.list_alt),
          onPressed: onPickSaved,
        ),
      ],
    );
  }

  Widget _extraDeliveriesBlock() {
    return Column(
      children: [
        Row(
          children: [
            const Text('Additional Deliveries',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _extraDeliveries
                  .add(Stop(label: 'Delivery ${_extraDeliveries.length + 2}'))),
              icon: const Icon(Icons.add),
              label: const Text('Add Delivery'),
            ),
          ],
        ),
        if (_extraDeliveries.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('No additional deliveries.'),
          ),
        for (int i = 0; i < _extraDeliveries.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _extraDeliveries[i].nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Receiver (Company) (optional)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Pick saved (receivers)',
                        icon: const Icon(Icons.list_alt),
                        onPressed: () =>
                            _pickFromCollection('receivers', (d) async {
                          final nm = (d.data()['name'] ?? '').toString();
                          _extraDeliveries[i].nameCtrl.text = nm;
                          final addr =
                              await _resolveDefaultAddress('receivers', nm);
                          if (addr != null)
                            _extraDeliveries[i].addrCtrl.text = addr;
                          setState(() {});
                        }),
                      ),
                      IconButton(
                        tooltip: 'Move up',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: i == 0
                            ? null
                            : () => setState(() {
                                  final s = _extraDeliveries.removeAt(i);
                                  _extraDeliveries.insert(i - 1, s);
                                }),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        icon: const Icon(Icons.arrow_downward),
                        onPressed: i == _extraDeliveries.length - 1
                            ? null
                            : () => setState(() {
                                  final s = _extraDeliveries.removeAt(i);
                                  _extraDeliveries.insert(i + 1, s);
                                }),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            setState(() => _extraDeliveries.removeAt(i)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _extraDeliveries[i].addrCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Delivery Address',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.streetAddress,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Pick coordinates',
                        icon: const Icon(Icons.place),
                        onPressed: () async {
                          final picked = await _openManualPicker(
                            initial: _extraDeliveries[i].latLng,
                            initialQuery: _extraDeliveries[i].addrCtrl.text,
                          );
                          if (picked != null) {
                            _extraDeliveries[i].latLng = picked.latLng;
                            _extraDeliveries[i].addrCtrl.text = picked.address;
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _numbersRow() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _numField('Shipping #', _shippingNumCtrl)),
            const SizedBox(width: 8),
            Expanded(child: _numField('PO #', _poNumCtrl)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _numField('Load #', _loadNumCtrl)),
            const SizedBox(width: 8),
            Expanded(child: _numField('Project #', _projectNumCtrl)),
          ],
        ),
      ],
    );
  }

  Widget _numField(String label, TextEditingController c) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _pricingCard(bool isKm) {
    final isPerDist = _rateMode == RateMode.perDistance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Text('Pricing',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                ChoiceChip(
                  label: const Text('Per distance'),
                  selected: _rateMode == RateMode.perDistance,
                  onSelected: (_) =>
                      setState(() => _rateMode = RateMode.perDistance),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Flat per load'),
                  selected: _rateMode == RateMode.flat,
                  onSelected: (_) => setState(() => _rateMode = RateMode.flat),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isPerDist)
              TextField(
                controller: _ratePerUnitCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Rate per ${isKm ? "km" : "mile"}',
                  prefixText: '\$ ',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _recomputePrice(),
              )
            else
              TextField(
                controller: _flatRateCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Flat rate (per load)',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _recomputePrice(),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Estimated total: ${_estimatedTotal == null ? "--" : "\$${_estimatedTotal!.toStringAsFixed(2)}"}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _driverPicker({
    required String title,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final q = FirebaseFirestore.instance
        .collection('employees')
        .where('role', isEqualTo: 'driver')
        .orderBy('name');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final items = <DropdownMenuItem<String>>[];
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final id = d.id;
            final name = d.data()['name']?.toString() ?? 'Driver $id';
            items.add(DropdownMenuItem(value: id, child: Text(name)));
          }
        }
        return InputDecorator(
          decoration: InputDecoration(
            labelText: title,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              hint: Text('Select $title'),
              items: items,
              onChanged: onChanged,
            ),
          ),
        );
      },
    );
  }

  Widget _truckPicker({
    required String title,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
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
          decoration: InputDecoration(
            labelText: title,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              hint: Text('Select $title'),
              items: items,
              onChanged: onChanged,
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
          onSelected: (_) {
            setState(() => _useMetric = true);
            _recomputePrice();
          },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('mi'),
          selected: !_useMetric,
          onSelected: (_) {
            setState(() => _useMetric = false);
            _recomputePrice();
          },
        ),
      ],
    );
  }

  Widget _handoffSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Enable Handoff / Relay'),
              value: _handoffEnabled,
              onChanged: (v) => setState(() => _handoffEnabled = v),
            ),
            if (_handoffEnabled) ...[
              _addressRow(
                label: 'Handoff Location',
                controller: _handoffAddrCtrl,
                current: _handoffLatLng,
                onPickSaved: null,
                onPickMap: () async {
                  final picked = await _openManualPicker(
                    initial: _handoffLatLng,
                    initialQuery: _handoffAddrCtrl.text,
                  );
                  if (picked != null) {
                    _handoffLatLng = picked.latLng;
                    _handoffAddrCtrl.text = picked.address;
                    setState(() {});
                  }
                },
              ),
              const SizedBox(height: 8),
              _driverPicker(
                title: 'Driver (Second Leg)',
                value: _handoffDriverId,
                onChanged: (v) => setState(() => _handoffDriverId = v),
              ),
              const SizedBox(height: 8),
              _truckPicker(
                title: 'Truck (Second Leg)',
                value: _handoffTruckId,
                onChanged: (v) => setState(() => _handoffTruckId = v),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _distancesView() {
    if (_truckToPickup == null &&
        _pickupToPrimary == null &&
        _routeMeters == 0) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (_truckToPickup != null)
          _distCard('Truck ➜ Pickup', _truckToPickup!),
        if (_pickupToPrimary != null)
          _distCard(
              _handoffEnabled ? 'Pickup ➜ Handoff' : 'Pickup ➜ First Delivery',
              _pickupToPrimary!),
        Card(
          child: ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('Route total (deliveries)'),
            subtitle: Text(_formatDistance(_routeMeters, _useMetric)),
          ),
        ),
      ],
    );
  }

  Widget _splitView() {
    if (!_handoffEnabled ||
        _firstLegMeters <= 0 ||
        _secondLegMeters <= 0 ||
        _firstPct == null ||
        _secondPct == null) {
      return const SizedBox.shrink();
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.percent),
        title: const Text('Driver Split'),
        subtitle: Text(
          'First leg: ${_formatDistance(_firstLegMeters, _useMetric)} '
          '(${_firstPct!.toStringAsFixed(1)}%) • '
          'Second leg: ${_formatDistance(_secondLegMeters, _useMetric)} '
          '(${_secondPct!.toStringAsFixed(1)}%)',
        ),
      ),
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

  String _formatDistance(int meters, bool metric) {
    if (metric) {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(1)} km';
    } else {
      final mi = meters / 1609.344;
      return '${mi.toStringAsFixed(1)} mi';
    }
  }

  // ============== Selection helpers ==============

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

  Future<String?> _resolveDefaultAddress(String collection, String name) async {
    if (name.trim().isEmpty) return null;
    final col = FirebaseFirestore.instance.collection(collection);
    final q = await col.where('name', isEqualTo: name).limit(1).get();
    if (q.docs.isEmpty) return null;
    final data = q.docs.first.data();
    final addr = (data['address'] ?? '').toString();
    if (addr.isNotEmpty) return addr;
    final list = (data['addresses'] ?? []) as List<dynamic>;
    if (list.isNotEmpty) return list.first.toString();
    return null;
  }

  // ============== Calculate ==============

  Future<void> _calculateAll() async {
    final pickupAddr = _shipperAddrCtrl.text.trim();
    final primaryAddr = _receiverAddrCtrl.text.trim();
    if (pickupAddr.isEmpty || primaryAddr.isEmpty) {
      _snack('Enter pickup and at least the first delivery address.');
      return;
    }

    setState(() => _calculating = true);
    try {
      // Build drops list
      final drops = <String>[];
      drops.add(_locationQuery(primaryAddr, _receiverLatLng));
      for (final s in _extraDeliveries) {
        if (s.addrCtrl.text.trim().isNotEmpty) {
          drops.add(_locationQuery(s.addrCtrl.text.trim(), s.latLng));
        }
      }

      // Truck -> Pickup
      final originStart = await _resolveStartOriginAddress();
      if (originStart != null && originStart.isNotEmpty) {
        _truckToPickup = await _distanceMatrix(
          origin: originStart,
          destination: _locationQuery(pickupAddr, _shipperLatLng),
          unitsMetric: _useMetric,
        );
      } else {
        _truckToPickup = null;
      }

      // Handoff split vs single leg
      if (_handoffEnabled && _handoffAddrCtrl.text.trim().isNotEmpty) {
        // Leg 1: pickup -> handoff
        final leg1 = await _distanceMatrix(
          origin: _locationQuery(pickupAddr, _shipperLatLng),
          destination:
              _locationQuery(_handoffAddrCtrl.text.trim(), _handoffLatLng),
          unitsMetric: _useMetric,
        );
        _pickupToPrimary = leg1;

        // Leg 2: handoff -> all drops (sum pairwise)
        final meters2 = await _sumRouteMeters([
          _locationQuery(_handoffAddrCtrl.text.trim(), _handoffLatLng),
          ...drops
        ]);

        _firstLegMeters = leg1.distanceMeters;
        _secondLegMeters = meters2;
        _routeMeters = meters2; // downstream route total for pricing
        final total = (_firstLegMeters + _secondLegMeters).toDouble();
        _firstPct = total > 0 ? (_firstLegMeters / total) * 100.0 : 0.0;
        _secondPct = total > 0 ? (_secondLegMeters / total) * 100.0 : 0.0;
      } else {
        // Single leg route: pickup -> all drops
        final meters = await _sumRouteMeters(
            [_locationQuery(pickupAddr, _shipperLatLng), ...drops]);
        _routeMeters = meters;
        _pickupToPrimary = await _distanceMatrix(
          origin: _locationQuery(pickupAddr, _shipperLatLng),
          destination: _locationQuery(primaryAddr, _receiverLatLng),
          unitsMetric: _useMetric,
        );
        _firstLegMeters = 0;
        _secondLegMeters = _routeMeters;
        _firstPct = null;
        _secondPct = null;
      }

      _recomputePrice();
      setState(() {});
    } catch (e) {
      _snack('Failed to calculate: $e');
    } finally {
      setState(() => _calculating = false);
    }
  }

  String _locationQuery(String address, LatLng? ll) {
    if (ll != null) return '${ll.latitude},${ll.longitude}';
    return address;
  }

  Future<String?> _resolveStartOriginAddress() async {
    switch (_startOrigin) {
      case StartOrigin.custom:
        return _customStartLatLng != null
            ? '${_customStartLatLng!.latitude},${_customStartLatLng!.longitude}'
            : _customStartCtrl.text.trim();
      case StartOrigin.yard:
        final doc = await FirebaseFirestore.instance
            .collection('settings')
            .doc('app')
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          final yardAddr = (data['yardAddress'] ?? '').toString();
          final yardLat = data['yardLat'];
          final yardLng = data['yardLng'];
          if (yardLat != null && yardLng != null) return '$yardLat,$yardLng';
          if (yardAddr.isNotEmpty) return yardAddr;
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
          final lat = d['deliveryLat'];
          final lng = d['deliveryLng'];
          final addr = (d['deliveryAddress'] ?? '').toString();
          if (lat != null && lng != null) return '$lat,$lng';
          if (addr.isNotEmpty) return addr;
        }
        return null;
      case StartOrigin.liveTruck:
        if (_selectedTruckId == null) return null;
        final v = await FirebaseFirestore.instance
            .collection('vehicles')
            .doc(_selectedTruckId)
            .get();
        if (v.exists) {
          final live = v.data()?['live'] as Map<String, dynamic>?; // {lat, lng}
          final lat = live?['lat'];
          final lng = live?['lng'];
          if (lat != null && lng != null) return '$lat,$lng';
        }
        return null;
    }
  }

  Future<int> _sumRouteMeters(List<String> route) async {
    if (route.length < 2) return 0;
    int total = 0;
    for (int i = 0; i < route.length - 1; i++) {
      final seg = await _distanceMatrix(
        origin: route[i],
        destination: route[i + 1],
        unitsMetric: _useMetric,
      );
      total += seg.distanceMeters;
    }
    return total;
  }

  Future<DistanceResult> _distanceMatrix({
    required String origin,
    required String destination,
    required bool unitsMetric,
  }) async {
    if (kGoogleMapsApiKey.isEmpty ||
        kGoogleMapsApiKey == 'PASTE_YOUR_REAL_KEY_HERE') {
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

  // ============== Geocoding & Manual Picker ==============

  Future<String> _reverseGeocode(LatLng ll) async {
    final url =
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${ll.latitude},${ll.longitude}&key=$kGoogleMapsApiKey';
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) return '${ll.latitude},${ll.longitude}';
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (data['results'] as List?) ?? [];
    if (results.isEmpty) return '${ll.latitude},${ll.longitude}';
    return (results.first['formatted_address'] ??
            '${ll.latitude},${ll.longitude}')
        .toString();
  }

  Future<PickedLocation?> _openManualPicker(
      {LatLng? initial, String? initialQuery}) async {
    return showDialog<PickedLocation>(
      context: context,
      builder: (_) => ManualPickerDialog(
        reverseGeocode: _reverseGeocode,
        initial: initial,
        initialQuery: initialQuery,
      ),
    );
  }

  // ============== Pricing ==============

  void _recomputePrice() {
    double? total;
    if (_rateMode == RateMode.perDistance) {
      final meters = _handoffEnabled
          ? (_firstLegMeters + _secondLegMeters)
          : _routeMeters.toDouble();
      final units = _useMetric ? (meters / 1000.0) : (meters / 1609.344);
      final rate = _parseDouble(_ratePerUnitCtrl.text);
      if (rate != null) total = rate * units;
    } else {
      total = _parseDouble(_flatRateCtrl.text);
    }
    setState(() => _estimatedTotal = total);
  }

  double? _parseDouble(String s) {
    final t = s.replaceAll(',', '').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  // ============== Save (Create or Update) ==============

  Future<void> _saveLoad() async {
    final client = _clientCtrl.text.trim();
    final shipper = _shipperCtrl.text.trim();
    final pickupAddr = _shipperAddrCtrl.text.trim();
    final receiver = _receiverCtrl.text.trim();
    final deliveryAddr = _receiverAddrCtrl.text.trim();

    if (client.isEmpty ||
        shipper.isEmpty ||
        pickupAddr.isEmpty ||
        receiver.isEmpty ||
        deliveryAddr.isEmpty) {
      _snack('Please fill Client, Shipper, Pickup, and Primary Delivery.');
      return;
    }

    if (_pickupToPrimary == null ||
        (_selectedTruckId != null && _truckToPickup == null)) {
      await _calculateAll();
    }

    setState(() => _saving = true);
    try {
      final loads = FirebaseFirestore.instance.collection('loads');

      final pricing = <String, dynamic>{
        'mode': _rateMode == RateMode.perDistance ? 'per_distance' : 'flat',
        'currency': 'CAD',
        if (_rateMode == RateMode.perDistance) ...{
          'unit': _useMetric ? 'km' : 'mi',
          'ratePerUnit': _parseDouble(_ratePerUnitCtrl.text),
          'estimatedTotal': _estimatedTotal,
          'routeMetersSnapshot': _handoffEnabled
              ? (_firstLegMeters + _secondLegMeters)
              : _routeMeters,
        } else ...{
          'flatRate': _parseDouble(_flatRateCtrl.text),
          'estimatedTotal': _estimatedTotal,
        },
      };

      final extraStops = _extraDeliveries
          .where((s) => s.addrCtrl.text.trim().isNotEmpty)
          .map((s) => {
                'name': s.nameCtrl.text.trim(),
                'address': s.addrCtrl.text.trim(),
                'lat': s.latLng?.latitude,
                'lng': s.latLng?.longitude,
              })
          .toList();

      final docData = {
        if (!_isEdit) 'createdAt': DateTime.now(),
        'status': 'Planned',

        // Core
        'clientName': client,
        'shipperName': shipper,
        'pickupAddress': pickupAddr,
        'pickupLat': _shipperLatLng?.latitude,
        'pickupLng': _shipperLatLng?.longitude,

        'receiverName': receiver,
        'deliveryAddress': deliveryAddr,
        'deliveryLat': _receiverLatLng?.latitude,
        'deliveryLng': _receiverLatLng?.longitude,

        'extraDeliveries': extraStops,
        'units': _useMetric ? 'metric' : 'imperial',
        'notes': _notesCtrl.text.trim(),

        // Links
        'driverId': _selectedDriverId,
        'truckId': _selectedTruckId,

        // Numbers
        'shippingNumber': _shippingNumCtrl.text.trim(),
        'poNumber': _poNumCtrl.text.trim(),
        'loadNumber': _loadNumCtrl.text.trim(),
        'projectNumber': _projectNumCtrl.text.trim(),

        // Distances
        if (_truckToPickup != null) 'truckToPickup': _truckToPickup!.toMap(),
        if (_pickupToPrimary != null) 'firstLeg': _pickupToPrimary!.toMap(),
        'routeMeters': _handoffEnabled
            ? (_firstLegMeters + _secondLegMeters)
            : _routeMeters,

        // Handoff
        'handoff': _handoffEnabled
            ? {
                'enabled': true,
                'address': _handoffAddrCtrl.text.trim(),
                'lat': _handoffLatLng?.latitude,
                'lng': _handoffLatLng?.longitude,
                'driverId': _handoffDriverId,
                'truckId': _handoffTruckId,
                'firstLegMeters': _firstLegMeters,
                'secondLegMeters': _secondLegMeters,
                'firstPct': _firstPct,
                'secondPct': _secondPct,
              }
            : {'enabled': false},

        // Pricing
        'pricing': pricing,
      };

      if (_isEdit) {
        await loads.doc(widget.loadId).update(docData);
      } else {
        await loads.add(docData);
      }

      if (!mounted) return;
      _snack(_isEdit ? 'Load updated.' : 'Load saved.');
      Navigator.pop(context, true);
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

// ================= Dialogs =================

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
                    final m = d.data();
                    final name = (m['name'] ?? m['displayName'] ?? '')
                        .toString()
                        .toLowerCase();
                    return _query.isEmpty || name.contains(_query);
                  }).toList();
                  if (docs.isEmpty) {
                    return const Center(child: Text('No matches.'));
                  }
                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final name =
                          (d.data()['name'] ?? d.data()['displayName'] ?? '')
                              .toString();
                      return ListTile(
                        title: Text(name),
                        onTap: () {
                          widget.onSelect(d);
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Close'))
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
                  if (data['address'] != null &&
                      (data['address'] as String).isNotEmpty) {
                    addresses.add(data['address'] as String);
                  }
                  addresses.addAll(list.map((e) => e.toString()));
                }
                if (addresses.isEmpty) {
                  return const Text(
                    'No saved addresses found. Enter manually below.',
                  );
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

// ================= Manual Picker (no map) =================

class PickedLocation {
  final LatLng latLng;
  final String address;
  PickedLocation(this.latLng, this.address);
}

class ManualPickerDialog extends StatefulWidget {
  final LatLng? initial;
  final String? initialQuery;
  final Future<String> Function(LatLng) reverseGeocode;
  const ManualPickerDialog({
    super.key,
    required this.reverseGeocode,
    this.initial,
    this.initialQuery,
  });

  @override
  State<ManualPickerDialog> createState() => _ManualPickerDialogState();
}

class _ManualPickerDialogState extends State<ManualPickerDialog> {
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _latCtrl.text = widget.initial!.latitude.toString();
      _lngCtrl.text = widget.initial!.longitude.toString();
    }
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isInteractiveMapAvailable = !(!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS);
    return AlertDialog(
      title: Text(isInteractiveMapAvailable
          ? 'Pick coordinates (no map on this platform)'
          : 'Pick coordinates'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Latitude'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lngCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Longitude'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Tip: paste coordinates like "43.6532,-79.3832" into Latitude and Longitude.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final lat = double.tryParse(_latCtrl.text.trim());
            final lng = double.tryParse(_lngCtrl.text.trim());
            if (lat == null || lng == null) {
              return;
            }
            final ll = LatLng(lat, lng);
            final addr = await widget.reverseGeocode(ll);
            if (!mounted) return;
            Navigator.pop(context, PickedLocation(ll, addr));
          },
          child: const Text('Use these coordinates'),
        ),
      ],
    );
  }
}

// ================= Small Models & Enums =================

class Stop {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController addrCtrl = TextEditingController();
  LatLng? latLng;
  Stop({String label = ''}) {
    nameCtrl.text = label;
  }
}

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

enum RateMode { perDistance, flat }
