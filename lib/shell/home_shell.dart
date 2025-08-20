import 'package:flutter/material.dart';

class NavTab {
  final String label;
  final IconData icon;
  final Widget page;
  const NavTab({required this.label, required this.icon, required this.page});
}

class HomeShell extends StatefulWidget {
  final List<NavTab> tabs;
  final String title;
  const HomeShell({super.key, required this.tabs, required this.title});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 1000;
    final body = IndexedStack(index: _index, children: [
      for (final t in widget.tabs) t.page,
    ]);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final t in widget.tabs)
                  NavigationRailDestination(
                    icon: Icon(t.icon),
                    label: Text(t.label),
                  ),
              ],
            ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final t in widget.tabs)
                  NavigationDestination(icon: Icon(t.icon), label: t.label),
              ],
            ),
    );
  }
}
