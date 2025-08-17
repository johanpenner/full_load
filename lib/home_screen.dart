import 'package:flutter/material.dart';

import 'clients_all_in_one.dart'; // provides ClientsTab + ClientListScreen
import 'receivers_tab.dart';
import 'shippers_tab.dart';
import 'employees_tab.dart';
import 'dispatcher_dashboard.dart';
import 'new_load_screen.dart';
import 'employee_summary_screen.dart';
import 'dispatcher_summary_screen.dart';
import 'loads_tab.dart';
import 'load_list_screen.dart';
import 'driver_upload_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  late final List<Widget> tabs = <Widget>[
    const ClientsTab(),
    ReceiversTab(),
    ShippersTab(),
    EmployeesTab(),
    DispatcherDashboard(),
    const NewLoadScreen(),
    EmployeeSummaryScreen(),
    DispatcherSummaryScreen(),
    LoadsTab(),
    LoadListScreen(),
    const DriverUploadScreen(),
  ];

  static const List<String> labels = <String>[
    'Clients',
    'Receivers',
    'Shippers',
    'Employees',
    'Dispatch',
    'New Load',
    'Summary',
    'Charts',
    'Loads',
    'All Loads',
    'Driver Upload',
  ];

  static const List<IconData> icons = <IconData>[
    Icons.business,
    Icons.local_shipping,
    Icons.local_shipping_outlined,
    Icons.people,
    Icons.dashboard,
    Icons.add_box,
    Icons.bar_chart,
    Icons.analytics,
    Icons.assignment,
    Icons.archive,
    Icons.upload_file,
  ];

  @override
  Widget build(BuildContext context) {
    assert(tabs.length == labels.length && labels.length == icons.length,
        'tabs/labels/icons must match');

    final safeIndex =
        (_index >= 0 && _index < tabs.length) ? _index : 0; // guard

    return Scaffold(
      appBar: AppBar(
        title: const Text('Full Load'),
        actions: [
          IconButton(
            tooltip: 'Open Clients',
            icon: const Icon(Icons.people),
            onPressed: () => Navigator.pushNamed(context, '/clients'),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: safeIndex, children: tabs),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _index = i), // i is int
        items: List.generate(
          tabs.length,
          (i) =>
              BottomNavigationBarItem(icon: Icon(icons[i]), label: labels[i]),
        ),
      ),
    );
  }
}
