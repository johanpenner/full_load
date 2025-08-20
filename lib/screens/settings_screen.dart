import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _logoUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .get();
      final m = doc.data() ?? {};
      _companyCtrl.text = (m['companyName'] ?? '').toString();
      _logoUrlCtrl.text = (m['companyLogoUrl'] ?? '').toString();
      final hex = (m['seedColor'] ?? '').toString();
      if (hex.startsWith('#') && (hex.length == 7 || hex.length == 9)) {
        _seedColor = _fromHex(hex);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Color _fromHex(String h) {
    final s = h.replaceFirst('#', '');
    final v = int.parse(s.length == 6 ? 'FF$s' : s, radix: 16);
    return Color(v);
  }

  String _toHex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _companyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Company Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _logoUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Company Logo URL (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Primary color',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _colorChoices().map((c) {
                      final selected = _seedColor.value == c.value;
                      return InkWell(
                        onTap: () => setState(() => _seedColor = c),
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
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Settings'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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

  Future<void> _save() async {
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

    // Return result upward so you can apply theme immediately if you want
    if (!mounted) return;
    Navigator.pop(
        context,
        SettingsResult(
            seedColor: _seedColor, companyName: _companyCtrl.text.trim()));
  }
}
