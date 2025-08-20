// lib/clients_all_in_one.dart
// Clients: add/edit + list, logos, tap-to-call/SMS/email, Billing Profiles + Billing Rules.
// Save closes immediately; Firestore writes finish in the background.

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

// (kept if you use it elsewhere)
import 'util/storage_upload.dart';
import 'util/safe_image_picker.dart';

/// =======================
/// Utilities / IDs
/// =======================

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

/// Phone / SMS / Email helpers
String _digitsOnlyForDial(String? raw) =>
    (raw ?? '').replaceAll(RegExp(r'[^0-9+*#]'), '');

Future<void> _callNumber(BuildContext context, String? raw) async {
  final s = _digitsOnlyForDial(raw);
  if (s.isEmpty) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No phone number')));
    return;
  }
  final uri = Uri(scheme: 'tel', path: s);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No calling app available')));
  }
}

Future<void> _sendSms(BuildContext context, String? raw, {String? body}) async {
  final s = _digitsOnlyForDial(raw);
  if (s.isEmpty) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No mobile number')));
    return;
  }
  final smsUri = Uri(
    scheme: 'sms',
    path: s,
    queryParameters: { if ((body ?? '').trim().isNotEmpty) 'body': body!.trim() },
  );
  var ok = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
  if (!ok) {
    final alt = Uri(scheme: 'smsto', path: s);
    ok = await launchUrl(alt, mode: LaunchMode.externalApplication);
  }
  if (!ok) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No SMS app available')));
  }
}

Future<void> _composeEmail(BuildContext context, String email,
    {String? subject, String? body}) async {
  final e = email.trim();
  if (e.isEmpty) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No email address')));
    return;
  }
  final uri = Uri(
    scheme: 'mailto',
    path: e,
    queryParameters: {
      if ((subject ?? '').trim().isNotEmpty) 'subject': subject!.trim(),
      if ((body ?? '').trim().isNotEmpty) 'body': body!.trim(),
    },
  );
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No email app available')));
  }
}

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

/// Flexible contacts (division/person + type/value)
class ClientContactPoint {
  String id;
  String division; // e.g., Dispatch, Shipping, Accounting
  String person;   // who to talk to
  String type;     // 'work_phone' | 'mobile' | 'email'
  String value;    // number or email
  String ext;      // for work_phone
  bool primary;    // preferred for this type

  ClientContactPoint({
    String? id,
    this.division = '',
    this.person = '',
    this.type = 'work_phone',
    this.value = '',
    this.ext = '',
    this.primary = false,
  }) : id = id ?? _newId();

  Map<String, dynamic> toMap() => {
        'id': id,
        'division': division,
        'person': person,
        'type': type,
        'value': value,
        'ext': ext,
        'primary': primary,
      };

  factory ClientContactPoint.fromMap(Map<String, dynamic>? m) =>
      ClientContactPoint(
        id: (m?['id'] ?? _newId()).toString(),
        division: (m?['division'] ?? '').toString(),
        person: (m?['person'] ?? '').toString(),
        type: (m?['type'] ?? 'work_phone').toString(),
        value: (m?['value'] ?? '').toString(),
        ext: (m?['ext'] ?? '').toString(),
        primary: (m?['primary'] ?? false) as bool,
      );
}

/// =======================
/// Contact helpers (pretty text, best picks, badges)
/// =======================

String _cpPretty(ClientContactPoint cp) {
  switch (cp.type) {
    case 'work_phone':
      final ex = cp.ext.trim().isEmpty ? '' : ' ext ${cp.ext.trim()}';
      return '${cp.division.isNotEmpty ? '${cp.division} · ' : ''}'
             '${cp.person.isNotEmpty ? '${cp.person} · ' : ''}'
             '${cp.value}$ex';
    case 'mobile':
    case 'email':
      return '${cp.division.isNotEmpty ? '${cp.division} · ' : ''}'
             '${cp.person.isNotEmpty ? '${cp.person} · ' : ''}'
             '${cp.value}';
    default:
      return cp.value;
  }
}

ClientContactPoint? _bestPhone(List<ClientContactPoint> list) {
  if (list.isEmpty) return null;
  final workPrim = list.firstWhere(
      (c) => c.type == 'work_phone' && c.primary && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (workPrim.value.isNotEmpty) return workPrim;
  final workAny = list.firstWhere(
      (c) => c.type == 'work_phone' && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (workAny.value.isNotEmpty) return workAny;
  final mobPrim = list.firstWhere(
      (c) => c.type == 'mobile' && c.primary && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (mobPrim.value.isNotEmpty) return mobPrim;
  final mobAny = list.firstWhere(
      (c) => c.type == 'mobile' && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  return mobAny.value.isNotEmpty ? mobAny : null;
}

ClientContactPoint? _bestMobile(List<ClientContactPoint> list) {
  if (list.isEmpty) return null;
  final pri = list.firstWhere(
      (c) => c.type == 'mobile' && c.primary && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (pri.value.isNotEmpty) return pri;
  final any = list.firstWhere(
      (c) => c.type == 'mobile' && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  return any.value.isNotEmpty ? any : null;
}

ClientContactPoint? _bestEmail(List<ClientContactPoint> list) {
  if (list.isEmpty) return null;
  final pri = list.firstWhere(
      (c) => c.type == 'email' && c.primary && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (pri.value.isNotEmpty) return pri;
  final any = list.firstWhere(
      (c) => c.type == 'email' && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  return any.value.isNotEmpty ? any : null;
}

/// Top N divisions by occurrence in contact points
List<String> _topDivisions(List<ClientContactPoint> cps, {int max = 3}) {
  final counts = <String, int>{};
  for (final c in cps) {
    final d = c.division.trim();
    if (d.isEmpty) continue;
    counts[d] = (counts[d] ?? 0) + 1;
  }
  final top = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return top.take(max).map((e) => e.key).toList();
}

/// Small pill-style badge widget
Widget _divBadge(String text) => Container(
  margin: const EdgeInsets.only(top: 4, right: 6),
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  decoration: BoxDecoration(
    color: Colors.blueGrey.withOpacity(0.08),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.blueGrey.withOpacity(0.35)),
  ),
  child: Text(text, style: const TextStyle(fontSize: 11)),
);

  Map<String, dynamic> toMap() => {
        'id': id,
        'division': division,
        'person': person,
        'type': type,
        'value': value,
        'ext': ext,
        'primary': primary,
      };

  factory ClientContactPoint.fromMap(Map<String, dynamic>? m) =>
      ClientContactPoint(
        id: (m?['id'] ?? _newId()).toString(),
        division: (m?['division'] ?? '').toString(),
        person: (m?['person'] ?? '').toString(),
        type: (m?['type'] ?? 'work_phone').toString(),
        value: (m?['value'] ?? '').toString(),
        ext: (m?['ext'] ?? '').toString(),
        primary: (m?['primary'] ?? false) as bool,
      );
}

/// Billing Profile
class BillingProfile {
  String id;
  String name;
  String billToName;
  Address address;
  List<String> arEmails;
  List<String> ccEmails;
  int paymentTermsDays;
  bool poRequired;
  bool isDefault;
  String notes;

  BillingProfile({
    String? id,
    this.name = '',
    this.billToName = '',
    Address? address,
    List<String>? arEmails,
    List<String>? ccEmails,
    this.paymentTermsDays = 30,
    this.poRequired = false,
    this.isDefault = false,
    this.notes = '',
  })  : id = id ?? _newId(),
        address = address ?? Address(),
        arEmails = arEmails ?? <String>[],
        ccEmails = ccEmails ?? <String>[];

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'billToName': billToName,
        'address': address.toMap(),
        'arEmails': arEmails,
        'ccEmails': ccEmails,
        'paymentTermsDays': paymentTermsDays,
        'poRequired': poRequired,
        'isDefault': isDefault,
        'notes': notes,
      };

  factory BillingProfile.fromMap(Map<String, dynamic>? m) => BillingProfile(
        id: (m?['id'] ?? _newId()).toString(),
        name: (m?['name'] ?? '').toString(),
        billToName: (m?['billToName'] ?? '').toString(),
        address: Address.fromMap(m?['address'] as Map<String, dynamic>?),
        arEmails: (m?['arEmails'] is List)
            ? List<String>.from(m!['arEmails'])
            : <String>[],
        ccEmails: (m?['ccEmails'] is List)
            ? List<String>.from(m!['ccEmails'])
            : <String>[],
        paymentTermsDays: (m?['paymentTermsDays'] ?? 30) is int
            ? (m?['paymentTermsDays'] as int)
            : int.tryParse((m?['paymentTermsDays'] ?? '30').toString()) ?? 30,
        poRequired: (m?['poRequired'] ?? false) as bool,
        isDefault: (m?['isDefault'] ?? false) as bool,
        notes: (m?['notes'] ?? '').toString(),
      );
}

/// Billing Rule
class BillingRule {
  String id;
  String label;
  String triggerType; // 'productTag' | 'always'
  String value;
  String billingProfileId;
  int priority;

  BillingRule({
    String? id,
    this.label = '',
    this.triggerType = 'productTag',
    this.value = '',
    this.billingProfileId = '',
    this.priority = 100,
  }) : id = id ?? _newId();

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'triggerType': triggerType,
        'value': value,
        'billingProfileId': billingProfileId,
        'priority': priority,
      };

  factory BillingRule.fromMap(Map<String, dynamic>? m) => BillingRule(
        id: (m?['id'] ?? _newId()).toString(),
        label: (m?['label'] ?? '').toString(),
        triggerType: (m?['triggerType'] ?? 'productTag').toString(),
        value: (m?['value'] ?? '').toString(),
        billingProfileId: (m?['billingProfileId'] ?? '').toString(),
        priority: (m?['priority'] ?? 100) is int
            ? (m?['priority'] as int)
            : int.tryParse((m?['priority'] ?? '100').toString()) ?? 100,
      );
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

  List<BillingProfile> billingProfiles;
  List<BillingRule> billingRules;

  // NEW: division/person contact points
  List<ClientContactPoint> contactPoints;

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
    List<BillingProfile>? billingProfiles,
    List<BillingRule>? billingRules,
    List<ClientContactPoint>? contactPoints,
  })  : mailingAddress = mailingAddress ?? Address(),
        billingAddress = billingAddress ?? Address(),
        primaryContact = primaryContact ?? Contact(),
        billingContact = billingContact ?? Contact(),
        tags = tags ?? [],
        billingProfiles = billingProfiles ?? <BillingProfile>[],
        billingRules = billingRules ?? <BillingRule>[],
        contactPoints = contactPoints ?? <ClientContactPoint>[];

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
        'billingProfiles': billingProfiles.map((e) => e.toMap()).toList(),
        'billingRules': billingRules.map((e) => e.toMap()).toList(),
        'contactPoints': contactPoints.map((e) => e.toMap()).toList(),
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
      paymentTermsDays: (m['paymentTermsDays'] ?? 30) is int
          ? m['paymentTermsDays'] as int
          : int.tryParse((m['paymentTermsDays'] ?? '30').toString()) ?? 30,
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
      billingProfiles: (m['billingProfiles'] is List)
          ? (m['billingProfiles'] as List)
              .map((x) => BillingProfile.fromMap(x as Map<String, dynamic>?))
              .toList()
          : <BillingProfile>[],
      billingRules: (m['billingRules'] is List)
          ? (m['billingRules'] as List)
              .map((x) => BillingRule.fromMap(x as Map<String, dynamic>?))
              .toList()
          : <BillingRule>[],
      contactPoints: (m['contactPoints'] is List)
          ? (m['contactPoints'] as List)
              .map(
                  (x) => ClientContactPoint.fromMap(x as Map<String, dynamic>?))
              .toList()
          : <ClientContactPoint>[],
    );
  }
}

/// =======================
/// Helpers
/// =======================

String _digitsOnlyForDial(String? raw) =>
    (raw ?? '').replaceAll(RegExp(r'[^0-9+*#]'), '');

Future<void> _callNumber(BuildContext context, String? raw) async {
  final s = _digitsOnlyForDial(raw);
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

Future<void> _sendSms(BuildContext context, String? raw, {String? body}) async {
  final s = _digitsOnlyForDial(raw);
  if (s.isEmpty) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No mobile number')));
    return;
  }
  // Try sms:, fallback to smsto:
  final smsUri = Uri(
    scheme: 'sms',
    path: s,
    queryParameters: {
      if ((body ?? '').trim().isNotEmpty) 'body': body!.trim(),
    },
  );
  var ok = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
  if (!ok) {
    final alt = Uri(scheme: 'smsto', path: s);
    ok = await launchUrl(alt, mode: LaunchMode.externalApplication);
  }
  if (!ok) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No SMS app available')));
  }
}

Future<void> _composeEmail(BuildContext context, String email,
    {String? subject, String? body}) async {
  final e = (email).trim();
  if (e.isEmpty) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No email address')));
    return;
  }
  final uri = Uri(
    scheme: 'mailto',
    path: e,
    queryParameters: {
      if ((subject ?? '').trim().isNotEmpty) 'subject': subject!.trim(),
      if ((body ?? '').trim().isNotEmpty) 'body': body!.trim(),
    },
  );
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No email app available')));
  }
}

String _cpPretty(ClientContactPoint cp) {
  switch (cp.type) {
    case 'work_phone':
      final ext = cp.ext.trim().isEmpty ? '' : ' ext ${cp.ext.trim()}';
      return '${cp.division.isNotEmpty ? '${cp.division} · ' : ''}'
          '${cp.person.isNotEmpty ? '${cp.person} · ' : ''}'
          '${cp.value}$ext';
    case 'mobile':
      return '${cp.division.isNotEmpty ? '${cp.division} · ' : ''}'
          '${cp.person.isNotEmpty ? '${cp.person} · ' : ''}'
          '${cp.value}';
    case 'email':
      return '${cp.division.isNotEmpty ? '${cp.division} · ' : ''}'
          '${cp.person.isNotEmpty ? '${cp.person} · ' : ''}'
          '${cp.value}';
    default:
      return cp.value;
  }
}

ClientContactPoint? _bestPhone(List<ClientContactPoint> list) {
  if (list.isEmpty) return null;
  final workPrim = list.firstWhere(
      (c) => c.type == 'work_phone' && c.primary && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (workPrim.value.isNotEmpty) return workPrim;
  final workAny = list.firstWhere(
      (c) => c.type == 'work_phone' && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (workAny.value.isNotEmpty) return workAny;
  final mobPrim = list.firstWhere(
      (c) => c.type == 'mobile' && c.primary && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (mobPrim.value.isNotEmpty) return mobPrim;
  final mobAny = list.firstWhere(
      (c) => c.type == 'mobile' && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (mobAny.value.isNotEmpty) return mobAny;
  return null;
}

ClientContactPoint? _bestMobile(List<ClientContactPoint> list) {
  if (list.isEmpty) return null;
  final pri = list.firstWhere(
      (c) => c.type == 'mobile' && c.primary && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (pri.value.isNotEmpty) return pri;
  final any = list.firstWhere(
      (c) => c.type == 'mobile' && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  return any.value.isNotEmpty ? any : null;
}

ClientContactPoint? _bestEmail(List<ClientContactPoint> list) {
  if (list.isEmpty) return null;
  final pri = list.firstWhere(
      (c) => c.type == 'email' && c.primary && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  if (pri.value.isNotEmpty) return pri;
  final any = list.firstWhere(
      (c) => c.type == 'email' && c.value.trim().isNotEmpty,
      orElse: () => ClientContactPoint(value: ''));
  return any.value.isNotEmpty ? any : null;
}

List<String> _topDivisions(List<ClientContactPoint> cps, {int max = 3}) {
  final counts = <String, int>{};
  for (final c in cps) {
    final d = c.division.trim();
    if (d.isEmpty) continue;
    counts[d] = (counts[d] ?? 0) + 1;
  }
  final top = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return top.take(max).map((e) => e.key).toList();
}

Widget _divBadge(String text) => Container(
      margin: const EdgeInsets.only(top: 4, right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.35)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );

/// Pick billing profile by simple rules
BillingProfile? pickBillingProfileForLoad({
  required List<BillingProfile> profiles,
  required List<BillingRule> rules,
  List<String> productTags = const [],
}) {
  final tags = productTags.map((t) => t.toLowerCase().trim()).toSet();
  final sorted = [...rules]..sort((a, b) => a.priority.compareTo(b.priority));
  for (final r in sorted) {
    if (r.triggerType == 'always') {
      final p = profiles.where((p) => p.id == r.billingProfileId);
      if (p.isNotEmpty) return p.first;
    } else if (r.triggerType == 'productTag') {
      if (r.value.isNotEmpty && tags.contains(r.value.toLowerCase())) {
        final p = profiles.where((p) => p.id == r.billingProfileId);
        if (p.isNotEmpty) return p.first;
      }
    }
  }
  final def = profiles.where((p) => p.isDefault);
  if (def.isNotEmpty) return def.first;
  return profiles.isNotEmpty ? profiles.first : null;
}

/// =======================
/// Edit Screen
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

  // Logo
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

  List<BillingProfile> _billingProfiles = <BillingProfile>[];
  List<BillingRule> _billingRules = <BillingRule>[];
  String? _defaultProfileId;

  // NEW: contact points
  List<ClientContactPoint> _contactPoints = <ClientContactPoint>[];

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

      _billingProfiles = [..._client.billingProfiles];
      _billingRules = [..._client.billingRules]
        ..sort((a, b) => a.priority.compareTo(b.priority));
      _defaultProfileId = _billingProfiles
          .firstWhere(
            (p) => p.isDefault,
            orElse: () => (_billingProfiles.isNotEmpty
                ? _billingProfiles.first
                : BillingProfile()),
          )
          .id;

      _contactPoints = [..._client.contactPoints];
      // ensure single primary per type
      for (final t in ['work_phone', 'mobile', 'email']) {
        final prims = _contactPoints.where((c) => c.type == t && c.primary);
        if (prims.length > 1) {
          bool keep = true;
          for (final c in prims) {
            if (keep) {
              keep = false;
            } else {
              c.primary = false;
            }
          }
        }
      }
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
        // Simple picker; you can swap to your SafeImagePicker if desired.
        final picker = ImagePicker();
        final x = await picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1200,
            maxHeight: 1200,
            imageQuality: 85);
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

  Future<String?> _uploadLogoSilently({
    required String docId,
    Uint8List? bytes,
    String? path,
  }) async {
    try {
      if (bytes == null && (path == null || kIsWeb)) return null;
      final ref = FirebaseStorage.instance
          .ref()
          .child('client_logos')
          .child('$docId.jpg');
      if (bytes != null) {
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(io.File(path!));
      }
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeLogo() async {
    if (_newLogoBytes != null || _newLogoPath != null) {
      setState(() {
        _newLogoBytes = null;
        _newLogoPath = null;
      });
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Logo cleared')));
      return;
    }
    if (widget.clientId == null || _client.logoUrl.isEmpty) return;

    try {
      try {
        await FirebaseStorage.instance.refFromURL(_client.logoUrl).delete();
      } catch (_) {}
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId!)
          .update({'logoUrl': ''});
      if (!mounted) return;
      setState(() => _client.logoUrl = '');
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Logo removed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Failed to remove logo: $e')));
    }
  }

  void _popNextFrame(Map<String, dynamic> result) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rootNav = Navigator.of(context, rootNavigator: true);
      if (rootNav.canPop()) {
        rootNav.pop(result);
      }
    });
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

    // ensure single default profile flag matches _defaultProfileId
    for (final p in _billingProfiles) {
      p.isDefault = (p.id == _defaultProfileId);
    }
    if (_billingProfiles.isNotEmpty &&
        !_billingProfiles.any((p) => p.isDefault)) {
      _billingProfiles.first.isDefault = true;
      _defaultProfileId = _billingProfiles.first.id;
    }

    final isNew = widget.clientId == null;
    final existingId = widget.clientId;
    final logoBytes = _newLogoBytes;
    final logoPath = _newLogoPath;

    final payload = Client(
      id: existingId ?? '',
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
      primaryContact:
          Contact(name: _pName.text, email: _pEmail.text, phone: _pPhone.text),
      billingContact:
          Contact(name: _bName.text, email: _bEmail.text, phone: _bPhone.text),
      dispatchEmail: _dispatchEmail.text.trim(),
      invoiceEmail: _invoiceEmail.text.trim(),
      notes: _notes.text.trim(),
      logoUrl: _client.logoUrl,
      billingProfiles: _billingProfiles,
      billingRules: _billingRules
        ..sort((a, b) => a.priority.compareTo(b.priority)),
      contactPoints: _contactPoints,
    );

    setState(() => _saving = true);

    // Close immediately (list will toast)
    final result = {
      'action': isNew ? 'created' : 'updated',
      'name': _display.text.trim(),
    };
    _popNextFrame(result);

    () async {
      try {
        final ref = FirebaseFirestore.instance.collection('clients');
        String docId;
        if (isNew) {
          final added = await ref.add(payload.toMap());
          docId = added.id;
        } else {
          docId = existingId!;
          await ref.doc(docId).update(payload.toMap());
        }

        final newUrl = await _uploadLogoSilently(
          docId: docId,
          bytes: logoBytes,
          path: logoPath,
        );
        if (newUrl != null) {
          await ref.doc(docId).update({'logoUrl': newUrl});
        }
      } catch (_) {}
    }();
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
      _popNextFrame({'action': 'deleted', 'name': name});
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

                // Core info
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
                    value: const ['none', 'warn', 'red'].contains(_alertLevel)
                        ? _alertLevel
                        : 'none',
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

                // ========= Contacts (Division / Person / Channels) =========
                const Divider(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Contacts (by Division)',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    if (_contactPoints.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No contacts added yet.'),
                      ),
                    for (int i = 0; i < _contactPoints.length; i++)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            _contactPoints[i].type == 'email'
                                ? Icons.email_outlined
                                : Icons.call_outlined,
                          ),
                          title: Text(
                            _cpPretty(_contactPoints[i]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${_contactPoints[i].type}'
                            '${_contactPoints[i].primary ? ' • primary' : ''}',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              // Quick actions per contact
                              if (_contactPoints[i].type == 'email')
                                IconButton(
                                  tooltip: 'Email',
                                  icon: const Icon(Icons.email_outlined),
                                  onPressed: () => _composeEmail(
                                      context, _contactPoints[i].value),
                                ),
                              if (_contactPoints[i].type == 'work_phone' ||
                                  _contactPoints[i].type == 'mobile')
                                IconButton(
                                  tooltip: 'Call',
                                  icon: const Icon(Icons.call),
                                  onPressed: () => _callNumber(
                                      context, _contactPoints[i].value),
                                ),
                              if (_contactPoints[i].type == 'mobile')
                                IconButton(
                                  tooltip: 'Text',
                                  icon: const Icon(Icons.sms_outlined),
                                  onPressed: () => _sendSms(
                                      context, _contactPoints[i].value),
                                ),
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _openContactPointDialog(
                                    index: i, existing: _contactPoints[i]),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    setState(() => _contactPoints.removeAt(i)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _openContactPointDialog(),
                        icon: const Icon(Icons.add_ic_call),
                        label: const Text('Add Contact'),
                      ),
                    ),
                  ],
                ),

                // ========= Billing Profiles =========
                const Divider(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Billing Profiles',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    for (final p in _billingProfiles)
                      Card(
                        child: RadioListTile<String>(
                          value: p.id,
                          groupValue: _defaultProfileId,
                          onChanged: (id) {
                            setState(() {
                              _defaultProfileId = id;
                              for (var x in _billingProfiles) {
                                x.isDefault = (x.id == id);
                              }
                            });
                          },
                          title: Text(
                              (p.name.isEmpty ? p.billToName : p.name).isEmpty
                                  ? 'Profile'
                                  : (p.name.isEmpty ? p.billToName : p.name)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (p.billToName.isNotEmpty)
                                Text(p.billToName,
                                    style:
                                        const TextStyle(color: Colors.black54)),
                              if (p.arEmails.isNotEmpty)
                                Text(p.arEmails.join(', '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                          secondary: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _openProfileDialog(
                                    index: _billingProfiles.indexOf(p),
                                    existing: p),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () {
                                  setState(() {
                                    final idx = _billingProfiles.indexOf(p);
                                    _billingProfiles.removeAt(idx);
                                    if (_billingProfiles.isEmpty) {
                                      _defaultProfileId = null;
                                    } else if (_defaultProfileId == p.id) {
                                      _billingProfiles.first.isDefault = true;
                                      _defaultProfileId =
                                          _billingProfiles.first.id;
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _openProfileDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Billing Profile'),
                      ),
                    ),
                  ],
                ),

                // ========= Billing Rules =========
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Billing Rules',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    for (final r in _billingRules)
                      ListTile(
                        leading: const Icon(Icons.rule),
                        title: Text(r.label.isEmpty ? 'Rule' : r.label),
                        subtitle: Text(
                          'When: ${r.triggerType}'
                          '${r.triggerType == 'productTag' && r.value.isNotEmpty ? '="${r.value}"' : ''} • '
                          'Then: ${_billingProfiles.firstWhere(
                                (p) => p.id == r.billingProfileId,
                                orElse: () => BillingProfile(name: 'Unknown'),
                              ).name.isEmpty ? _billingProfiles.firstWhere(
                                (p) => p.id == r.billingProfileId,
                                orElse: () =>
                                    BillingProfile(billToName: 'Unknown'),
                              ).billToName : _billingProfiles.firstWhere(
                                (p) => p.id == r.billingProfileId,
                                orElse: () => BillingProfile(name: 'Unknown'),
                              ).name} • Priority: ${r.priority}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Edit rule',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _openRuleDialog(
                                  index: _billingRules.indexOf(r), existing: r),
                            ),
                            IconButton(
                              tooltip: 'Delete rule',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => setState(() => _billingRules
                                  .removeWhere((x) => x.id == r.id)),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _openRuleDialog(),
                        icon: const Icon(Icons.add_task),
                        label: const Text('Add Billing Rule'),
                      ),
                    ),
                  ],
                ),

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

  // ===== Dialogs =====

  Future<void> _openProfileDialog(
      {int? index, BillingProfile? existing}) async {
    final isEdit = index != null && existing != null;

    final name = TextEditingController(text: existing?.name ?? '');
    final billToName = TextEditingController(text: existing?.billToName ?? '');
    final line1 = TextEditingController(text: existing?.address.line1 ?? '');
    final line2 = TextEditingController(text: existing?.address.line2 ?? '');
    final city = TextEditingController(text: existing?.address.city ?? '');
    final region = TextEditingController(text: existing?.address.region ?? '');
    final postal =
        TextEditingController(text: existing?.address.postalCode ?? '');
    final country =
        TextEditingController(text: existing?.address.country ?? 'CA');
    final ar =
        TextEditingController(text: (existing?.arEmails ?? []).join(', '));
    final cc =
        TextEditingController(text: (existing?.ccEmails ?? []).join(', '));
    final terms = TextEditingController(
        text: (existing?.paymentTermsDays ?? 30).toString());
    bool poRequired = existing?.poRequired ?? false;
    bool isDefault = existing?.isDefault ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isEdit ? 'Edit Billing Profile' : 'New Billing Profile'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Profile Name *')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: billToName,
                      decoration:
                          const InputDecoration(labelText: 'Bill To Name *')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: line1,
                      decoration:
                          const InputDecoration(labelText: 'Address Line 1')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: line2,
                      decoration:
                          const InputDecoration(labelText: 'Address Line 2')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: city,
                            decoration:
                                const InputDecoration(labelText: 'City'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: region,
                            decoration: const InputDecoration(
                                labelText: 'Province/State'))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: postal,
                            decoration: const InputDecoration(
                                labelText: 'Postal/ZIP'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: country,
                            decoration:
                                const InputDecoration(labelText: 'Country'))),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                      controller: ar,
                      decoration: const InputDecoration(
                          labelText: 'A/R Emails (comma separated)')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: cc,
                      decoration: const InputDecoration(
                          labelText: 'CC Emails (comma separated)')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: terms,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Payment Terms (days)'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: SwitchListTile(
                      value: poRequired,
                      onChanged: (v) => setLocal(() => poRequired = v),
                      title: const Text('PO Required'),
                    )),
                  ]),
                  SwitchListTile(
                    value: isDefault,
                    onChanged: (v) => setLocal(() => isDefault = v),
                    title: const Text('Default profile'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(isEdit ? 'Save' : 'Add')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final p = BillingProfile(
        id: existing?.id,
        name: name.text.trim(),
        billToName: billToName.text.trim(),
        address: Address(
          line1: line1.text.trim(),
          line2: line2.text.trim(),
          city: city.text.trim(),
          region: region.text.trim(),
          postalCode: postal.text.trim(),
          country: country.text.trim().isEmpty ? 'CA' : country.text.trim(),
        ),
        arEmails: ar.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        ccEmails: cc.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        paymentTermsDays: int.tryParse(terms.text.trim()) ?? 30,
        poRequired: poRequired,
        isDefault: isDefault,
      );

      setState(() {
        if (p.isDefault) {
          for (var x in _billingProfiles) {
            x.isDefault = false;
          }
          _defaultProfileId = p.id;
        }
        if (isEdit) {
          _billingProfiles[index!] = p;
          if (p.isDefault) _defaultProfileId = p.id;
        } else {
          _billingProfiles.add(p);
          if (_defaultProfileId == null || p.isDefault) {
            for (var x in _billingProfiles) {
              x.isDefault = false;
            }
            _billingProfiles.last.isDefault = true;
            _defaultProfileId = _billingProfiles.last.id;
          }
        }
      });
    }
  }

  Future<void> _openRuleDialog({int? index, BillingRule? existing}) async {
    if (_billingProfiles.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
            content: Text('Add at least one Billing Profile first.')),
      );
      return;
    }

    final isEdit = index != null && existing != null;

    String label = existing?.label ?? '';
    String triggerType = existing?.triggerType ?? 'productTag';
    final valueCtrl = TextEditingController(text: existing?.value ?? '');
    String billingProfileId =
        existing?.billingProfileId ?? _billingProfiles.first.id;
    final priorityCtrl =
        TextEditingController(text: (existing?.priority ?? 100).toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isEdit ? 'Edit Billing Rule' : 'New Billing Rule'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: TextEditingController(text: label),
                  onChanged: (v) => label = v,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: ['productTag', 'always'].contains(triggerType)
                      ? triggerType
                      : 'productTag',
                  items: const [
                    DropdownMenuItem(
                        value: 'productTag',
                        child: Text('When product tag equals…')),
                    DropdownMenuItem(
                        value: 'always', child: Text('Always (catch-all)')),
                  ],
                  onChanged: (v) =>
                      setLocal(() => triggerType = v ?? 'productTag'),
                  decoration: const InputDecoration(labelText: 'Trigger'),
                ),
                const SizedBox(height: 8),
                if (triggerType == 'productTag')
                  TextField(
                    controller: valueCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Product Tag (e.g., chemicals, steel)'),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _billingProfiles.any((p) => p.id == billingProfileId)
                      ? billingProfileId
                      : _billingProfiles.first.id,
                  items: _billingProfiles
                      .map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name.isEmpty
                                ? (p.billToName.isEmpty
                                    ? 'Profile'
                                    : p.billToName)
                                : p.name),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setLocal(() => billingProfileId = v ?? billingProfileId),
                  decoration:
                      const InputDecoration(labelText: 'Bill using profile'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priorityCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Priority (lower runs first)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(isEdit ? 'Save' : 'Add')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final rule = BillingRule(
        id: existing?.id,
        label: label.trim().isEmpty
            ? (triggerType == 'always'
                ? 'Always'
                : 'Tag: ${valueCtrl.text.trim()}')
            : label.trim(),
        triggerType: triggerType,
        value: triggerType == 'productTag'
            ? valueCtrl.text.trim().toLowerCase()
            : '',
        billingProfileId: billingProfileId,
        priority: int.tryParse(priorityCtrl.text.trim()) ?? 100,
      );

      setState(() {
        if (isEdit) {
          _billingRules[index!] = rule;
        } else {
          _billingRules.add(rule);
        }
        _billingRules.sort((a, b) => a.priority.compareTo(b.priority));
      });
    }
  }

  Future<void> _openContactPointDialog(
      {int? index, ClientContactPoint? existing}) async {
    final isEdit = index != null && existing != null;
    String type = existing?.type ?? 'work_phone';
    final division = TextEditingController(text: existing?.division ?? '');
    final person = TextEditingController(text: existing?.person ?? '');
    final value = TextEditingController(text: existing?.value ?? '');
    final ext = TextEditingController(text: existing?.ext ?? '');
    bool primary = existing?.primary ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isEdit ? 'Edit Contact' : 'Add Contact'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: ['work_phone', 'mobile', 'email'].contains(type)
                      ? type
                      : 'work_phone',
                  items: const [
                    DropdownMenuItem(
                        value: 'work_phone', child: Text('Work Phone')),
                    DropdownMenuItem(value: 'mobile', child: Text('Mobile')),
                    DropdownMenuItem(value: 'email', child: Text('Email')),
                  ],
                  onChanged: (v) => setLocal(() => type = v ?? 'work_phone'),
                  decoration: const InputDecoration(labelText: 'Type'),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: division,
                    decoration: const InputDecoration(
                        labelText: 'Division (Dispatch, Shipping, etc.)')),
                const SizedBox(height: 8),
                TextField(
                    controller: person,
                    decoration:
                        const InputDecoration(labelText: 'Person to talk to')),
                const SizedBox(height: 8),
                TextField(
                  controller: value,
                  decoration: InputDecoration(
                    labelText: type == 'email'
                        ? 'Email'
                        : (type == 'mobile' ? 'Mobile Number' : 'Work Phone'),
                  ),
                  keyboardType: type == 'email'
                      ? TextInputType.emailAddress
                      : TextInputType.phone,
                ),
                if (type == 'work_phone') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: ext,
                    decoration: const InputDecoration(
                        labelText: 'Extension (optional)'),
                    keyboardType: TextInputType.number,
                  ),
                ],
                SwitchListTile(
                  value: primary,
                  onChanged: (v) => setLocal(() => primary = v),
                  title: const Text('Set as primary for this type'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(isEdit ? 'Save' : 'Add')),
          ],
        ),
      ),
    );

    if (ok == true) {
      if (primary) {
        for (final c in _contactPoints) {
          if (c.type == type) c.primary = false;
        }
      }

      final cp = ClientContactPoint(
        id: existing?.id,
        division: division.text.trim(),
        person: person.text.trim(),
        type: type,
        value: value.text.trim(),
        ext: type == 'work_phone' ? ext.text.trim() : '',
        primary: primary,
      );

      setState(() {
        if (isEdit) {
          _contactPoints[index!] = cp;
        } else {
          _contactPoints.add(cp);
        }
      });
    }
  }
}

/// =======================
/// List Screen
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

              final bestPhone = _bestPhone(cl.contactPoints);
              final phone = (bestPhone?.value ?? '').isNotEmpty
                  ? bestPhone!.value
                  : (cl.primaryContact.phone.isNotEmpty
                      ? cl.primaryContact.phone
                      : cl.billingContact.phone);

              final bestMobile = _bestMobile(cl.contactPoints);
              final mobile = (bestMobile?.value ?? '');

              final emCP = _bestEmail(cl.contactPoints);
              final emailForSubtitle = (emCP?.value ?? '').isNotEmpty
                  ? emCP!.value
                  : (cl.billingContact.email.isNotEmpty
                      ? cl.billingContact.email
                      : cl.primaryContact.email);

              final divisions = _topDivisions(cl.contactPoints, max: 3);

              final alertIcon = cl.alertLevel == 'red'
                  ? const Icon(Icons.warning, color: Colors.red)
                  : cl.alertLevel == 'warn'
                      ? const Icon(Icons.warning, color: Colors.orange)
                      : null;

              final subtitleText = emailForSubtitle.isNotEmpty
                  ? emailForSubtitle
                  : (bestPhone != null ? _cpPretty(bestPhone) : '');

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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtitleText,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (divisions.isNotEmpty)
                      Wrap(children: divisions.map(_divBadge).toList()),
                  ],
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    if (alertIcon != null) alertIcon,
                    IconButton(
                      tooltip: emailForSubtitle.isEmpty ? 'No email' : 'Email',
                      icon: const Icon(Icons.email_outlined),
                      onPressed: emailForSubtitle.isEmpty
                          ? null
                          : () => _composeEmail(context, emailForSubtitle),
                    ),
                    IconButton(
                      tooltip: phone.isEmpty ? 'No phone' : 'Call',
                      icon: const Icon(Icons.call),
                      onPressed: phone.isEmpty
                          ? null
                          : () => _callNumber(context, phone),
                    ),
                    IconButton(
                      tooltip: mobile.isEmpty ? 'No mobile' : 'Text',
                      icon: const Icon(Icons.sms_outlined),
                      onPressed: mobile.isEmpty
                          ? null
                          : () => _sendSms(context, mobile),
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
