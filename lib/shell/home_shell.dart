<DOCUMENT filename="home_shell.dart">
// lib/shell/home_shell.dart
// Updated: Role-dynamic tabs, company isolation, responsive. Integrated new dashboards (mechanic_dashboard.dart for shop/fleet, bookkeeper_dashboard.dart for invoices/docs). Removed all placeholder references.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // For role provider (add to pubspec if not already: provider: ^6.1.2)

import '../auth/roles.dart'; // Ensure this has AppRole enum and AppRoleProvider
import '../dashboard_screen.dart';
import '../loads_tab.dart';
import '../employees_tab.dart';
import '../clients_all_in_one.dart';
import '../shippers_tab.dart';
import '../receivers_tab.dart';
import '../mechanic_dashboard.dart'; // Replacement for shop/fleet (trucks/trailers)
import '../bookkeeper_dashboard.dart'; // Replacement for documents/invoices
import '../settings_screen.dart';

class NavTab {
  final String label;
  final IconData icon;
  final Widget page;
  final List<AppRole> allowedRoles; // For role gating
  const NavTab({
    required this.label,
    required this.icon,
    required this.page,
    this.allowedRoles = const [AppRole.admin], // Default to admin
  });
}

class HomeShell extends StatefulWidget {
  final String companyId; // For multi-tenant data isolation
  const HomeShell({super.key, required this.companyId});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with RestorationMixin<HomeShell> {
  final RestorableInt _index = RestorableInt(0);
  late AppRole _role;

  @override
  void initState() {
    super.initState();
    // Fetch role from provider (assume set after login in auth_gate.dart or similar)
    _role = Provider.of<AppRoleProvider>(context, listen: false).role;
  }

  @override
  String? get restorationId => 'home_shell';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_index, 'tab_index');
  }

  List<NavTab> _getTabsForRole(AppRole role) {
    // Dynamically filter tabs by role; all use companyId for isolation
    final allTabs = [
      NavTab(
        label: 'Dashboard',
        icon: Icons.dashboard,
        page: DashboardScreen(companyId: widget.companyId),
        allowedRoles: AppRole.values, // Visible to all
      ),
      NavTab(
        label: 'Loads',
        icon: Icons.local_shipping,
        page: LoadsTab(companyId: widget.companyId),
        allowedRoles: [AppRole.admin, AppRole.dispatcher, AppRole.bookkeeper],
      ),
      NavTab(
        label: 'Employees',
        icon: Icons.people,
        page: EmployeesTab(companyId: widget.companyId),
        allowedRoles: [AppRole.admin],
      ),
      NavTab(
        label: 'Clients',
        icon: Icons.business,
        page: ClientsAllInOne(companyId: widget.companyId),
        allowedRoles: [AppRole.admin, AppRole.dispatcher, AppRole.bookkeeper],
      ),
      NavTab(
        label: 'Shippers',
        icon: Icons.store,
        page: ShippersTab(companyId: widget.companyId),
        allowedRoles: [AppRole.admin, AppRole.dispatcher],
      ),
      NavTab(
        label: 'Receivers',
        icon: Icons.inventory_2,
        page: ReceiversTab(companyId: widget.companyId),
        allowedRoles: [AppRole.admin, AppRole.dispatcher],
      ),
      NavTab(
        label: 'Shop', // Replaces trucks/trailers/shop placeholders
        icon: Icons.build,
        page: MechanicDashboard(companyId: widget.companyId),
        allowedRoles: [AppRole.admin, AppRole.mechanic],
      ),
      NavTab(
        label: 'Invoices', // Replaces documents/invoices placeholders
        icon: Icons.receipt,
        page: BookkeeperDashboard(companyId: widget.companyId),
        allowedRoles: [AppRole.admin, AppRole.bookkeeper],
      ),
      NavTab(
        label: 'Settings',
        icon: Icons.settings,
        page: SettingsScreen(companyId: widget.companyId),
        allowedRoles: [AppRole.admin],
      ),
    ];
    return allTabs.where((t) => t.allowedRoles.contains(role)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _getTabsForRole(_role);
    if (tabs.isEmpty) {
      return const Scaffold(body: Center(child: Text('No access to any sections. Contact admin.')));
    }

    final isWide = MediaQuery.of(context).size.width >= 1000;
    final body = IndexedStack(
      index: _index.value,
      children: tabs.map((t) => t.page).toList(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Full Load')),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: _index.value,
              onDestinationSelected: (i) => setState(() => _index.value = i),
              labelType: NavigationRailLabelType.all,
              destinations: tabs.map((t) => NavigationRailDestination(
                    icon: Icon(t.icon),
                    label: Text(t.label),
                  )).toList(),
            ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _index.value,
              onDestinationSelected: (i) => setState(() => _index.value = i),
              destinations: tabs.map((t) => NavigationDestination(
                    icon: Icon(t.icon),
                    label: t.label,
                  )).toList(),
            ),
    );
  }

  @override
  void dispose() {
    _index.dispose();
    super.dispose();
  }
}
</DOCUMENT>