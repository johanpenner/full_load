import 'package:cloud_firestore/cloud_firestore.dart';

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
    );
  }
}
