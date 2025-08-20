// lib/load_list_screen.dart
// Thin wrapper so any old routes that push LoadListScreen still work.
// It just renders the same UI as LoadsTab.

import 'package:flutter/material.dart';
import 'loads_tab.dart';
import 'widgets/main_menu_button.dart';

// inside AppBar
actions: [
  MainMenuButton(
    onSettingsApplied: (seedColor, companyName) {
      // (optional) live theme apply if you manage ThemeMode dynamically
    },
  ),
],

class LoadListScreen extends StatelessWidget {
  const LoadListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // LoadsTab already includes AppBar, search, filter, and the New Load FAB.
    return const LoadsTab();
  }
}
