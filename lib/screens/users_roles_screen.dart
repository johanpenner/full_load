import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/roles.dart';

class UsersRolesScreen extends StatelessWidget {
  const UsersRolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('email')
        .limit(500)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Users & Roles')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No users'));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = docs[i];
              final m = d.data();
              final name = (m['name'] ?? '').toString();
              final email = (m['email'] ?? '').toString();
              final phone = (m['phone'] ?? '').toString();
              final role = roleFromString(m['role']?.toString());

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(name.isEmpty ? '(no name)' : name),
                subtitle:
                    Text([email, phone].where((s) => s.isNotEmpty).join(' • ')),
                trailing: _RoleDropdown(
                  current: role,
                  onChanged: (newRole) async {
                    await d.reference
                        .update({'role': roleLabel(newRole).toLowerCase()});
                  },
                ),
              );
            },
          );
        },
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
