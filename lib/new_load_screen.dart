import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Simple option models
class ClientOpt {
  final String id;
  final String name;
  ClientOpt({required this.id, required this.name});
}

class PartyOpt {
  final String id;
  final String name;
  PartyOpt({required this.id, required this.name});
}

class Pickup {
  String? shipperId;
  String? receiverId;
  DateTime? pickupAt;
  DateTime? deliverAt;

  Pickup({
    this.shipperId,
    this.receiverId,
    this.pickupAt,
    this.deliverAt,
  });
}

class NewLoadScreen extends StatefulWidget {
  const NewLoadScreen({super.key});

  @override
  State<NewLoadScreen> createState() => _NewLoadScreenState();
}

class _NewLoadScreenState extends State<NewLoadScreen> {
  // Dev: UI always enabled; Firestore rules still control server writes
  static const bool kDevAllowAllWrites = true;

  // Reference data
  List<ClientOpt> _clients = [];
  List<PartyOpt> _shippers = [];
  List<PartyOpt> _receivers = [];

  bool _loadingRefs = true;
  String? _loadError;

  // Form fields
  String? _clientId;
  final List<Pickup> _pickups = [Pickup()];

  // Misc inputs
  final TextEditingController _refCtrl = TextEditingController(); // reference #
  final TextEditingController _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchReferenceData();
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // === Helper for consistent small section labels ===
  Widget _locLabel(String text, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          if (icon != null) Icon(icon, size: 18),
          if (icon != null) const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchReferenceData() async {
    try {
      final fs = FirebaseFirestore.instance;

      Future<List<ClientOpt>> loadClients() async {
        final qs = await fs.collection('clients').limit(200).get();
        return qs.docs
            .map((d) => ClientOpt(
                  id: d.id,
                  name: (d.data()['name'] ?? d.data()['title'] ?? 'Client')
                      .toString(),
                ))
            .toList()
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }

      Future<List<PartyOpt>> loadParties(String col) async {
        final qs = await fs.collection(col).limit(500).get();
        return qs.docs
            .map((d) => PartyOpt(
                  id: d.id,
                  name: (d.data()['name'] ?? d.data()['label'] ?? 'Unknown')
                      .toString(),
                ))
            .toList()
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }

      final results = await Future.wait([
        loadClients(),
        loadParties('shippers'),
        loadParties('receivers'),
      ]);

      setState(() {
        _clients = results[0] as List<ClientOpt>;
        _shippers = results[1] as List<PartyOpt>;
        _receivers = results[2] as List<PartyOpt>;
        _loadingRefs = false;
        _loadError = null;
        // auto-select first client if none chosen
        _clientId ??= _clients.isNotEmpty ? _clients.first.id : null;
      });
    } catch (e) {
      setState(() {
        _loadingRefs = false;
        _loadError = 'Failed to load reference data: $e';
      });
    }
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final base = initial ?? now;

    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d == null) return null;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null) return DateTime(d.year, d.month, d.day);

    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    // minimal validation
    if (_clientId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a client')),
      );
      return;
    }
    if (_pickups.any((p) => p.shipperId == null || p.receiverId == null)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Select shipper and receiver for each pickup')),
      );
      return;
    }

    try {
      final payload = {
        'clientId': _clientId,
        'reference': _refCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'pickups': _pickups
            .map((p) => {
                  'shipperId': p.shipperId,
                  'receiverId': p.receiverId,
                  'pickupAt': p.pickupAt,
                  'deliverAt': p.deliverAt,
                })
            .toList(),
        'status': 'Draft',
      };

      if (kDevAllowAllWrites) {
        await FirebaseFirestore.instance.collection('loads').add(payload);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load saved')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  Widget _pickupCard(int idx) {
    final p = _pickups[idx];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text('Pickup ${idx + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_pickups.length > 1)
                  IconButton(
                    tooltip: 'Remove pickup',
                    icon: const Icon(Icons.delete_forever),
                    onPressed: () => setState(() => _pickups.removeAt(idx)),
                  ),
              ],
            ),
            _locLabel('Shipper', icon: Icons.factory_outlined),
            DropdownButtonFormField<String>(
              value: p.shipperId,
              items: _shippers
                  .map(
                      (s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                  .toList(),
              onChanged: (v) => setState(() => p.shipperId = v),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            _locLabel('Receiver', icon: Icons.local_shipping_outlined),
            DropdownButtonFormField<String>(
              value: p.receiverId,
              items: _receivers
                  .map(
                      (r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
                  .toList(),
              onChanged: (v) => setState(() => p.receiverId = v),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final dt = await _pickDateTime(p.pickupAt);
                      if (dt != null) setState(() => p.pickupAt = dt);
                    },
                    child: Text(
                      p.pickupAt == null
                          ? 'Set pickup time'
                          : 'Pickup: ${p.pickupAt!.toLocal()}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final dt = await _pickDateTime(p.deliverAt);
                      if (dt != null) setState(() => p.deliverAt = dt);
                    },
                    child: Text(
                      p.deliverAt == null
                          ? 'Set delivery time'
                          : 'Delivery: ${p.deliverAt!.toLocal()}',
                      textAlign: TextAlign.center,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Load'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
            style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onPrimary),
          ),
        ],
      ),
      body: _loadingRefs
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Text(_loadError!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _locLabel('Client', icon: Icons.business),
                      DropdownButtonFormField<String>(
                        value: _clientId,
                        items: _clients
                            .map((c) => DropdownMenuItem(
                                value: c.id, child: Text(c.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _clientId = v),
                        decoration:
                            const InputDecoration(border: OutlineInputBorder()),
                      ),
                      _locLabel('Reference # (optional)', icon: Icons.numbers),
                      TextField(
                        controller: _refCtrl,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Enter your reference / BOL #',
                        ),
                      ),
                      _locLabel('Pickups & Drops', icon: Icons.alt_route),
                      for (int i = 0; i < _pickups.length; i++) _pickupCard(i),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _pickups.add(Pickup())),
                          icon: const Icon(Icons.add),
                          label: const Text('Add another pickup'),
                        ),
                      ),
                      _locLabel('Notes (optional)', icon: Icons.note_outlined),
                      TextField(
                        controller: _notesCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Special instructions…',
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save),
                        label: const Text('Save Load'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
