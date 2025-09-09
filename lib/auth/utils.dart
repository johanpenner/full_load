<DOCUMENT filename="utils.dart">
// lib/util/utils.dart
// Updated: Added HOS calc (simplified FMCSA 11/14-hour rules with reset logic), distance/time formatters for maps (km/miles, hours/mins), safe file name (for uploads), status color chip (for dashboards), open maps (for addresses). Made cross-platform (no platform-specific), null-safe, exported for easy import.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

String fmtTs(Timestamp? ts) =>
    ts != null ? DateFormat('MMM d, y HH:mm').format(ts.toDate()) : '';

String newId() =>
    FirebaseFirestore.instance.collection('dummy').doc().id; // Random ID

String oneLine(String? s) =>
    (s ?? '').replaceAll('\n', ', ').replaceAll(RegExp(r'\s+'), ' ').trim();

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

Future<void> openMaps(String address) async {
  if (address.trim().isEmpty) return;
  final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    // Handle silently or log
  }
}

String safeFileName(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_');

String fmtDistance(double km, {bool useMetric = true}) {
  final dist = useMetric ? km : km * 0.621371;
  return '${dist.toStringAsFixed(1)} ${useMetric ? 'km' : 'mi'}';
}

String fmtDuration(Duration d) {
  final hours = d.inHours;
  final mins = d.inMinutes % 60;
  return '${hours}h ${mins}m';
}

// HOS calc (simplified: 11-drive/14-on-duty per day, 34h reset; real app integrate Samsara API)
Duration remainingHOS(Timestamp? lastLog, {int driveLimit = 11, int dutyLimit = 14}) {
  if (lastLog == null) return Duration(hours: driveLimit);
  final now = DateTime.now();
  final elapsed = now.difference(lastLog.toDate());
  if (elapsed > const Duration(hours: 34)) return Duration(hours: driveLimit); // Reset
  return Duration(hours: driveLimit) - elapsed;
}

Color statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'planned':
      return Colors.blueGrey;
    case 'assigned':
      return Colors.blue;
    case 'enroute':
      return Colors.deepPurple;
    case 'delivered':
      return Colors.green;
    case 'invoiced':
      return Colors.teal;
    case 'on_hold':
      return Colors.orange;
    case 'cancelled':
      return Colors.red;
    case 'waiting':
      return Colors.amber;
    case 'draft':
    default:
      return Colors.grey;
  }
}

Widget statusChip(String status) {
  final base = statusColor(status);
  return Chip(
    label: Text(status[0].toUpperCase() + status.substring(1)),
    backgroundColor: base.withOpacity(0.12),
    labelStyle: TextStyle(color: base, fontWeight: FontWeight.w600),
    side: BorderSide(color: base.withOpacity(0.35)),
  );
}
</DOCUMENT>