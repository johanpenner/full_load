import 'package:flutter/material.dart';

import 'clients_tab.dart';
import 'receivers_tab.dart';
import 'shippers_tab.dart';
import 'employees_tab.dart';
import 'dispatcher_dashboard.dart';
import 'new_load_screen.dart';
import 'employee_summary_screen.dart';
import 'dispatcher_summary_screen.dart';
import 'loads_tab.dart'; // ✅ NEW: Loads manager tab
import 'load_list_screen.dart';
import 'driver_upload_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  // Not const: some screens may not have const constructors
  late final List<Widget> tabs = <Widget>[
    ClientsTab(),
    ReceiversTab(),
    ShippersTab(),
    EmployeesTab(),
    DispatcherDashboard(),
    NewLoadScreen(),
    EmployeeSummaryScreen(),
    DispatcherSummaryScreen(),
    LoadsTab(),          // ✅ NEW tab
    LoadListScreen(),    // (Optional) keep your existing "All Loads" view
    DriverUploadScreen(),
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
    'Loads',       // ✅ NEW
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
    Icons.assignment,   // ✅ NEW icon for Loads
    Icons.archive,
    Icons.upload_file,
  ];

  @override
  Widget build(BuildContext context) {
    assert(tabs.length == labels.length && labels.length == icons.length,
        'tabs/labels/icons must have the same length');

    return Scaffold(
      appBar: AppBar(title: const Text('Full Load')),
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: tabs,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _index = i),
        items: List.generate(
          tabs.length,
          (i) => BottomNavigationBarItem(
            icon: Icon(icons[i]),
            label: labels[i],
          ),
        ),
      ),
    );
  }
}
