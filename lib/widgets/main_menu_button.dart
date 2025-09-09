// lib/widgets/main_menu_button.dart
import 'package:flutter/material.dart';

class MainMenuButton extends StatelessWidget {
  const MainMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu),
      onPressed: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home'),
              onTap: () => Navigator.pop(ctx, 'home'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () => Navigator.pop(ctx, 'settings'),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => Navigator.pop(ctx, 'signout'),
            ),
          ],
        ),
      ),
    );

    switch (choice) {
      case 'home':
        Navigator.of(context).maybePop();
        break;
      case 'settings':
        // TODO: push your settings screen if you have it:
        // Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings (todo)')));
        break;
      case 'signout':
        // TODO: call your auth sign-out here
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Signed out (todo)')));
        break;
      default:
        break;
    }
  }
}
