// lib/loads_tab.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'quick_load_screen.dart';
import 'widgets/main_menu_button.dart';

// inside AppBar
actions: [
  MainMenuButton(
    onSettingsApplied: (seedColor, companyName) {
      // (optional) live theme apply if you manage ThemeMode dynamically
    },
  ),
],

class LoadsTab extends StatefulWidget {
  const LoadsTab({super.key});
  @override
  State<LoadsTab> createState() => _LoadsTabState();
}

class _LoadsTabState extends State<LoadsTab> {
  final _search = TextEditingController();
  String _q = '';
  String _statusFilter =
      'All'; // All | Draft | Planned | En Route | Delivered | Canceled

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
    final q = FirebaseFirestore.instance
        .collection('loads')
        .orderBy('createdAt', descending: true)
        .limit(500) // plenty for UI
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loads'),
        actions: [
          IconButton(
            tooltip: 'New Load',
            icon: const Icon(Icons.add),
            onPressed: () async {
              final changed = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QuickLoadScreen()),
              );
              if (changed == true && mounted) setState(() {});
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText:
                        'Search by reference, client, shipper, or receiver',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Filter',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All')),
                    DropdownMenuItem(value: 'Draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'Planned', child: Text('Planned')),
                    DropdownMenuItem(
                        value: 'En Route', child: Text('En Route')),
                    DropdownMenuItem(
                        value: 'Delivered', child: Text('Delivered')),
                    DropdownMenuItem(
                        value: 'Canceled', child: Text('Canceled')),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: q,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  // Build list of rows with client-side filter + search
                  var docs = snap.data!.docs;

                  // Filter by status (client-side; simple and safe)
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
                      final ref = (m['loadNumber'] ??
                              m['shippingNumber'] ??
                              m['projectNumber'] ??
                              '')
                          .toString()
                          .toLowerCase();
                      final client =
                          (m['clientName'] ?? '').toString().toLowerCase();
                      final shipper =
                          (m['shipperName'] ?? '').toString().toLowerCase();
                      final receiver =
                          (m['receiverName'] ?? '').toString().toLowerCase();
                      final addr =
                          (m['deliveryAddress'] ?? '').toString().toLowerCase();
                      return [ref, client, shipper, receiver, addr]
                          .any((t) => t.contains(_q));
                    }).toList();
                  }

                  if (docs.isEmpty) {
                    return const Center(child: Text('No loads yet'));
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data();
                      final id = d.id;

                      final status = (m['status'] ?? 'Draft').toString();
                      final client = (m['clientName'] ?? '').toString();
                      final shipper = (m['shipperName'] ?? '').toString();
                      final receiver = (m['receiverName'] ?? '').toString();
                      final del = (m['deliveryAddress'] ?? '').toString();

                      final ref = (m['loadNumber'] ??
                              m['shippingNumber'] ??
                              m['projectNumber'] ??
                              '')
                          .toString();
                      final title = ref.isEmpty ? '(no reference)' : ref;

                      final subtitle =
                          _summaryLine(client, shipper, receiver, del);

                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(_statusLetter(status)),
                        ),
                        title: Text(title),
                        subtitle: subtitle.isEmpty
                            ? null
                            : Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _statusChip(status),
                            IconButton(
                              tooltip: 'Edit load',
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final changed = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          QuickLoadScreen(loadId: id)),
                                );
                                if (changed == true && mounted) setState(() {});
                              },
                            ),
                            IconButton(
                              tooltip: 'Open details',
                              icon: const Icon(Icons.chevron_right),
                              onPressed: () async {
                                final changed = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          QuickLoadScreen(loadId: id)),
                                );
                                if (changed == true && mounted) setState(() {});
                              },
                            ),
                          ],
                        ),
                        onTap: () async {
                          final changed = await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => QuickLoadScreen(loadId: id)),
                          );
                          if (changed == true && mounted) setState(() {});
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final changed = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QuickLoadScreen()),
          );
          if (changed == true && mounted) setState(() {});
        },
        icon: const Icon(Icons.add),
        label: const Text('New Load'),
      ),
    );
  }

  // ---------- helpers ----------

  String _summaryLine(
      String client, String shipper, String receiver, String del) {
    final parts = <String>[];
    if (client.isNotEmpty) parts.add(client);
    if (shipper.isNotEmpty) parts.add(shipper);
    if (receiver.isNotEmpty) parts.add(receiver);
    if (del.isNotEmpty) parts.add(del);
    return parts.join(' • ');
  }

  String _statusLetter(String status) {
    final s = status.trim().toLowerCase();
    if (s.startsWith('p')) return 'P'; // Planned
    if (s.startsWith('d')) return 'D'; // Draft / Delivered
    if (s.startsWith('e')) return 'E'; // En Route
    if (s.startsWith('c')) return 'C'; // Canceled
    return 'L';
  }

  Widget _statusChip(String status) {
    final s = status.trim().isEmpty ? 'Draft' : status.trim();
    return Chip(
      label: Text(s),
      backgroundColor: Colors.grey.shade200,
    );
  }
}
