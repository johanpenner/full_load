// lib/home_screen.dart
// Clean home with tabs for Loads, New Load, Clients, Shippers, Receivers, Employees.
// Includes a launcher for QuickLoadScreen and fixes tab/child count mismatch.

import 'package:flutter/material.dart';

// Tabs
import 'loads_tab.dart';
import 'clients_all_in_one.dart'; // ClientListScreen
import 'shippers_tab.dart'; // ShippersTab
import 'receivers_tab.dart'; // ReceiversTab
import 'employees_tab.dart'; // EmployeesTab

// Quick Load creator (ensure this file exists from earlier step)
// If you renamed it, update the import accordingly.
import 'quick_load_screen.dart'; // QuickLoadScreen

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Tab indexes for convenience
  static const int _idxLoads = 0;
  static const int _idxNewLoad = 1;
  static const int _idxClients = 2;
  static const int _idxShippers = 3;
  static const int _idxReceivers = 4;
  static const int _idxEmployees = 5;

  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    // ✅ 6 tabs now (Loads, New Load, Clients, Shippers, Receivers, Employees)
    _tabs = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openQuickLoad() async {
    // Open the full Quick Load form.
    // On successful save, QuickLoadScreen returns true via Navigator.pop(context, true)
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const QuickLoadScreen()),
    );

    if (saved == true) {
      // Jump to Loads so dispatcher sees it immediately.
      _tabs.animateTo(_idxLoads);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Load saved')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Full Load'),
        actions: [
          IconButton(
            tooltip: 'New Load',
            icon: const Icon(Icons.add),
            onPressed: _openQuickLoad,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.local_shipping), text: 'Loads'),
            Tab(icon: Icon(Icons.add_box), text: 'New Load'),
            Tab(icon: Icon(Icons.people_alt), text: 'Clients'),
            Tab(icon: Icon(Icons.store), text: 'Shippers'),
            Tab(icon: Icon(Icons.inventory_2), text: 'Receivers'),
            Tab(icon: Icon(Icons.badge), text: 'Employees'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const LoadsTab(),
          // New Load tab shows a one-tap launcher into the QuickLoadScreen.
          _NewLoadLauncher(onStart: _openQuickLoad),
          const ClientListScreen(),
          const ShippersTab(),
          const ReceiversTab(),
          const EmployeesTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQuickLoad,
        icon: const Icon(Icons.add),
        label: const Text('New Load'),
      ),
    );
  }
}

/// A simple launcher card so the New Load tab is just one tap.
/// This avoids embedding the full screen in a tab (which could cause
/// Navigator.pop() inside the form to close the whole HomeScreen).
class _NewLoadLauncher extends StatelessWidget {
  final VoidCallback onStart;
  const _NewLoadLauncher({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  leading: Icon(Icons.bolt),
                  title: Text('Quick Load'),
                  subtitle: Text(
                    'One-line entry: Client • Shipper • Receiver • Pickup • Delivery • Truck.\n'
                    'Calculates Truck→Pickup and Pickup→Delivery distance & ETA (km/mi).',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.local_shipping),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_right_alt),
                    SizedBox(width: 8),
                    Icon(Icons.place),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_right_alt),
                    SizedBox(width: 8),
                    Icon(Icons.flag),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Quick Load'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tip: You can also tap the + in the top bar or the New Load button below.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
