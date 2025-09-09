// lib/util/utils.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

String fmtTs(Timestamp? ts) =>
    ts != null ? DateFormat('MMM d, y HH:mm').format(ts.toDate()) : '';

String newId() =>
    FirebaseFirestore.instance.collection('dummy').doc().id;  // Random ID

// Add other utils...