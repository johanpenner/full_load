// lib/routing/role_router.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../shell/home_shell.dart';
import '../dispatcher_dashboard.dart' show DispatcherDashboard;
import '../loads_tab.dart' show LoadsTab;
import '../employees_tab.dart' show EmployeesTab;
import '../clients_all_in_one.dart' show ClientListScreen;
import '../shippers_tab.dart' show ShippersTab;
import '../receivers_tab.dart' show ReceiversTab;
import '../driver_upload_screen.dart' show DriverUploadScreen;
import '../screens/settings_screen.dart' show SettingsScreen;
import '../load_editor.dart' show LoadEditor; // editor we open from FAB

class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _Centered('Not signed in');
    }

    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _error('Connecting to database…\n${snap.error}');
        }
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final data = snap.data!.data() ?? const <String, dynamic>{};
        final role = (data['role'] ?? 'dispatcher') as String;

        switch (role) {
          case 'admin':
          case 'dispatcher':
            return _adminDispatcherShell(
              context,
              title: role == 'admin'
                  ? 'Full Load — Admin'
                  : 'Full Load — Dispatcher',
            );

          case 'driver':
            return const _Centered('Driver app view goes here');

          default:
            return const _Centered('Unknown role. Contact admin.');
        }
      },
    );
  }

  Widget _adminDispatcherShell(BuildContext context, {required String title}) {
    final tabs = <NavTab>[
      NavTab(
          label: 'Home',
          icon: Icons.home_outlined,
          page: DispatcherDashboard()),
      NavTab(
          label: 'Loads',
          icon: Icons.local_shipping_outlined,
          page: const LoadsTab()),
      const NavTab(
          label: 'Employees', icon: Icons.badge_outlined, page: EmployeesTab()),
      const NavTab(
          label: 'Clients',
          icon: Icons.apartment_outlined,
          page: ClientListScreen()),
      const NavTab(
          label: 'Shippers',
          icon: Icons.storefront_outlined,
          page: ShippersTab()),
      const NavTab(
          label: 'Receivers',
          icon: Icons.inventory_2_outlined,
          page: ReceiversTab()),
      const NavTab(
          label: 'Docs',
          icon: Icons.folder_open_outlined,
          page: DriverUploadScreen()),
      const NavTab(
          label: 'Settings',
          icon: Icons.settings_outlined,
          page: SettingsScreen()),
    ];

    return HomeShell(
      title: title,
      tabs: tabs,
      // Show the "New Load" FAB on Home (0) and Loads (1)
      fabBuilder: (ctx, index) {
        if (index == 0 || index == 1) {
          return FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(ctx).push(
                MaterialPageRoute(builder: (_) => const LoadEditor()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('New Load'),
          );
        }
        return null;
      },
    );
  }

  Widget _error(String text) => Scaffold(
        appBar: AppBar(title: const Text('Connecting…')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(text, textAlign: TextAlign.center),
          ),
        ),
      );
}

class _Centered extends StatelessWidget {
  final String text;
  const _Centered(this.text);
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(text)));
}
