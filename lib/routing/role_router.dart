// lib/routing/role_router.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../shell/home_shell.dart';

// ===== Your real screens =====
// Dashboard / Dispatcher
import '../dispatcher_dashboard.dart'; // -> class DispatcherDashboard
// Loads
import '../loads_tab.dart'; // -> class LoadsTab
import '../load_list_screen.dart'; // (optional) class LoadListScreen
import '../load_editor.dart'; // (optional) class LoadEditor
// Drivers / Employees
import '../employees_tab.dart'; // -> class EmployeesTab
import '../employee_summary_screen.dart'; // (optional) class EmployeeSummaryScreen
// Documents
import '../document_upload_screen.dart'; // -> class DocumentUploadScreen
import '../file_preview_screen.dart'; // (optional) class FilePreviewScreen
// Clients
import '../clients_all_in_one.dart'; // -> class ClientsAllInOne
// Driver-specific
import '../driver_timeline_screen.dart'; // -> class DriverTimelineScreen
import '../driver_upload_screen.dart'; // -> class DriverUploadScreen
// Settings (you already have this in /screens/)
import '../screens/settings_screen.dart'; // -> class SettingsScreen

class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = FirebaseFirestore.instance.collection('users').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: doc.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Connecting…')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Connecting to database…\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data!.data() ?? const <String, dynamic>{};
        final role = (data['role'] ?? 'viewer') as String;

        if (role == 'admin') {
          return HomeShell(
            title: 'Full Load — Admin',
            tabs: [
              NavTab(
                  label: 'Dashboard',
                  icon: Icons.dashboard_outlined,
                  page: DispatcherDashboard()),
              NavTab(
                  label: 'Loads',
                  icon: Icons.local_shipping_outlined,
                  page: LoadsTab()),
              NavTab(
                  label: 'Drivers',
                  icon: Icons.people_alt_outlined,
                  page: EmployeesTab()),
              NavTab(
                  label: 'Docs',
                  icon: Icons.folder_open_outlined,
                  page: DocumentUploadScreen()),
              NavTab(
                  label: 'Clients',
                  icon: Icons.business_outlined,
                  page: ClientsAllInOne()),
              NavTab(
                  label: 'Settings',
                  icon: Icons.settings_outlined,
                  page: const SettingsScreen()),
            ],
          );
        }

        if (role == 'dispatcher') {
          return HomeShell(
            title: 'Full Load — Dispatcher',
            tabs: [
              NavTab(
                  label: 'Dashboard',
                  icon: Icons.dashboard_outlined,
                  page: DispatcherDashboard()),
              NavTab(
                  label: 'Loads',
                  icon: Icons.local_shipping_outlined,
                  page: LoadsTab()),
              NavTab(
                  label: 'Drivers',
                  icon: Icons.people_alt_outlined,
                  page: EmployeesTab()),
              NavTab(
                  label: 'Docs',
                  icon: Icons.folder_open_outlined,
                  page: DocumentUploadScreen()),
              NavTab(
                  label: 'Clients',
                  icon: Icons.business_outlined,
                  page: ClientsAllInOne()),
            ],
          );
        }

        if (role == 'driver') {
          return HomeShell(
            title: 'Full Load — Driver',
            tabs: [
              NavTab(
                  label: 'My Day',
                  icon: Icons.today_outlined,
                  page: DriverTimelineScreen()),
              NavTab(
                  label: 'My Loads',
                  icon: Icons.local_shipping_outlined,
                  page: LoadsTab()),
              NavTab(
                  label: 'Documents',
                  icon: Icons.folder_open_outlined,
                  page: DriverUploadScreen()),
            ],
          );
        }

        // viewer (or unknown)
        return const _ViewerHome();
      },
    );
  }
}

class _ViewerHome extends StatelessWidget {
  const _ViewerHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Access')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Your account is set to viewer. Please contact an admin to assign a role.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
