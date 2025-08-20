import 'package:flutter/material.dart';

/// The roles your app supports.
enum AppRole { admin, manager, dispatcher, mechanic, bookkeeper, viewer }

/// Named permissions your UI cares about.
/// Add more later without touching storage.
class AppPerm {
  static const manageUsers = 'manageUsers'; // view + change roles
  static const manageTrucks = 'manageTrucks';
  static const manageTrailers = 'manageTrailers';
  static const viewDispatch = 'viewDispatch';
  static const editDispatch = 'editDispatch';
  static const viewMechanic = 'viewMechanic';
  static const editMechanic = 'editMechanic';
  static const viewAccounting = 'viewAccounting';
  static const editAccounting = 'editAccounting';
  static const viewSettings = 'viewSettings';
  static const editSettings = 'editSettings';
}

/// The permission matrix for each role.
final Map<AppRole, Set<String>> kRolePerms = {
  AppRole.admin: {
    AppPerm.manageUsers,
    AppPerm.manageTrucks,
    AppPerm.manageTrailers,
    AppPerm.viewDispatch,
    AppPerm.editDispatch,
    AppPerm.viewMechanic,
    AppPerm.editMechanic,
    AppPerm.viewAccounting,
    AppPerm.editAccounting,
    AppPerm.viewSettings,
    AppPerm.editSettings,
  },
  AppRole.manager: {
    AppPerm.manageTrucks, AppPerm.manageTrailers,
    AppPerm.viewDispatch, AppPerm.editDispatch,
    AppPerm.viewMechanic, AppPerm.editMechanic,
    AppPerm.viewAccounting, AppPerm.editAccounting,
    AppPerm.viewSettings, AppPerm.editSettings,
    // no manageUsers
  },
  AppRole.dispatcher: {
    AppPerm.viewDispatch, AppPerm.editDispatch,
    AppPerm.viewMechanic, // can view mechanic info
    AppPerm.viewAccounting, // can view accounting summaries
    AppPerm.viewSettings, // can see settings, not edit
  },
  AppRole.mechanic: {
    AppPerm.viewMechanic, AppPerm.editMechanic,
    AppPerm.viewDispatch, // can see loads for shop context
  },
  AppRole.bookkeeper: {
    AppPerm.viewAccounting, AppPerm.editAccounting,
    AppPerm.viewDispatch, // read-only to cross-check
    AppPerm.viewSettings, // read-only
  },
  AppRole.viewer: {
    AppPerm.viewDispatch,
  },
};

/// Helpers
AppRole roleFromString(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'admin':
      return AppRole.admin;
    case 'manager':
      return AppRole.manager;
    case 'dispatcher':
      return AppRole.dispatcher;
    case 'mechanic':
      return AppRole.mechanic;
    case 'bookkeeper':
      return AppRole.bookkeeper;
    default:
      return AppRole.viewer;
  }
}

String roleLabel(AppRole r) {
  switch (r) {
    case AppRole.admin:
      return 'Admin';
    case AppRole.manager:
      return 'Manager';
    case AppRole.dispatcher:
      return 'Dispatcher';
    case AppRole.mechanic:
      return 'Mechanic';
    case AppRole.bookkeeper:
      return 'Bookkeeper';
    case AppRole.viewer:
      return 'Viewer';
  }
}

bool can(AppRole role, String perm) => kRolePerms[role]!.contains(perm);

/// Conditionally shows [child] based on a permission.
/// If [hide] is false, it disables the subtree instead of hiding.
class RoleGate extends StatelessWidget {
  final AppRole role;
  final String perm;
  final Widget child;
  final bool hide;
  const RoleGate({
    super.key,
    required this.role,
    required this.perm,
    required this.child,
    this.hide = true,
  });

  @override
  Widget build(BuildContext context) {
    final ok = can(role, perm);
    if (ok) return child;
    if (hide) return const SizedBox.shrink();
    return AbsorbPointer(
        absorbing: true, child: Opacity(opacity: 0.4, child: child));
  }
}
