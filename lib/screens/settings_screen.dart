// lib/screens/settings_screen.dart
// Updated Settings screen: Realtime stream from Firestore, role gating (view/read-only for non-admins), logo upload (via file_picker + Firebase Storage), validation, error/progress UI, color picker with preview.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../auth/roles.dart'; // For RoleGate/AppPerm (add 'editSettings' if not in roles.dart)
import '../auth/current_user_role.dart'; // For role
import '../util/storage_upload.dart'; // For uploadFilePathWithMeta (add if needed)

class SettingsResult {
  final Color? seedColor;
  final String? companyName;
  SettingsResult({this.seedColor, this.companyName});
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _companyCtrl = TextEditingController();
  final _logoUrlCtrl = TextEditingController();
  Color _seedColor = Colors.blue;

  AppRole _role = AppRole.viewer;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    _role = await currentUserRole();
    setState(() {});
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _logoUrlCtrl.dispose();
    super.dispose();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _stream =>
      FirebaseFirestore.instance.collection('settings').doc('app').snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final m = snap.data!.data() ?? {};
          if (_loading) {
            _companyCtrl.text = (m['companyName'] ?? '').toString();
            _logoUrlCtrl.text = (m['companyLogoUrl'] ?? '').toString();
            final hex = (m['seedColor'] ?? '').toString();
            if (hex.startsWith('#') && (hex.length == 7 || hex.length == 9)) {
              _seedColor = _fromHex(hex);
            }
            _loading = false;
          }
          final canEdit = can(_role, AppPerm.editSettings);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _companyCtrl,
                  readOnly: !canEdit,
                  decoration: const InputDecoration(
                    labelText: 'Company Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _logoUrlCtrl,
                        readOnly: !canEdit,
                        decoration: const InputDecoration(
                          labelText: 'Company Logo URL (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (canEdit) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Upload logo',
                        icon: const Icon(Icons.upload),
                        onPressed: _uploadLogo,
                      ),
                    ],
                  ],
                ),
                if (_logoUrlCtrl.text.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Center(
                      child: Image.network(_logoUrlCtrl.text,
                          height: 100,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image))),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Primary color',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 8),
                RoleGate(
                  role: _role,
                  perm: AppPerm.editSettings,
                  hide: false, // Disable instead of hide for viewers
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _colorChoices().map((c) {
                      final selected = _seedColor.value == c.value;
                      return InkWell(
                        onTap: canEdit
                            ? () => setState(() => _seedColor = c)
                            : null,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected ? Colors.black87 : Colors.black26,
                              width: selected ? 2 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Spacer(),
                if (canEdit)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save),
                          label: Text(_saving ? 'Saving...' : 'Save Settings'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Color> _colorChoices() => [
        Colors.blue,
        Colors.indigo,
        Colors.teal,
        Colors.green,
        Colors.orange,
        Colors.red,
        Colors.pink,
        Colors.purple,
        Colors.brown,
        Colors.cyan,
      ];

  Color _fromHex(String h) {
    final s = h.replaceFirst('#', '');
    final v = int.parse(s.length == 6 ? 'FF$s' : s, radix: 16);
    return Color(v);
  }

  String _toHex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final data = {
        'companyName': _companyCtrl.text.trim(),
        'companyLogoUrl': _logoUrlCtrl.text.trim(),
        'seedColor': _toHex(_seedColor),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .set(data, SetOptions(merge: true));
      if (mounted) {
        Navigator.pop(
            context,
            SettingsResult(
                seedColor: _seedColor, companyName: _companyCtrl.text.trim()));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadLogo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.path == null) return;
    try {
      final refPath = 'logos/company_logo.${f.extension ?? 'png'}';
      final url =
          await uploadFilePathWithMeta(refPath: refPath, filePath: f.path!);
      _logoUrlCtrl.text = url;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Logo uploaded')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }
}
