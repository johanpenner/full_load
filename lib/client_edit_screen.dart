import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/client_model.dart';

class ClientEditScreen extends StatefulWidget {
  final String? clientId;
  const ClientEditScreen({super.key, this.clientId});

  @override
  State<ClientEditScreen> createState() => _ClientEditScreenState();
}

class _ClientEditScreenState extends State<ClientEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  Client _client = Client();

  // Text controllers
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_alertLevel == 'red' && _alertNotes.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add Red Alert notes.')),
      );
      return;
    }
    setState(() => _saving = true);

    final c = Client(
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
        country: _mailCountry.text.isEmpty ? 'CA' : _mailCountry.text,
      ),
      billingAddress: Address(
        line1: _bill1.text,
        line2: _bill2.text,
        city: _billCity.text,
        region: _billRegion.text,
        postalCode: _billPostal.text,
        country: _billCountry.text.isEmpty ? 'CA' : _billCountry.text,
      ),
      primaryContact:
          Contact(name: _pName.text, email: _pEmail.text, phone: _pPhone.text),
      billingContact:
          Contact(name: _bName.text, email: _bEmail.text, phone: _bPhone.text),
      dispatchEmail: _dispatchEmail.text.trim(),
      invoiceEmail: _invoiceEmail.text.trim(),
      notes: _notes.text.trim(),
    );

    final ref = FirebaseFirestore.instance.collection('clients');
    if (widget.clientId == null) {
      await ref.add(c.toMap());
    } else {
      await ref.doc(widget.clientId!).update(c.toMap());
    }

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Client saved')),
    );
    Navigator.pop(context, true);
  }

  InputDecoration _dec(String label, [String? hint]) => InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      );

  Widget _addr(
      String title,
      TextEditingController l1,
      TextEditingController l2,
      TextEditingController city,
      TextEditingController region,
      TextEditingController postal,
      TextEditingController country) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Names & terms
                TextFormField(
                  controller: _display,
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
                        decoration: _dec('Currency', 'CAD'),
                      )),
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
                _addr('Mailing Address', _mail1, _mail2, _mailCity, _mailRegion,
                    _mailPostal, _mailCountry),
                const Divider(height: 24),
                _addr('Billing Address', _bill1, _bill2, _billCity, _billRegion,
                    _billPostal, _billCountry),

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
                          decoration: _dec('Primary Phone'))),
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
                          decoration: _dec('Billing Phone'))),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
