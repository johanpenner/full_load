// lib/screens/users_roles_screen.dart
// Updated Users & Roles screen: Streamed list with search/email/phone, role dropdown (gated for admins), confirm changes, error/loading UI, realtime updates.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/roles.dart'; // For AppRole, roleFromString, roleLabel
import '../auth/current_user_role.dart'; // For currentUserRole (to gate edits)
import '../util/utils.dart'; // For _oneLine if needed

class UsersRolesScreen extends StatefulWidget {
  const UsersRolesScreen({super.key});
  @override
  State<UsersRolesScreen> createState() => _UsersRolesScreenState();
}

class _UsersRolesScreenState extends State<UsersRolesScreen> {
  final _search = TextEditingController();
  String _q = '';
  AppRole _role = AppRole.viewer;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _search.addListener(
        () => setState(() => _q = _search.text.trim().toLowerCase()));
  }

  Future<void> _loadRole() async {
    _role = await currentUserRole();
    setState(() {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('email')
        .limit(500)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Users & Roles')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, email, phone',
                border: OutlineInputBorder(),
              ),
            ),
          ),
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
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('No users'));

                var filtered = docs;
                if (_q.isNotEmpty) {
                  filtered = docs.where((d) {
                    final m = d.data();
                    final hay = [
                      (m['name'] ?? '').toString(),
                      (m['email'] ?? '').toString(),
                      (m['phone'] ?? '').toString(),
                    ].join(' ').toLowerCase();
                    return hay.contains(_q);
                  }).toList();
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = filtered[i];
                    final m = d.data();
                    final name = (m['name'] ?? '').toString();
                    final email = (m['email'] ?? '').toString();
                    final phone = (m['phone'] ?? '').toString();
                    final role = roleFromString(m['role']?.toString());

                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(name.isEmpty ? '(no name)' : name),
                      subtitle: Text(_oneLine('$email • $phone')),
                      trailing: RoleGate(
                        role: _role,
                        perm:
                            AppPerm.manageUsers, // Only admins can change roles
                        child: _RoleDropdown(
                          current: role,
                          onChanged: (newRole) async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Change Role?'),
                                content: Text(
                                    'Set role to ${roleLabel(newRole)} for $name?'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Confirm')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await d.reference.update(
                                  {'role': roleLabel(newRole).toLowerCase()});
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(
                                      'Role updated to ${roleLabel(newRole)}')));
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  final AppRole current;
  final ValueChanged<AppRole> onChanged;
  const _RoleDropdown({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final roles = AppRole.values;
    return DropdownButton<AppRole>(
      value: current,
      onChanged: (r) => r != null ? onChanged(r) : null,
      items: roles.map((r) {
        return DropdownMenuItem(
          value: r,
          child: Text(roleLabel(r)),
        );
      }).toList(),
    );
  }
}

String _oneLine(String s) =>
    s.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
