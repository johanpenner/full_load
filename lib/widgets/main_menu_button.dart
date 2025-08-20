import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/roles.dart';
import '../screens/trucks_screen.dart';
import '../screens/trailers_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/users_roles_screen.dart';

enum _MenuAction { trucks, trailers, settings, users, signOut }

class MainMenuButton extends StatelessWidget {
  final void Function(Color? newSeedColor, String? companyName)?
      onSettingsApplied;
  const MainMenuButton({super.key, this.onSettingsApplied});

  Future<AppRole> _loadRole() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return AppRole.viewer;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
    return roleFromString(doc.data()?['role']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppRole>(
      future: _loadRole(),
      builder: (context, snap) {
        final role = snap.data ?? AppRole.viewer;

        final items = <PopupMenuEntry<_MenuAction>>[];

        if (can(role, AppPerm.manageTrucks) ||
            can(role, AppPerm.viewMechanic) ||
            can(role, AppPerm.editDispatch)) {
          items.add(const PopupMenuItem(
            value: _MenuAction.trucks,
            child: ListTile(
              leading: Icon(Icons.local_shipping_outlined),
              title: Text('Trucks'),
              subtitle: Text('Enter trucks & numbers'),
            ),
          ));
        }
        if (can(role, AppPerm.manageTrailers) ||
            can(role, AppPerm.viewMechanic) ||
            can(role, AppPerm.editDispatch)) {
          items.add(const PopupMenuItem(
            value: _MenuAction.trailers,
            child: ListTile(
              leading: Icon(Icons.trailer_outlined),
              title: Text('Trailers'),
              subtitle: Text('Enter trailers & numbers'),
            ),
          ));
        }
        if (can(role, AppPerm.viewSettings)) {
          items.add(const PopupMenuItem(
            value: _MenuAction.settings,
            child: ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('Settings'),
              subtitle: Text('Company & color'),
            ),
          ));
        }
        if (can(role, AppPerm.manageUsers)) {
          items.add(const PopupMenuItem(
            value: _MenuAction.users,
            child: ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('Users & Roles'),
              subtitle: Text('Invite & assign roles'),
            ),
          ));
        }

        items.add(const PopupMenuDivider());
        items.add(const PopupMenuItem(
          value: _MenuAction.signOut,
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
          ),
        ));

        return PopupMenuButton<_MenuAction>(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu),
          onSelected: (choice) async {
            switch (choice) {
              case _MenuAction.trucks:
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TrucksScreen()));
                break;
              case _MenuAction.trailers:
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TrailersScreen()));
                break;
              case _MenuAction.settings:
                final result = await Navigator.push<SettingsResult>(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                if (result != null && onSettingsApplied != null) {
                  onSettingsApplied!(result.seedColor, result.companyName);
                }
                break;
              case _MenuAction.users:
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const UsersRolesScreen()));
                break;
              case _MenuAction.signOut:
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Signed out')));
                }
                break;
            }
          },
          itemBuilder: (context) => items,
        );
      },
    );
  }
}
