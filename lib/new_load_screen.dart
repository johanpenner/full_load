import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'clients_all_in_one.dart';

// Canonical statuses
const kLoadStatuses = <String>[
  'Draft',
  'Assigned',
  'En route',
  'Loading',
  'Delivered',
  'Cancelled'
];

class ClientOpt {
  final String id;
  final String name;
  ClientOpt({required this.id, required this.name});
}

class Pickup {
  String? shipperId;
  String? receiverId;
  DateTime? pickupAt;
  DateTime? deliverAt;
  Pickup();
}

class NewLoadScreen extends StatefulWidget {
  const NewLoadScreen({super.key});

  @override
  State<NewLoadScreen> createState() => _NewLoadScreenState();
}

class _NewLoadScreenState extends State<NewLoadScreen> {
  String? _clientId;
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<Pickup> _pickups = [Pickup()];

  String _status = 'Draft';

  List<ClientOpt> _clients = [];
  bool _loading = true;
  String? _error;

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

  Future<void> _fetchReferenceData() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('clients')
          .limit(200)
          .get();
      final list = qs.docs.map((d) {
        final m = d.data();
        final name = (m['displayName'] ?? m['name'] ?? m['title'] ?? 'Client')
            .toString();
        return ClientOpt(id: d.id, name: name);
      }).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() {
        _clients = list;
        _clientId ??= list.isNotEmpty ? list.first.id : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load clients: $e';
        _loading = false;
      });
    }
  }

  Widget _locLabel(String text, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          if (icon != null) Icon(icon, size: 18),
          if (icon != null) const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey)),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_clientId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a client')));
      return;
    }

    final payload = {
      'clientId': _clientId,
      'reference': _refCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
      'status': _status,
      'createdAt': FieldValue.serverTimestamp(),
      'pickups': _pickups
          .map((p) => {
                'shipperId': p.shipperId,
                'receiverId': p.receiverId,
                'pickupAt': p.pickupAt,
                'deliverAt': p.deliverAt,
              })
          .toList(),
    };

    try {
      await FirebaseFirestore.instance.collection('loads').add(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Load saved')));
      setState(() {
        _refCtrl.clear();
        _notesCtrl.clear();
        _status = 'Draft';
        _pickups
          ..clear()
          ..add(Pickup());
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Load'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _locLabel('Client', icon: Icons.business),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _clientId,
                    items: _clients
                        .map((c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _clientId = v),
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Add client',
                  icon: const Icon(Icons.person_add_alt_1),
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ClientEditScreen()),
                    );
                    if (result is Map && result['action'] == 'created') {
                      await _fetchReferenceData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Saved "${result['name']}"')),
                      );
                    }
                  },
                )
              ],
            ),
            _locLabel('Reference # (optional)', icon: Icons.numbers),
            TextField(
              controller: _refCtrl,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), hintText: 'BOL / Ref #'),
            ),
            _locLabel('Status', icon: Icons.flag),
            DropdownButtonFormField<String>(
              value: kLoadStatuses.contains(_status) ? _status : null, // guard
              items: kLoadStatuses
                  .toSet()
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? _status),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            _locLabel('Notes (optional)', icon: Icons.note_outlined),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Special instructions…'),
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
