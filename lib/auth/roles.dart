<DOCUMENT filename="roles.dart">
// lib/auth/roles.dart
// Role-based access control (RBAC) for the app.
// Updated: Added roles from user vision (head_mechanic, general_laborer, sub-bookkeeper roles via perms). Expanded perms for features (e.g., toggleFeatures for subscriptions, aiUse for AI). Added roleToString for storage. Improved RoleGate with tooltip for denied access.

import 'package:flutter/material.dart';

/// The roles your app supports.
/// Add new ones here; update roleFromString, roleToString, and roleLabel.
enum AppRole {
  admin,
  manager,
  dispatcher,
  mechanic,
  headMechanic, // Added for approval workflows
  bookkeeper,
  driver, // For limited mobile access
  generalLaborer, // For clock-in/out
  viewer,
}

/// Named permissions your UI cares about.
/// Add more without changing storage (roles store strings, perms derived).
class AppPerm {
  static const manageUsers = 'manageUsers'; // View/change roles/permissions
  static const manageTrucks = 'manageTrucks';
  static const manageTrailers = 'manageTrailers';
  static const viewDispatch = 'viewDispatch';
  static const editDispatch = 'editDispatch';
  static const viewMechanic = 'viewMechanic';
  static const editMechanic = 'editMechanic';
  static const approveMechanic = 'approveMechanic'; // For head mechanic
  static const viewAccounting = 'viewAccounting';
  static const editAccounting = 'editAccounting';
  static const viewSettings = 'viewSettings';
  static const editSettings = 'editSettings';
  static const uploadDocs = 'uploadDocs'; // Driver uploads
  static const toggleFeatures = 'toggleFeatures'; // Admin subscription tiers
  static const useAI = 'useAI'; // AI driver select/invoice verify
}

/// Permission matrix for each role.
final Map<AppRole, Set<String>> kRolePerms = {
  AppRole.admin: {
    AppPerm.manageUsers,
    AppPerm.manageTrucks,
    AppPerm.manageTrailers,
    AppPerm.viewDispatch,
    AppPerm.editDispatch,
    AppPerm.viewMechanic,
    AppPerm.editMechanic,
    AppPerm.approveMechanic,
    AppPerm.viewAccounting,
    AppPerm.editAccounting,
    AppPerm.viewSettings,
    AppPerm.editSettings,
    AppPerm.uploadDocs,
    AppPerm.toggleFeatures,
    AppPerm.useAI,
  },
  AppRole.manager: {
    AppPerm.manageTrucks,
    AppPerm.manageTrailers,
    AppPerm.viewDispatch,
    AppPerm.editDispatch,
    AppPerm.viewMechanic,
    AppPerm.editMechanic,
    AppPerm.viewAccounting,
    AppPerm.editAccounting,
    AppPerm.viewSettings,
    AppPerm.useAI,
  },
  AppRole.dispatcher: {
    AppPerm.viewDispatch,
    AppPerm.editDispatch,
    AppPerm.viewAccounting, // Read-only for verification
    AppPerm.useAI, // For driver selection
  },
  AppRole.mechanic: {
    AppPerm.viewMechanic,
    AppPerm.editMechanic,
  },
  AppRole.headMechanic: {
    AppPerm.viewMechanic,
    AppPerm.editMechanic,
    AppPerm.approveMechanic,
  },
  AppRole.bookkeeper: {
    AppPerm.viewAccounting,
    AppPerm.editAccounting,
    AppPerm.viewDispatch, // Read-only
    AppPerm.useAI, // For invoice verify
  },
  AppRole.driver: {
    AppPerm.viewDispatch, // Own loads
    AppPerm.uploadDocs,
  },
  AppRole.generalLaborer: {
    AppPerm.uploadDocs, // Clock-in/out as "uploads"
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
    case 'headmechanic':
      return AppRole.headMechanic;
    case 'bookkeeper':
      return AppRole.bookkeeper;
    case 'driver':
      return AppRole.driver;
    case 'generallaborer':
      return AppRole.generalLaborer;
    default:
      return AppRole.viewer;
  }
}

String roleToString(AppRole r) {
  return r.toString().split('.').last.toLowerCase();
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
    case AppRole.headMechanic:
      return 'Head Mechanic';
    case AppRole.bookkeeper:
      return 'Bookkeeper';
    case AppRole.driver:
      return 'Driver';
    case AppRole.generalLaborer:
      return 'General Laborer';
    case AppRole.viewer:
      return 'Viewer';
  }
}

bool can(AppRole role, String perm) =>
    kRolePerms[role]?.contains(perm) ?? false;

/// Conditionally shows [child] based on a permission.
/// If [hide] is false, it disables the subtree instead of hiding.
/// Added: Optional tooltip for denied access.
class RoleGate extends StatelessWidget {
  final AppRole role;
  final String perm;
  final Widget child;
  final bool hide;
  final String? deniedTooltip;
  const RoleGate({
    super.key,
    required this.role,
    required this.perm,
    required this.child,
    this.hide = true,
    this.deniedTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final ok = can(role, perm);
    if (ok) return child;
    if (hide) return const SizedBox.shrink();
    Widget w = AbsorbPointer(
      absorbing: true,
      child: Opacity(opacity: 0.4, child: child),
    );
    if (deniedTooltip != null) {
      w = Tooltip(message: deniedTooltip, child: w);
    }
    return w;
  }
}
</DOCUMENT>

<DOCUMENT filename="init_app_check.dart">
// lib/auth/init_app_check.dart
// Updated: Added platform checks (web vs mobile), real ReCaptcha key stub (replace with yours), error handling for init.

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_app_check/firebase_app_check.dart';

Future<void> initAppCheck() async {
  try {
    final isUnsupportedDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (isUnsupportedDesktop) return; // Skip for unsupported

    await FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider('YOUR_RECAPTCHA_SITE_KEY_HERE'), // Replace
      androidProvider: AndroidProvider.playIntegrity, // Or .debug for testing
      appleProvider: AppleProvider.appAttest, // Or .deviceCheck
    );
  } catch (e) {
    // Log error; app can continue without App Check if optional
    print('App Check init failed: $e');
  }
}
</DOCUMENT>

<DOCUMENT filename="auth_gate.dart">
// lib/auth/auth_gate.dart
// Updated: Added role provider init after sign-in (fetch and set role), loading state, error handling. Integrated with home_shell.dart (pass companyId; assume fetched from user doc).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/roles.dart'; // For AppRoleProvider
import '../home_shell.dart'; // Updated home
import 'sign_in_screen.dart';
import 'current_user_role.dart'; // For role fetch

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _companyId; // Fetch after auth

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const SignInScreen();
        }
        // User signed in: Fetch role/companyId
        _initUserData(context, snapshot.data!);
        if (_companyId == null) {
          return const Center(child: CircularProgressIndicator()); // Wait for fetch
        }
        return HomeShell(companyId: _companyId!);
      },
    );
  }

  Future<void> _initUserData(BuildContext context, User user) async {
    try {
      final role = await currentUserRole();
      Provider.of<AppRoleProvider>(context, listen: false).setRole(role);
      // Fetch companyId from user doc (assume stored)
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      _companyId = snap.data()?['companyId'] as String? ?? 'default'; // Fallback
      if (mounted) setState(() {});
    } catch (e) {
      // Handle error: Sign out or show message
      FirebaseAuth.instance.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Init failed: $e')));
      }
    }
  }
}
</DOCUMENT>

<DOCUMENT filename="current_user_role.dart">
// lib/auth/current_user_role.dart
// Updated: Added error handling (throw specific exception), null check for user, companyId integration if roles per-company (commented; adjust if needed).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'roles.dart';

Future<AppRole> currentUserRole() async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) {
    throw Exception('No current user');
  }
  try {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
    final roleStr = snap.data()?['role']?.toString();
    return roleFromString(roleStr);
  } catch (e) {
    throw Exception('Role fetch failed: $e');
  }
}
</DOCUMENT>

<DOCUMENT filename="auth_debug.dart">
// lib/auth/auth_debug.dart
// Updated: Added clear fields after action, role gating (hide if not admin), error snackbar instead of text, async role load with loading state.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'roles.dart'; // For AppRole and RoleGate
import 'current_user_role.dart'; // For currentUserRole

class AuthDebugScreen extends StatefulWidget {
  const AuthDebugScreen({super.key});
  @override
  State<AuthDebugScreen> createState() => _AuthDebugScreenState();
}

class _AuthDebugScreenState extends State<AuthDebugScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = true;
  AppRole _role = AppRole.viewer;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    try {
      _role = await currentUserRole();
    } catch (_) {
      _role = AppRole.viewer;
    }
    setState(() => _loading = false);
  }

  Future<void> _register() async {
    final email = _email.text.trim();
    final pass = _pass.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      _snack('Enter email and password');
      return;
    }
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      _snack('Register OK');
      _clear();
    } on FirebaseAuthException catch (e) {
      _snack('${e.code}: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _anon() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
      _snack('Anon OK');
      _clear();
    } on FirebaseAuthException catch (e) {
      _snack('${e.code}: ${e.message}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _clear() {
    _email.clear();
    _pass.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(title: const Text('Auth Debug')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RoleGate(
          role: _role,
          perm: AppPerm.manageUsers,
          deniedTooltip: 'Admin only', // Only for admins
          child: Column(
            children: [
              TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 8),
              TextField(
                  controller: _pass,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _register, child: const Text('Register (Direct)')),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: _anon, child: const Text('Sign in Anonymously')),
            ],
          ),
        ),
      ),
    );
  }
}
</DOCUMENT>

<DOCUMENT filename="utils.dart">
// lib/util/utils.dart
// Updated: Added more utils from project (e.g., _callNumber from clients, _fmtDate from merges), HOS calc stub, safe ID gen. Made cross-platform safe.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

String fmtTs(Timestamp? ts) =>
    ts != null ? DateFormat('MMM d, y HH:mm').format(ts.toDate()) : '';

String newId() =>
    FirebaseFirestore.instance.collection('dummy').doc().id; // Random ID

String _oneLine(String s) =>
    s.replaceAll('\n', ', ').replaceAll(RegExp(r'\s+'), ' ').trim();

Future<void> callNumber(BuildContext context, String? raw) async {
  final s = (raw ?? '').replaceAll(RegExp(r'[^0-9+*#]'), '');
  if (s.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('No phone number')));
    return;
  }
  final uri = Uri(scheme: 'tel', path: s);
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Call failed: $e')));
  }
}

String fmtDate(DateTime? d) {
  if (d == null) return '';
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Duration remainingHOS(Timestamp? lastLog) {
  if (lastLog == null) return const Duration(hours: 11);
  final elapsed = DateTime.now().difference(lastLog.toDate());
  return const Duration(hours: 11) - elapsed; // Simplified FMCSA 11-hour rule
}
</DOCUMENT>

<DOCUMENT filename="sign_in_screen.dart">
// lib/auth/sign_in_screen.dart
// Updated: Added register button (nav to debug or simple form), forgot password link, error handling with snackbar, loading state.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_debug.dart'; // For register (optional)

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter email first')));
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Reset email sent')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _signIn,
                    child: const Text('Sign In'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AuthDebugScreen()),
                    ),
                    child: const Text('Register'),
                  ),
                  TextButton(
                    onPressed: _forgotPassword,
                    child: const Text('Forgot Password?'),
                  ),
                ],
              ),
      ),
    );
  }
}
</DOCUMENT>

<DOCUMENT filename="current_user_role_stream.dart">
// lib/auth/current_user_role_stream.dart
// Updated: Added error handling (yield viewer on error/null), companyId if roles per-company (commented), debounce for frequent auth changes.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart'; // Add to pubspec for debounce if needed

import 'roles.dart';

Stream<AppRole> currentUserRoleStream() {
  return FirebaseAuth.instance.authStateChanges().debounceTime(const Duration(milliseconds: 500)).asyncMap((user) async {
    if (user == null) return AppRole.viewer;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final roleStr = snap.data()?['role']?.toString();
      return roleFromString(roleStr);
    } catch (e) {
      return AppRole.viewer;
    }
  });
}
</DOCUMENT>