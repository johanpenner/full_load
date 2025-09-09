<DOCUMENT filename="loads_tab.dart">
// lib/loads_tab.dart
// Loads tab: Streamed list with search/status filter, pagination, quick add/edit/update status.
// Updated: replace popup menu with bottom-sheet actions to avoid web hit-test issues.
// Merged: FAB from load_list_screen.dart for new load (points to NewLoadEntryScreen; role-gated).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'auth/roles.dart'; // RoleGate / AppPerm
import 'auth/current_user_role.dart'; // currentUserRole()
import 'util/utils.dart'; // fmtTs()
import 'load_editor.dart'; // opens editor
import 'update_load_status.dart'; // status updates
import 'new_load_entry.dart'; // For new load (consolidated)

class LoadsTab extends StatefulWidget {
  final String companyId; // Added for multi-tenant
  const LoadsTab({super.key, required this.companyId});

  @override
  State<LoadsTab> createState() => _LoadsTabState();
}

class _LoadsTabState extends State<LoadsTab> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all';
  DocumentSnapshot? _lastDoc;
  bool _loadingMore = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _loads = [];

  AppRole _currentRole = AppRole.viewer;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _searchController.addListener(
      () => setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      ),
    );
    _fetchLoads();
  }

  Future<void> _loadRole() async {
    try {
      _currentRole = await currentUserRole();
      if (mounted) setState(() {});
    } catch (e) {
      _currentRole = AppRole.viewer;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Role load failed: $e')));
      }
    }
  }

  Future<void> _fetchLoads({bool loadMore = false}) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('companies/${widget.companyId}/loads') // Updated for multi-tenant
          .orderBy('createdAt', descending: true)
          .limit(20);

      if (_statusFilter != 'all') {
        q = q.where('status', isEqualTo: _statusFilter);
      }
      if (loadMore && _lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }

      final snap = await q.get();
      if (loadMore) {
        _loads.addAll(snap.docs);
      } else {
        _loads = snap.docs;
      }
      if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Load fetch failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool get _canEdit =>
      _currentRole == AppRole.admin ||
      _currentRole == AppRole.manager ||
      _currentRole == AppRole.dispatcher;

  @override
  Widget build(BuildContext context) {
    final filtered = _loads.where((d) {
      final m = d.data();
      final hay = [
        (m['reference'] ?? '').toString(),
        (m['client'] ?? '').toString(),
        (m['status'] ?? '').toString(),
      ].join(' ').toLowerCase();
      return _searchQuery.isEmpty || hay.contains(_searchQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loads'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search reference, client',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _statusFilter,
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _statusFilter = v);
                      _fetchLoads();
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'planned', child: Text('Planned')),
                    DropdownMenuItem(value: 'assigned', child: Text('Assigned')),
                    DropdownMenuItem(value: 'enroute', child: Text('Enroute')),
                    DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
                    DropdownMenuItem(value: 'invoiced', child: Text('Invoiced')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchLoads(),
        child: ListView.builder(
          itemCount: filtered.length + 1, // +1 for load more
          itemBuilder: (context, i) {
            if (i == filtered.length) {
              return _loadingMore
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                      child: ElevatedButton(
                        onPressed: () => _fetchLoads(loadMore: true),
                        child: const Text('Load More'),
                      ),
                    );
            }
            final d = filtered[i];
            final m = d.data();
            final ref = (m['reference'] ?? d.id).toString();
            final client = (m['client'] ?? '').toString();
            final status = (m['status'] ?? 'draft').toString();
            final created = fmtTs(m['createdAt']);
            return ListTile(
              title: Text(ref),
              subtitle: Text('$client • $status • $created'),
              trailing: _canEdit
                  ? IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _showActions(d.id),
                    )
                  : null,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LoadEditor(loadId: d.id),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: _canEdit // Gate FAB by role
          ? FloatingActionButton.extended(
              onPressed: () async {
                final saved = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NewLoadEntryScreen(companyId: widget.companyId), // Updated to consolidated screen
                  ),
                );
                if (saved == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Load saved')),
                  );
                  _fetchLoads(); // Refresh list
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('New Load'),
            )
          : null,
    );
  }

  Future<void> _showActions(String loadId) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.flag),
              title: const Text('Update Status'),
              onTap: () => Navigator.pop(ctx, 'status'),
            ),
            if (_currentRole == AppRole.admin)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title:
                    const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );

    switch (result) {
      case 'edit':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => LoadEditor(loadId: loadId)),
        );
        if (mounted) _fetchLoads();
        break;
      case 'status':
        await updateLoadStatus(context, loadId, _currentRole.name);
        if (mounted) _fetchLoads();
        break;
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete load?'),
            content: const Text(
                'This cannot be undone. Are you sure you want to delete this load?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) {
          await FirebaseFirestore.instance
              .collection('companies/${widget.companyId}/loads') // Updated path
              .doc(loadId)
              .delete();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Load deleted')),
            );
            _fetchLoads();
          }
        }
        break;
      default:
        // dismissed
        break;
    }
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
</DOCUMENT>