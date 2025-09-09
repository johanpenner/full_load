// lib/load_editor.dart
// Clean Load Editor: reference + client + stops + BOL + Cross-border + assignment + notes.
// Compatible with LoadsTab (expects fields: reference, status, client, createdAt/updatedAt).
// Read-only supported via widget.readOnly.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LoadEditor extends StatefulWidget {
  final String? loadId;
  final bool readOnly;
  const LoadEditor({super.key, this.loadId, this.readOnly = false});

  @override
  State<LoadEditor> createState() => _LoadEditorState();
}

/// ------ Simple models ------

enum _StopKind { pickup, delivery }

class _Stop {
  _Stop({
    this.kind = _StopKind.pickup,
    String? name,
    String? address,
    this.apptStart,
    this.apptEnd,
    this.serviceMinutes = 30,
  })  : nameCtrl = TextEditingController(text: name ?? ''),
        addrCtrl = TextEditingController(text: address ?? '');

  _StopKind kind;
  final TextEditingController nameCtrl;
  final TextEditingController addrCtrl;
  DateTime? apptStart;
  DateTime? apptEnd;
  int serviceMinutes;

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'name': nameCtrl.text.trim(),
        'address': addrCtrl.text.trim(),
        'apptStart': apptStart,
        'apptEnd': apptEnd,
        'serviceMinutes': serviceMinutes,
      };

  static _Stop fromMap(Map<String, dynamic> m) {
    return _Stop(
      kind: (m['kind'] == 'delivery') ? _StopKind.delivery : _StopKind.pickup,
      name: (m['name'] ?? '').toString(),
      address: (m['address'] ?? '').toString(),
      apptStart: (m['apptStart'] is Timestamp)
          ? (m['apptStart'] as Timestamp).toDate()
          : (m['apptStart'] is DateTime ? m['apptStart'] as DateTime : null),
      apptEnd: (m['apptEnd'] is Timestamp)
          ? (m['apptEnd'] as Timestamp).toDate()
          : (m['apptEnd'] is DateTime ? m['apptEnd'] as DateTime : null),
      serviceMinutes: (m['serviceMinutes'] is num)
          ? (m['serviceMinutes'] as num).toInt()
          : 30,
    );
  }
}

/// Bill of Lading line (✅ default constructor exists)
class _BolLine {
  _BolLine({
    int? qty,
    String? description,
    double? weight,
    String? weightUnit, // 'kg' | 'lb'
    double? len,
    double? width,
    double? height,
    String? dimUnit, // 'cm' | 'in'
  })  : qtyCtrl = TextEditingController(text: (qty ?? 1).toString()),
        descCtrl = TextEditingController(text: description ?? ''),
        weightCtrl = TextEditingController(
            text: weight == null ? '' : weight.toStringAsFixed(2)),
        weightUnit = weightUnit ?? 'lb',
        lenCtrl = TextEditingController(
            text: len == null ? '' : len.toStringAsFixed(1)),
        widCtrl = TextEditingController(
            text: width == null ? '' : width.toStringAsFixed(1)),
        heiCtrl = TextEditingController(
            text: height == null ? '' : height.toStringAsFixed(1)),
        dimUnit = dimUnit ?? 'in';

  final TextEditingController qtyCtrl;
  final TextEditingController descCtrl;
  final TextEditingController weightCtrl;
  String weightUnit;
  final TextEditingController lenCtrl;
  final TextEditingController widCtrl;
  final TextEditingController heiCtrl;
  String dimUnit;

  Map<String, dynamic> toMap() => {
        'qty': int.tryParse(qtyCtrl.text.trim()) ?? 0,
        'description': descCtrl.text.trim(),
        'weight': double.tryParse(weightCtrl.text.trim()) ?? 0.0,
        'weightUnit': weightUnit,
        'length': double.tryParse(lenCtrl.text.trim()),
        'width': double.tryParse(widCtrl.text.trim()),
        'height': double.tryParse(heiCtrl.text.trim()),
        'dimUnit': dimUnit,
      };

  factory _BolLine.fromMap(Map m) => _BolLine(
        qty: (m['qty'] is num) ? (m['qty'] as num).toInt() : null,
        description: (m['description'] ?? '').toString(),
        weight: (m['weight'] is num) ? (m['weight'] as num).toDouble() : null,
        weightUnit: (m['weightUnit'] ?? 'lb').toString(),
        len: (m['length'] is num) ? (m['length'] as num).toDouble() : null,
        width: (m['width'] is num) ? (m['width'] as num).toDouble() : null,
        height: (m['height'] is num) ? (m['height'] as num).toDouble() : null,
        dimUnit: (m['dimUnit'] ?? 'in').toString(),
      );
}

/// Cross-border fields stored behind a toggle
class _CrossBorder {
  bool enabled;
  final TextEditingController brokerName;
  final TextEditingController brokerPhone;
  final TextEditingController hsCode;
  final TextEditingController portOfEntry;
  final TextEditingController instructions;

  _CrossBorder({
    this.enabled = false,
    String brokerName = '',
    String brokerPhone = '',
    String hsCode = '',
    String portOfEntry = '',
    String instructions = '',
  })  : brokerName = TextEditingController(text: brokerName),
        brokerPhone = TextEditingController(text: brokerPhone),
        hsCode = TextEditingController(text: hsCode),
        portOfEntry = TextEditingController(text: portOfEntry),
        instructions = TextEditingController(text: instructions);

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'brokerName': brokerName.text.trim(),
        'brokerPhone': brokerPhone.text.trim(),
        'hsCode': hsCode.text.trim(),
        'portOfEntry': portOfEntry.text.trim(),
        'instructions': instructions.text.trim(),
      };

  static _CrossBorder fromMap(Map<String, dynamic>? m) => _CrossBorder(
        enabled: (m?['enabled'] ?? false) as bool,
        brokerName: (m?['brokerName'] ?? '').toString(),
        brokerPhone: (m?['brokerPhone'] ?? '').toString(),
        hsCode: (m?['hsCode'] ?? '').toString(),
        portOfEntry: (m?['portOfEntry'] ?? '').toString(),
        instructions: (m?['instructions'] ?? '').toString(),
      );
}

/// ------ Screen ------

class _LoadEditorState extends State<LoadEditor> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _saving = false;

  // Header
  final _reference = TextEditingController();
  final _client = TextEditingController();
  String _status =
      'draft'; // draft | planned | assigned | enroute | delivered | invoiced

  // Stops
  final List<_Stop> _stops = <_Stop>[
    _Stop(kind: _StopKind.pickup),
    _Stop(kind: _StopKind.delivery),
  ];

  // BOL
  final List<_BolLine> _bol = <_BolLine>[];

  // Cross border
  _CrossBorder _cb = _CrossBorder();

  // Assignment & equipment (simple text for now)
  final _driver = TextEditingController();
  final _truck = TextEditingController();
  final _trailer = TextEditingController();

  // Notes
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.loadId != null) {
      _loadExisting();
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _client.dispose();
    _driver.dispose();
    _truck.dispose();
    _trailer.dispose();
    _notes.dispose();
    for (final s in _stops) {
      s.nameCtrl.dispose();
      s.addrCtrl.dispose();
    }
    for (final b in _bol) {
      b.qtyCtrl.dispose();
      b.descCtrl.dispose();
      b.weightCtrl.dispose();
      b.lenCtrl.dispose();
      b.widCtrl.dispose();
      b.heiCtrl.dispose();
    }
    _cb.brokerName.dispose();
    _cb.brokerPhone.dispose();
    _cb.hsCode.dispose();
    _cb.portOfEntry.dispose();
    _cb.instructions.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
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

      _reference.text = (m['reference'] ?? '').toString();
      _client.text = (m['client'] ?? '').toString();
      _status = (m['status'] ?? 'draft').toString();

      // stops
      _stops.clear();
      if (m['stops'] is List) {
        for (final x in (m['stops'] as List)) {
          if (x is Map<String, dynamic>) {
            _stops.add(_Stop.fromMap(x));
          }
        }
      }
      if (_stops.isEmpty) {
        _stops.addAll(
            [_Stop(kind: _StopKind.pickup), _Stop(kind: _StopKind.delivery)]);
      }

      // BOL
      _bol.clear();
      if (m['bol'] is List) {
        for (final x in (m['bol'] as List)) {
          if (x is Map) _bol.add(_BolLine.fromMap(x.cast<String, dynamic>()));
        }
      }

      // cross-border
      _cb = _CrossBorder.fromMap(
        (m['crossBorder'] is Map<String, dynamic>)
            ? m['crossBorder'] as Map<String, dynamic>
            : null,
      );

      // assignment/equipment
      _driver.text = (m['driver'] ?? '').toString();
      _truck.text = (m['truck'] ?? '').toString();
      _trailer.text = (m['trailer'] ?? '').toString();

      _notes.text = (m['notes'] ?? '').toString();
    } catch (e) {
      _snack('Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_stops.isEmpty) {
      _snack('Add at least one stop.');
      return;
    }
    setState(() => _saving = true);
    try {
      final col = FirebaseFirestore.instance.collection('loads');

      // Build map
      final nowRef = _reference.text.trim().isEmpty
          ? 'LD-${DateTime.now().millisecondsSinceEpoch}'
          : _reference.text.trim();

      final data = <String, dynamic>{
        'reference': nowRef,
        'client': _client.text.trim(),
        'status': _status,
        'stops': _stops.map((s) => s.toMap()).toList(),
        'bol': _bol.map((b) => b.toMap()).toList(),
        'crossBorder': _cb.toMap(),
        'driver': _driver.text.trim(),
        'truck': _truck.text.trim(),
        'trailer': _trailer.text.trim(),
        'notes': _notes.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (widget.loadId == null) 'createdAt': FieldValue.serverTimestamp(),
      };

      if (widget.loadId == null) {
        await col.add(data);
        if (!mounted) return;
        Navigator.pop(context, {'action': 'created', 'name': nowRef});
      } else {
        await col.doc(widget.loadId).set(data, SetOptions(merge: true));
        if (!mounted) return;
        Navigator.pop(context, {'action': 'updated', 'name': nowRef});
      }
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.loadId == null
            ? 'New Load'
            : (ro ? 'View Load' : 'Edit Load')),
        actions: [
          if (!ro)
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _headerCard(ro),
                    const SizedBox(height: 12),
                    _stopsCard(ro),
                    const SizedBox(height: 12),
                    _bolCard(ro),
                    const SizedBox(height: 12),
                    _crossBorderCard(ro),
                    const SizedBox(height: 12),
                    _assignCard(ro),
                    const SizedBox(height: 12),
                    _notesCard(ro),
                    const SizedBox(height: 24),
                    if (!ro)
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save),
                        label: Text(_saving ? 'Saving…' : 'Save Load'),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _headerCard(bool ro) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Header', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _reference,
                    enabled: !ro,
                    decoration: const InputDecoration(
                      labelText: 'Reference (e.g., load # / PO)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _client,
                    enabled: !ro,
                    decoration: const InputDecoration(
                      labelText: 'Client',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      'draft',
                      'planned',
                      'assigned',
                      'enroute',
                      'delivered',
                      'invoiced',
                    ]
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(_cap(s))))
                        .toList(),
                    onChanged: ro
                        ? null
                        : (v) => setState(() => _status = v ?? 'draft'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stopsCard(bool ro) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Text('Stops (sequence)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (!ro) ...[
                  TextButton.icon(
                    onPressed: () => setState(
                        () => _stops.add(_Stop(kind: _StopKind.pickup))),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Pickup'),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    onPressed: () => setState(
                        () => _stops.add(_Stop(kind: _StopKind.delivery))),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Delivery'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (_stops.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('No stops yet. Add a pickup or delivery.'),
              ),
            for (int i = 0; i < _stops.length; i++) _stopRow(i, ro),
          ],
        ),
      ),
    );
  }

  Widget _stopRow(int i, bool ro) {
    final s = _stops[i];
    final title = s.kind == _StopKind.pickup ? 'Pickup' : 'Delivery';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Chip(label: Text(title)),
                const Spacer(),
                if (!ro) ...[
                  IconButton(
                    tooltip: 'Move up',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: i == 0
                        ? null
                        : () => setState(() {
                              final x = _stops.removeAt(i);
                              _stops.insert(i - 1, x);
                            }),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: i == _stops.length - 1
                        ? null
                        : () => setState(() {
                              final x = _stops.removeAt(i);
                              _stops.insert(i + 1, x);
                            }),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _stops.removeAt(i)),
                  ),
                ],
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: s.nameCtrl,
                    enabled: !ro,
                    decoration: InputDecoration(
                      labelText: '$title (Company)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: s.addrCtrl,
                    enabled: !ro,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text(
                      s.apptStart == null
                          ? 'Appt start (optional)'
                          : 'Start: ${s.apptStart!.toString().substring(0, 16)}',
                    ),
                    onPressed: ro
                        ? null
                        : () async {
                            final dt = await _pickDateTime(
                                context, s.apptStart ?? DateTime.now());
                            if (dt != null) setState(() => s.apptStart = dt);
                          },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.event_available),
                    label: Text(
                      s.apptEnd == null
                          ? 'Appt end (optional)'
                          : 'End: ${s.apptEnd!.toString().substring(0, 16)}',
                    ),
                    onPressed: ro
                        ? null
                        : () async {
                            final dt = await _pickDateTime(
                                context, s.apptEnd ?? DateTime.now());
                            if (dt != null) setState(() => s.apptEnd = dt);
                          },
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    enabled: !ro,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: false),
                    decoration: const InputDecoration(
                      labelText: 'Service (min)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    initialValue: s.serviceMinutes.toString(),
                    onChanged: (t) =>
                        s.serviceMinutes = int.tryParse(t.trim()) ?? 30,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bolCard(bool ro) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Text('BOL (Bill of Lading)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (!ro)
                  TextButton.icon(
                    onPressed: () => setState(() => _bol.add(_BolLine())),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Line'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_bol.isEmpty)
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No BOL lines. Add a line.')),
            for (int i = 0; i < _bol.length; i++)
              _BolLineRow(
                line: _bol[i],
                readOnly: ro,
                onRemove: ro
                    ? null
                    : () => setState(() {
                          _bol.removeAt(i);
                        }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _crossBorderCard(bool ro) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SwitchListTile(
              value: _cb.enabled,
              onChanged: ro ? null : (v) => setState(() => _cb.enabled = v),
              title: const Text('Cross-border'),
            ),
            if (_cb.enabled) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cb.brokerName,
                      enabled: !ro,
                      decoration: const InputDecoration(
                        labelText: 'Broker Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _cb.brokerPhone,
                      enabled: !ro,
                      decoration: const InputDecoration(
                        labelText: 'Broker Phone',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cb.hsCode,
                      enabled: !ro,
                      decoration: const InputDecoration(
                        labelText: 'HS Code(s)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _cb.portOfEntry,
                      enabled: !ro,
                      decoration: const InputDecoration(
                        labelText: 'Port of Entry',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _cb.instructions,
                enabled: !ro,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Customs Instructions / Notes',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _assignCard(bool ro) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assignment & Equipment',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _driver,
                    enabled: !ro,
                    decoration: const InputDecoration(
                      labelText: 'Driver (optional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _truck,
                    enabled: !ro,
                    decoration: const InputDecoration(
                      labelText: 'Truck # (optional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _trailer,
                    enabled: !ro,
                    decoration: const InputDecoration(
                      labelText: 'Trailer # (optional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _notesCard(bool ro) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _notes,
          enabled: !ro,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  // ------- helpers -------

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Row widget for a single BOL line
class _BolLineRow extends StatelessWidget {
  final _BolLine line;
  final bool readOnly;
  final VoidCallback? onRemove;

  const _BolLineRow({
    required this.line,
    required this.readOnly,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: line.qtyCtrl,
                    enabled: !readOnly,
                    keyboardType: const TextInputType.numberWithOptions(),
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: line.descCtrl,
                    enabled: !readOnly,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: line.weightCtrl,
                    enabled: !readOnly,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Weight',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    initialValue: line.weightUnit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'lb', child: Text('lb')),
                      DropdownMenuItem(value: 'kg', child: Text('kg')),
                    ],
                    onChanged:
                        readOnly ? null : (v) => line.weightUnit = v ?? 'lb',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: line.lenCtrl,
                          enabled: !readOnly,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'L',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: line.widCtrl,
                          enabled: !readOnly,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'W',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: line.heiCtrl,
                          enabled: !readOnly,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'H',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 110,
                        child: DropdownButtonFormField<String>(
                          initialValue: line.dimUnit,
                          decoration: const InputDecoration(
                            labelText: 'dim',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'in', child: Text('in')),
                            DropdownMenuItem(value: 'cm', child: Text('cm')),
                          ],
                          onChanged:
                              readOnly ? null : (v) => line.dimUnit = v ?? 'in',
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onRemove,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ====== Shared date/time picker ======

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final d = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  if (d == null) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (t == null) return DateTime(d.year, d.month, d.day);
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}
