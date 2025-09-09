// lib/screens/drivers_screen.dart
// Updated Drivers screen: List with search/filter (availability/status), add/edit (role-gated), tap to timeline/detail.
// Streams from Firestore 'employees' where roles include 'Driver'.
// Integrates with driver_timeline_screen/employee_detail_screen.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../employees_tab.dart'; // For Employee model
import '../driver_timeline_screen.dart'; // For timeline
import '../employee_detail_screen.dart'; // For details/edit
import '../auth/roles.dart'; // For RoleGate/AppPerm
import '../auth/current_user_role.dart'; // For role

class DriversScreen extends StatefulWidget {
  const DriversScreen({super.key});
  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  final _search = TextEditingController();
  String _q = '';
  String _filter = 'all'; // all | available | busy | off
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
    final baseQuery = FirebaseFirestore.instance
        .collection('employees')
        .where('roles', arrayContains: 'Driver')
        .orderBy('nameLower')
        .limit(500);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drivers'),
        actions: [
          RoleGate(
            role: _role,
            perm: AppPerm.editDrivers, // Add to roles.dart if needed
            child: IconButton(
              tooltip: 'New driver',
              icon: const Icon(Icons.add),
              onPressed: () async {
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const EmployeeEditScreen()), // Reuse from employees_tab
                );
                if (res is Map && res['action'] != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text('${res['action']} driver: ${res['name']}')));
                }
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name, alias, email, phone',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _filter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(
                        value: 'available', child: Text('Available')),
                    DropdownMenuItem(value: 'busy', child: Text('Busy')),
                    DropdownMenuItem(value: 'off', child: Text('Off/Leave')),
                  ],
                  onChanged: (v) => setState(() => _filter = v ?? 'all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: baseQuery.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var drivers = snap.data!.docs.map(Employee.fromDoc).toList();

                  // Client-side filter (for status/availability—add 'status' field to Employee if needed)
                  drivers = drivers.where((d) {
                    switch (_filter) {
                      case 'available':
                        return d.isActive &&
                            d.nextTimeOffStart == null; // Example logic
                      case 'busy':
                        return d.isActive &&
                            d.productivityScore > 0; // Example (active loads)
                      case 'off':
                        return !d.isActive || d.nextTimeOffStart != null;
                      default:
                        return true;
                    }
                  }).toList();

                  // Search
                  if (_q.isNotEmpty) {
                    drivers = drivers.where((d) {
                      final hay = [
                        '${d.firstName} ${d.lastName}',
                        d.alias,
                        d.email,
                        d.mobilePhone,
                        d.workPhone,
                      ].join(' ').toLowerCase();
                      return hay.contains(_q);
                    }).toList();
                  }

                  if (drivers.isEmpty) {
                    return const Center(child: Text('No drivers found.'));
                  }

                  return ListView.separated(
                    itemCount: drivers.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final d = drivers[i];
                      final name = d.aliasEnabled && d.alias.isNotEmpty
                          ? d.alias
                          : '${d.firstName} ${d.lastName}';
                      final subtitle = '${d.email} • ${d.mobilePhone}';
                      final timeOffPill = timeOffPillFromEmployee(
                          d); // From utils or employees_tab
                      return ListTile(
                        leading:
                            CircleAvatar(child: Text(name[0].toUpperCase())),
                        title: Row(
                          children: [
                            Expanded(child: Text(name)),
                            if (timeOffPill != null) timeOffPill,
                          ],
                        ),
                        subtitle: Text(subtitle),
                        trailing: IconButton(
                          icon: const Icon(Icons.timeline),
                          tooltip: 'Timeline',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  DriverTimelineScreen(driverId: d.id),
                            ),
                          ),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                EmployeeDetailScreen(employeeId: d.id),
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
      ),
    );
  }
}
