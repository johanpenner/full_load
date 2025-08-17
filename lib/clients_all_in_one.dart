import 'dart:typed_data';
import 'dart:io' as io show File;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

/// =======================
/// Models
/// =======================

class Address {
  String line1, line2, city, region, postalCode, country;
  Address({
    this.line1 = '',
    this.line2 = '',
    this.city = '',
    this.region = '',
    this.postalCode = '',
    this.country = 'CA',
  });
  Map<String, dynamic> toMap() => {
        'line1': line1,
        'line2': line2,
        'city': city,
        'region': region,
        'postalCode': postalCode,
        'country': country,
      };
  factory Address.fromMap(Map<String, dynamic>? m) => Address(
        line1: (m?['line1'] ?? '').toString(),
        line2: (m?['line2'] ?? '').toString(),
        city: (m?['city'] ?? '').toString(),
        region: (m?['region'] ?? '').toString(),
        postalCode: (m?['postalCode'] ?? '').toString(),
        country: (m?['country'] ?? 'CA').toString(),
      );
}

class Contact {
  String name, email, phone;
  Contact({this.name = '', this.email = '', this.phone = ''});
  Map<String, dynamic> toMap() =>
      {'name': name, 'email': email, 'phone': phone};
  factory Contact.fromMap(Map<String, dynamic>? m) => Contact(
      name: (m?['name'] ?? '').toString(),
      email: (m?['email'] ?? '').toString(),
      phone: (m?['phone'] ?? '').toString());
}

class Client {
  String id;
  String displayName, legalName, taxId, currency;
  int paymentTermsDays;
  num? creditLimit;
  bool prepayRequired, creditHold;
  String alertLevel, alertNotes;
  Address mailingAddress, billingAddress;
  Contact primaryContact, billingContact;
  String dispatchEmail, invoiceEmail;
  String notes;
  List<String> tags;
  String logoUrl;

  Client({
    this.id = '',
    this.displayName = '',
    this.legalName = '',
    this.taxId = '',
    this.currency = 'CAD',
    this.paymentTermsDays = 30,
    this.creditLimit,
    this.prepayRequired = false,
    this.creditHold = false,
    this.alertLevel = 'none',
    this.alertNotes = '',
    Address? mailingAddress,
    Address? billingAddress,
    Contact? primaryContact,
    Contact? billingContact,
    this.dispatchEmail = '',
    this.invoiceEmail = '',
    this.notes = '',
    List<String>? tags,
    this.logoUrl = '',
  })  : mailingAddress = mailingAddress ?? Address(),
        billingAddress = billingAddress ?? Address(),
        primaryContact = primaryContact ?? Contact(),
        billingContact = billingContact ?? Contact(),
        tags = tags ?? [];

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'legalName': legalName,
        'taxId': taxId,
        'currency': currency,
        'paymentTermsDays': paymentTermsDays,
        'creditLimit': creditLimit,
        'prepayRequired': prepayRequired,
        'creditHold': creditHold,
        'alertLevel': alertLevel,
        'alertNotes': alertNotes,
        'mailingAddress': mailingAddress.toMap(),
        'billingAddress': billingAddress.toMap(),
        'primaryContact': primaryContact.toMap(),
        'billingContact': billingContact.toMap(),
        'dispatchEmail': dispatchEmail,
        'invoiceEmail': invoiceEmail,
        'notes': notes,
        'tags': tags,
        'logoUrl': logoUrl,
        'name_lower': displayName.toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
      };

  factory Client.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Client(
      id: d.id,
      displayName: (m['displayName'] ?? '').toString(),
      legalName: (m['legalName'] ?? '').toString(),
      taxId: (m['taxId'] ?? '').toString(),
      currency: (m['currency'] ?? 'CAD').toString(),
      paymentTermsDays: (m['paymentTermsDays'] ?? 30) as int,
      creditLimit: (m['creditLimit']),
      prepayRequired: (m['prepayRequired'] ?? false) as bool,
      creditHold: (m['creditHold'] ?? false) as bool,
      alertLevel: (m['alertLevel'] ?? 'none').toString(),
      alertNotes: (m['alertNotes'] ?? '').toString(),
      mailingAddress:
          Address.fromMap(m['mailingAddress'] as Map<String, dynamic>?),
      billingAddress:
          Address.fromMap(m['billingAddress'] as Map<String, dynamic>?),
      primaryContact:
          Contact.fromMap(m['primaryContact'] as Map<String, dynamic>?),
      billingContact:
          Contact.fromMap(m['billingContact'] as Map<String, dynamic>?),
      dispatchEmail: (m['dispatchEmail'] ?? '').toString(),
      invoiceEmail: (m['invoiceEmail'] ?? '').toString(),
      notes: (m['notes'] ?? '').toString(),
      tags: (m['tags'] is List ? List<String>.from(m['tags']) : <String>[]),
      logoUrl: (m['logoUrl'] ?? '').toString(),
    );
  }
}

/// =======================
/// Helpers
/// =======================

Future<void> _callNumber(BuildContext context, String? raw) async {
  final s = (raw ?? '').replaceAll(RegExp(r'[^0-9+*#]'), '');
  if (s.isEmpty) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No phone number')));
    return;
  }
  final uri = Uri(scheme: 'tel', path: s);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('This device cannot place calls')));
  }
}

/// =======================
/// Edit Screen (save→close, delete, logo upload)
/// =======================
class ClientEditScreen extends StatefulWidget {
  final String? clientId;
  const ClientEditScreen({super.key, this.clientId});

  @override
  State<ClientEditScreen> createState() => _ClientEditScreenState();
}

class _ClientEditScreenState extends State<ClientEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _displayFocus = FocusNode();

  bool _saving = false;
  Client _client = Client();

  // Logo selection
  Uint8List? _newLogoBytes;
  String? _newLogoPath;
  bool _logoBusy = false;

  // Controllers
  final _display = TextEditingController();
  final _legal = TextEditingController();
  final _taxId = TextEditingController();
  final _currency = TextEditingController(text: 'CAD');
  final _terms = TextEditingController(text: '30');
  final _creditLimit = TextEditingController();

  final _mail1 = TextEditingController(),
      _mail2 = TextEditingController(),
      _mailCity = TextEditingController(),
      _mailRegion = TextEditingController(),
      _mailPostal = TextEditingController(),
      _mailCountry = TextEditingController(text: 'CA');

  final _bill1 = TextEditingController(),
      _bill2 = TextEditingController(),
      _billCity = TextEditingController(),
      _billRegion = TextEditingController(),
      _billPostal = TextEditingController(),
      _billCountry = TextEditingController(text: 'CA');

  final _pName = TextEditingController(),
      _pEmail = TextEditingController(),
      _pPhone = TextEditingController();
  final _bName = TextEditingController(),
      _bEmail = TextEditingController(),
      _bPhone = TextEditingController();

  final _dispatchEmail = TextEditingController(),
      _invoiceEmail = TextEditingController();
  final _notes = TextEditingController(), _alertNotes = TextEditingController();

  bool _prepay = false, _creditHold = false;
  String _alertLevel = 'none';

  @override
  void initState() {
    super.initState();
    if (widget.clientId != null) _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _displayFocus.dispose();
    for (final c in [
      _display,
      _legal,
      _taxId,
      _currency,
      _terms,
      _creditLimit,
      _mail1,
      _mail2,
      _mailCity,
      _mailRegion,
      _mailPostal,
      _mailCountry,
      _bill1,
      _bill2,
      _billCity,
      _billRegion,
      _billPostal,
      _billCountry,
      _pName,
      _pEmail,
      _pPhone,
      _bName,
      _bEmail,
      _bPhone,
      _dispatchEmail,
      _invoiceEmail,
      _notes,
      _alertNotes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance
        .collection('clients')
        .doc(widget.clientId!)
        .get();
    if (!doc.exists) return;
    setState(() {
      _client = Client.fromDoc(doc);
      _display.text = _client.displayName;
      _legal.text = _client.legalName;
      _taxId.text = _client.taxId;
      _currency.text = _client.currency;
      _terms.text = _client.paymentTermsDays.toString();
      _creditLimit.text = _client.creditLimit?.toString() ?? '';

      _mail1.text = _client.mailingAddress.line1;
      _mail2.text = _client.mailingAddress.line2;
      _mailCity.text = _client.mailingAddress.city;
      _mailRegion.text = _client.mailingAddress.region;
      _mailPostal.text = _client.mailingAddress.postalCode;
      _mailCountry.text = _client.mailingAddress.country;

      _bill1.text = _client.billingAddress.line1;
      _bill2.text = _client.billingAddress.line2;
      _billCity.text = _client.billingAddress.city;
      _billRegion.text = _client.billingAddress.region;
      _billPostal.text = _client.billingAddress.postalCode;
      _billCountry.text = _client.billingAddress.country;

      _pName.text = _client.primaryContact.name;
      _pEmail.text = _client.primaryContact.email;
      _pPhone.text = _client.primaryContact.phone;

      _bName.text = _client.billingContact.name;
      _bEmail.text = _client.billingContact.email;
      _bPhone.text = _client.billingContact.phone;

      _dispatchEmail.text = _client.dispatchEmail;
      _invoiceEmail.text = _client.invoiceEmail;

      _notes.text = _client.notes;
      _alertNotes.text = _client.alertNotes;

      _prepay = _client.prepayRequired;
      _creditHold = _client.creditHold;
      _alertLevel = _client.alertLevel;
    });
  }

  String? _emailOk(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(s) ? null : 'Invalid email';
  }

  ImageProvider? _logoProvider() {
    if (_newLogoBytes != null) return MemoryImage(_newLogoBytes!);
    if (_newLogoPath != null && !kIsWeb) {
      return Image.file(io.File(_newLogoPath!)).image;
    }
    if (_client.logoUrl.isNotEmpty) return NetworkImage(_client.logoUrl);
    return null;
  }

  Future<void> _pickLogo() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (_) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Camera'),
                  onTap: () => Navigator.pop(context, ImageSource.camera)),
              ListTile(
                  leading: const Icon(Icons.photo),
                  title: const Text('Gallery'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery)),
            ]),
          ),
        );
        if (source == null) return;
        final picker = ImagePicker();
        final x = await picker.pickImage(
            source: source, maxWidth: 1200, maxHeight: 1200, imageQuality: 85);
        if (x == null) return;
        final bytes = await x.readAsBytes();
        setState(() {
          _newLogoBytes = bytes;
          _newLogoPath = null;
        });
      } else {
        final res = await FilePicker.platform
            .pickFiles(type: FileType.image, withData: true);
        if (res == null || res.files.isEmpty) return;
        final f = res.files.first;
        setState(() {
          _newLogoBytes = f.bytes;
          _newLogoPath = f.bytes == null ? f.path : null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logo pick failed: $e')));
    }
  }

  Future<String?> _uploadLogo(String docId) async {
    if (_newLogoBytes == null && _newLogoPath == null) return null;
    setState(() => _logoBusy = true);
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('client_logos')
          .child('$docId.jpg');
      if (_newLogoBytes != null) {
        await ref.putData(
            _newLogoBytes!, SettableMetadata(contentType: 'image/jpeg'));
      } else if (!kIsWeb && _newLogoPath != null) {
        await ref.putFile(io.File(_newLogoPath!));
      } else {
        return null;
      }
      return await ref.getDownloadURL();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _removeLogo() async {
    if (widget.clientId == null) {
      setState(() {
        _newLogoBytes = null;
        _newLogoPath = null;
      });
      return;
    }
    if (_client.logoUrl.isEmpty) return;
    try {
      await FirebaseStorage.instance.refFromURL(_client.logoUrl).delete();
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId!)
          .update({'logoUrl': ''});
      if (!mounted) return;
      setState(() => _client.logoUrl = '');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Logo removed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to remove logo: $e')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      if (_display.text.trim().isEmpty) {
        _displayFocus.requestFocus();
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Client name is required')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fix highlighted fields')));
      }
      return;
    }
    if (_alertLevel == 'red' && _alertNotes.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add Red Alert notes.')));
      return;
    }

    setState(() => _saving = true);
    final isNew = widget.clientId == null;

    try {
      final payload = Client(
        id: widget.clientId ?? '',
        displayName: _display.text.trim(),
        legalName: _legal.text.trim(),
        taxId: _taxId.text.trim(),
        currency: _currency.text.trim().isEmpty ? 'CAD' : _currency.text.trim(),
        paymentTermsDays: int.tryParse(_terms.text.trim()) ?? 30,
        creditLimit: _creditLimit.text.trim().isEmpty
            ? null
            : num.tryParse(_creditLimit.text.trim()),
        prepayRequired: _prepay,
        creditHold: _creditHold,
        alertLevel: _alertLevel,
        alertNotes: _alertNotes.text.trim(),
        mailingAddress: Address(
          line1: _mail1.text,
          line2: _mail2.text,
          city: _mailCity.text,
          region: _mailRegion.text,
          postalCode: _mailPostal.text,
          country: _mailCountry.text.isNotEmpty ? _mailCountry.text : 'CA',
        ),
        billingAddress: Address(
          line1: _bill1.text,
          line2: _bill2.text,
          city: _billCity.text,
          region: _billRegion.text,
          postalCode: _billPostal.text,
          country: _billCountry.text.isNotEmpty ? _billCountry.text : 'CA',
        ),
        primaryContact: Contact(
            name: _pName.text, email: _pEmail.text, phone: _pPhone.text),
        billingContact: Contact(
            name: _bName.text, email: _bEmail.text, phone: _bPhone.text),
        dispatchEmail: _dispatchEmail.text.trim(),
        invoiceEmail: _invoiceEmail.text.trim(),
        notes: _notes.text.trim(),
        logoUrl: _client.logoUrl,
      );

      final ref = FirebaseFirestore.instance.collection('clients');
      String docId;
      if (isNew) {
        final added = await ref.add(payload.toMap());
        docId = added.id;
      } else {
        docId = widget.clientId!;
        await ref.doc(docId).update(payload.toMap());
      }

      final newUrl = await _uploadLogo(docId);
      if (newUrl != null) {
        await ref.doc(docId).update({'logoUrl': newUrl});
      }

      if (!mounted) return;
      setState(() => _saving = false);

      // ---------- CLOSE THE PAGE (and report action) ----------
      final result = {
        'action': isNew ? 'created' : 'updated',
        'name': _display.text.trim(),
      };

      if (Navigator.canPop(context)) {
        Navigator.pop(context, result);
      } else {
        // Rare: if this screen is the first route, replace with list.
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ClientListScreen()),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final msg = isNew
              ? 'Saved "${_display.text.trim()}"'
              : 'Updated "${_display.text.trim()}"';
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text(msg)));
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _confirmDelete() async {
    if (widget.clientId == null) return;
    final name =
        _display.text.trim().isEmpty ? 'this client' : _display.text.trim();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete client?'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      if (_client.logoUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(_client.logoUrl).delete();
        } catch (_) {}
      }
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId!)
          .delete();
      if (!mounted) return;
      Navigator.pop(context, {'action': 'deleted', 'name': name});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  InputDecoration _dec(String label, [String? hint, Widget? suffix]) =>
      InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: suffix);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDelete = widget.clientId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clientId == null ? 'New Client' : 'Edit Client'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
            style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onPrimary),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Logo picker + preview
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundImage: _logoProvider(),
                        child: _logoProvider() == null
                            ? const Icon(Icons.apartment, size: 36)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _pickLogo,
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Change logo'),
                          ),
                          if (canDelete &&
                              (_client.logoUrl.isNotEmpty ||
                                  _newLogoBytes != null ||
                                  _newLogoPath != null))
                            TextButton.icon(
                              onPressed: _removeLogo,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove'),
                              style: TextButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error),
                            ),
                        ],
                      ),
                      if (_logoBusy)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _display,
                  focusNode: _displayFocus,
                  decoration: _dec('Client Name (display)'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                    controller: _legal, decoration: _dec('Legal Name')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: TextFormField(
                          controller: _taxId,
                          decoration: _dec('Tax ID / HST #'))),
                  const SizedBox(width: 8),
                  SizedBox(
                      width: 110,
                      child: TextFormField(
                          controller: _currency,
                          decoration: _dec('Currency', 'CAD'))),
                  const SizedBox(width: 8),
                  SizedBox(
                      width: 110,
                      child: TextFormField(
                        controller: _terms,
                        decoration: _dec('Terms (days)', '30'),
                        keyboardType: TextInputType.number,
                      )),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: TextFormField(
                    controller: _creditLimit,
                    decoration: _dec('Credit Limit (optional)'),
                    keyboardType: TextInputType.number,
                  )),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DropdownButtonFormField<String>(
                    value: _alertLevel,
                    items: const [
                      DropdownMenuItem(
                          value: 'none', child: Text('Alert: none')),
                      DropdownMenuItem(
                          value: 'warn', child: Text('Alert: warn')),
                      DropdownMenuItem(value: 'red', child: Text('Alert: RED')),
                    ],
                    onChanged: (v) => setState(() => _alertLevel = v ?? 'none'),
                    decoration: _dec('Alert Level'),
                  )),
                ]),
                if (_alertLevel != 'none') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _alertNotes,
                    maxLines: 3,
                    decoration: _dec('Alert Notes (reason, instructions)'),
                    validator: (v) =>
                        _alertLevel == 'red' && (v == null || v.trim().isEmpty)
                            ? 'Required for RED alert'
                            : null,
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _prepay,
                  onChanged: (v) => setState(() => _prepay = v),
                  title: const Text('Require prepayment / pay first'),
                  subtitle:
                      const Text('Block new loads until payment received'),
                ),
                SwitchListTile(
                  value: _creditHold,
                  onChanged: (v) => setState(() => _creditHold = v),
                  title: const Text('Credit hold'),
                  subtitle: const Text('Do not create loads while on hold'),
                ),

                const Divider(height: 24),
                _addrBlock('Mailing Address', _mail1, _mail2, _mailCity,
                    _mailRegion, _mailPostal, _mailCountry),
                const Divider(height: 24),
                _addrBlock('Billing Address', _bill1, _bill2, _billCity,
                    _billRegion, _billPostal, _billCountry),

                const Divider(height: 24),
                Row(children: [
                  Expanded(
                      child: TextFormField(
                          controller: _pName,
                          decoration: _dec('Primary Contact Name'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextFormField(
                    controller: _pPhone,
                    keyboardType: TextInputType.phone,
                    decoration: _dec(
                        'Primary Phone',
                        null,
                        IconButton(
                            icon: const Icon(Icons.call),
                            onPressed: () =>
                                _callNumber(context, _pPhone.text))),
                  )),
                ]),
                const SizedBox(height: 8),
                TextFormField(
                    controller: _pEmail,
                    decoration: _dec('Primary Email'),
                    validator: _emailOk),

                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: TextFormField(
                          controller: _bName,
                          decoration: _dec('Billing Contact Name'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextFormField(
                    controller: _bPhone,
                    keyboardType: TextInputType.phone,
                    decoration: _dec(
                        'Billing Phone',
                        null,
                        IconButton(
                            icon: const Icon(Icons.call),
                            onPressed: () =>
                                _callNumber(context, _bPhone.text))),
                  )),
                ]),
                const SizedBox(height: 8),
                TextFormField(
                    controller: _bEmail,
                    decoration: _dec('Billing Email'),
                    validator: _emailOk),

                const SizedBox(height: 16),
                TextFormField(
                    controller: _dispatchEmail,
                    decoration: _dec('Dispatch Email'),
                    validator: _emailOk),
                const SizedBox(height: 8),
                TextFormField(
                    controller: _invoiceEmail,
                    decoration: _dec('Invoice Email (AR inbox)'),
                    validator: _emailOk),

                const SizedBox(height: 16),
                TextFormField(
                    controller: _notes,
                    maxLines: 4,
                    decoration: _dec('Internal Notes / Special instructions')),

                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Client'),
                ),

                if (canDelete) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Danger zone',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.error),
                    ),
                    onPressed: _confirmDelete,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Delete client'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addrBlock(
    String title,
    TextEditingController l1,
    TextEditingController l2,
    TextEditingController city,
    TextEditingController region,
    TextEditingController postal,
    TextEditingController country,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(controller: l1, decoration: _dec('Line 1')),
        const SizedBox(height: 8),
        TextField(controller: l2, decoration: _dec('Line 2 (optional)')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(controller: city, decoration: _dec('City'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: region, decoration: _dec('Province/State'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: postal, decoration: _dec('Postal/ZIP'))),
          const SizedBox(width: 8),
          Expanded(
              child:
                  TextField(controller: country, decoration: _dec('Country'))),
        ]),
      ],
    );
  }
}

/// =======================
/// List Screen (awaits result → toast) + Edit + Call + Logo
/// =======================
class ClientListScreen extends StatelessWidget {
  const ClientListScreen({super.key});

  Future<void> _openNew(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClientEditScreen()),
    );
    _handleResult(context, result);
  }

  Future<void> _openEdit(BuildContext context, String id, String name) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClientEditScreen(clientId: id)),
    );
    _handleResult(context, result, fallbackName: name);
  }

  void _handleResult(BuildContext context, dynamic result,
      {String? fallbackName}) {
    if (result is! Map) return;
    final action = result['action']?.toString();
    final name = (result['name']?.toString().trim().isNotEmpty ?? false)
        ? result['name'].toString()
        : (fallbackName ?? 'Client');

    String? msg;
    if (action == 'created') msg = 'Saved "$name".';
    if (action == 'updated') msg = 'Updated "$name".';
    if (action == 'deleted') msg = 'Deleted "$name".';

    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('clients')
        .orderBy('name_lower')
        .limit(200);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clients'),
        actions: [
          IconButton(
            tooltip: 'New client',
            icon: const Icon(Icons.add),
            onPressed: () => _openNew(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (c, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs.map((d) => Client.fromDoc(d)).toList();
          if (docs.isEmpty) return const Center(child: Text('No clients yet'));
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final cl = docs[i];
              final phone = cl.primaryContact.phone.isNotEmpty
                  ? cl.primaryContact.phone
                  : cl.billingContact.phone;
              final alertIcon = cl.alertLevel == 'red'
                  ? const Icon(Icons.warning, color: Colors.red)
                  : cl.alertLevel == 'warn'
                      ? const Icon(Icons.warning, color: Colors.orange)
                      : null;

              return ListTile(
                leading: CircleAvatar(
                  radius: 22,
                  backgroundImage:
                      cl.logoUrl.isNotEmpty ? NetworkImage(cl.logoUrl) : null,
                  child: cl.logoUrl.isNotEmpty
                      ? null
                      : const Icon(Icons.apartment),
                ),
                title: Text(cl.displayName),
                subtitle: Text(
                  cl.billingContact.email.isNotEmpty
                      ? cl.billingContact.email
                      : cl.primaryContact.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    if (alertIcon != null) alertIcon,
                    IconButton(
                      tooltip: phone.isEmpty ? 'No phone' : 'Call',
                      icon: const Icon(Icons.call),
                      onPressed: phone.isEmpty
                          ? null
                          : () => _callNumber(context, phone),
                    ),
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit),
                      onPressed: () =>
                          _openEdit(context, cl.id, cl.displayName),
                    ),
                  ],
                ),
                onTap: () => _openEdit(context, cl.id, cl.displayName),
              );
            },
          );
        },
      ),
    );
  }
}

/// Optional tab wrapper
class ClientsTab extends StatelessWidget {
  const ClientsTab({super.key});
  @override
  Widget build(BuildContext context) => const ClientListScreen();
}
