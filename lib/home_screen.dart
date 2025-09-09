// lib/home_screen.dart
// Home with sidebar (NavigationRail) for Dashboard, Loads, Employees, Clients,
// Shippers, Receivers, Docs, Settings. Global search in the content area.
// FAB opens the upgraded New Load Entry screen.

import 'package:flutter/material.dart';

// Actual screens/widgets
import 'dashboard_screen.dart';
import 'loads_screen.dart';
import 'employees_screen.dart';
import 'clients_screen.dart';
import 'shippers_tab.dart';
import 'receivers_tab.dart';
import 'settings_screen.dart';

// Placeholders
import 'placeholders.dart';

// New load entry screen (the upgraded one I provided)
import 'new_load_entry.dart'; // <- make sure this file exists

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0; // Starts on Dashboard
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
          () => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Sidebar destinations
  final List<NavigationRailDestination> _destinations = const [
    NavigationRailDestination(
        icon: Icon(Icons.dashboard), label: Text('Dashboard')),
    NavigationRailDestination(
        icon: Icon(Icons.local_shipping), label: Text('Loads')),
    NavigationRailDestination(
        icon: Icon(Icons.people), label: Text('Employees')),
    NavigationRailDestination(
        icon: Icon(Icons.business), label: Text('Clients')),
    NavigationRailDestination(icon: Icon(Icons.store), label: Text('Shippers')),
    NavigationRailDestination(
        icon: Icon(Icons.inventory_2), label: Text('Receivers')),
    NavigationRailDestination(
        icon: Icon(Icons.description), label: Text('Docs')),
    NavigationRailDestination(
        icon: Icon(Icons.settings), label: Text('Settings')),
  ];

  // Get content for selected index
  Widget _getContent(int index, String searchQuery) {
    switch (index) {
      case 0:
        return const DashboardScreen();
      case 1:
        return LoadsScreen(searchQuery: searchQuery);
      case 2:
        return EmployeesScreen(searchQuery: searchQuery);
      case 3:
        return ClientsScreen(searchQuery: searchQuery);
      case 4:
        return Scaffold(
          appBar: AppBar(title: const Text('Shippers')),
          body: ShippersTab(searchQuery: searchQuery),
        );
      case 5:
        return Scaffold(
          appBar: AppBar(title: const Text('Receivers')),
          body: ReceiversTab(searchQuery: searchQuery),
        );
      case 6:
        return const DocsScreenPlaceholder();
      case 7:
        return const SettingsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Full Load - Admin'),
        actions: [IconButton(icon: const Icon(Icons.menu), onPressed: () {})],
      ),
      body: SafeArea(
        child: Row(
          children: [
            // Keep the rail width explicit so it never collapses to 0 and break hit-testing.
            // 256 is the standard width for an "extended" NavigationRail.
            SizedBox(
              width: 256,
              child: NavigationRail(
                selectedIndex: _selectedIndex,
                extended: true,
                onDestinationSelected: (index) =>
                    setState(() => _selectedIndex = index),
                destinations: _destinations,
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: Column(
                children: [
                  // Global search bar
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText:
                            'Search by client, shipper, receiver, load #, PO #',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  Expanded(child: _getContent(_selectedIndex, _searchQuery)),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: (_selectedIndex == 0 || _selectedIndex == 1)
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NewLoadEntryScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('New Load'),
            )
          : null,
    );
  }
}
