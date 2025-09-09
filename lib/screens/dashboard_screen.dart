// lib/screens/dashboard_screen.dart
// Updated Dashboard: Now a dynamic summary with Firestore streams for key metrics (active loads, available drivers, trucks in shop).
// Role-gated sections (e.g., edit links for dispatchers/admins), loading/error UI, responsive cards.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/roles.dart'; // For RoleGate and AppPerm
import '../auth/current_user_role.dart'; // For currentUserRole

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AppRole _role = AppRole.viewer;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    _role = await currentUserRole();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _metricCard(
                    title: 'Active Loads',
                    icon: Icons.local_shipping,
                    stream: FirebaseFirestore.instance
                        .collection('loads')
                        .where('status',
                            whereIn: ['assigned', 'enroute']).snapshots(),
                    builder: (count) => Text('$count'),
                    onTap: () =>
                        Navigator.pushNamed(context, '/loads'), // Example route
                  ),
                  _metricCard(
                    title: 'Available Drivers',
                    icon: Icons.people,
                    stream: FirebaseFirestore.instance
                        .collection('employees')
                        .where('roles', arrayContains: 'Driver')
                        .where('isActive', isEqualTo: true)
                        .snapshots(),
                    builder: (count) => Text('$count'),
                    onTap: () => Navigator.pushNamed(context, '/employees'),
                  ),
                  RoleGate(
                    role: _role,
                    perm: AppPerm.viewMechanic,
                    child: _metricCard(
                      title: 'Trucks in Shop',
                      icon: Icons.build,
                      stream: FirebaseFirestore.instance
                          .collection('trucks')
                          .where('status', isEqualTo: 'maintenance')
                          .snapshots(),
                      builder: (count) => Text('$count'),
                      onTap: () => Navigator.pushNamed(context, '/trucks'),
                    ),
                  ),
                  _metricCard(
                    title: 'Pending Invoices',
                    icon: Icons.receipt,
                    stream: FirebaseFirestore.instance
                        .collection('invoices')
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                    builder: (count) => Text('$count'),
                    onTap: () => Navigator.pushNamed(context, '/accounting'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required IconData icon,
    required Stream<QuerySnapshot> stream,
    required Widget Function(int count) builder,
    VoidCallback? onTap,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return _errorCard(title, icon);
        if (!snap.hasData) return _loadingCard(title, icon);
        final count = snap.data!.docs.length;
        return Card(
          elevation: 4,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 48),
                  const SizedBox(height: 8),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  builder(count),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _loadingCard(String title, IconData icon) => Card(
        child: const Center(child: CircularProgressIndicator()),
      );

  Widget _errorCard(String title, IconData icon) => Card(
        child: const Center(child: Icon(Icons.error, color: Colors.red)),
      );
}
