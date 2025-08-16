// employee_summary_screen.dart — Summary + Filtered Export + ZIP file bundle

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:archive/archive_io.dart';

class EmployeeSummaryScreen extends StatefulWidget {
  const EmployeeSummaryScreen({super.key});

  @override
  State<EmployeeSummaryScreen> createState() => _EmployeeSummaryScreenState();
}

class _EmployeeSummaryScreenState extends State<EmployeeSummaryScreen> {
  int? loadFilter;
  DateTime? recentCutoff;

  final List<List<String>> filteredRows = [
    ['Name', 'Phone', 'Loads', 'Last Active', 'Days Off', 'Documents']
  ];

  Future<int> getLoadCount(String employeeId) async {
    final snap = await FirebaseFirestore.instance
        .collection('loads')
        .where('driverId', isEqualTo: employeeId)
        .get();
    return snap.docs.length;
  }

  Future<DateTime?> getLastActivity(String employeeId) async {
    final snap = await FirebaseFirestore.instance
        .collection('loads')
        .where('driverId', isEqualTo: employeeId)
        .orderBy('pickupDate', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return DateTime.tryParse(snap.docs.first['pickupDate']);
  }

  Future<void> exportFilteredCSV() async {
    final csvData = const ListToCsvConverter().convert(filteredRows);
    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}/filtered_employees_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(path);
    await file.writeAsString(csvData);
    Share.shareXFiles([XFile(file.path)], text: 'Filtered Employee Export');
  }

  Future<void> exportFilteredPDF() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (context) => pw.Table.fromTextArray(
          headers: filteredRows.first,
          data: filteredRows.skip(1).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          border: pw.TableBorder.all(),
          cellPadding: const pw.EdgeInsets.all(6),
        ),
      ),
    );
    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}/filtered_employees_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    Share.shareXFiles([XFile(file.path)], text: 'Filtered Employee PDF');
  }

  Future<void> exportAllEmployeeFilesAsZip() async {
    final directory = await getApplicationDocumentsDirectory();
    final encoder = ZipFileEncoder();
    final zipPath =
        '${directory.path}/employee_files_${DateTime.now().millisecondsSinceEpoch}.zip';
    encoder.create(zipPath);

    final snap = await FirebaseFirestore.instance.collection('employees').get();
    for (final doc in snap.docs) {
      final data = doc.data();
      final files = data['files'] ?? {};
      for (final entry in files.entries) {
        for (final filePath in entry.value) {
          final f = File(filePath);
          if (await f.exists()) {
            encoder.addFile(f);
          }
        }
      }
    }
    encoder.close();
    Share.shareXFiles([XFile(zipPath)], text: 'All Employee Files');
  }

  @override
  Widget build(BuildContext context) {
    filteredRows.removeRange(1, filteredRows.length);

    return Scaffold(
      appBar: AppBar(title: const Text('Employee Summary')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                DropdownButton<int?>(
                  hint: const Text('Min Load Count'),
                  value: loadFilter,
                  items: [null, 1, 3, 5, 10]
                      .map((val) => DropdownMenuItem(
                          value: val, child: Text(val?.toString() ?? 'All')))
                      .toList(),
                  onChanged: (val) => setState(() => loadFilter = val),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          DateTime.now().subtract(const Duration(days: 7)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => recentCutoff = picked);
                  },
                  child: Text(recentCutoff == null
                      ? 'Filter by Activity'
                      : 'After ${DateFormat('yyyy-MM-dd').format(recentCutoff!)}'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection('employees')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final id = docs[index].id;

                    return FutureBuilder(
                      future: Future.wait([
                        getLoadCount(id),
                        getLastActivity(id),
                      ]),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const ListTile(title: Text('Loading...'));
                        }
                        final int loadCount = snapshot.data![0] as int;
                        final DateTime? lastActive =
                            snapshot.data![1] as DateTime?;

                        if (loadFilter != null && loadCount < loadFilter!) {
                          return const SizedBox();
                        }
                        if (recentCutoff != null &&
                            (lastActive == null ||
                                lastActive.isBefore(recentCutoff!))) {
                          return const SizedBox();
                        }

                        final daysOff = data['availability']['daysOff'] ?? [];
                        final files = data['files'] ?? {};
                        final fileCount =
                            files.values.expand((v) => (v as List)).length;

                        filteredRows.add([
                          data['fullName'] ?? '',
                          data['phone'] ?? '',
                          '$loadCount',
                          lastActive?.toString().split(' ').first ?? '-',
                          daysOff
                              .map((e) => "${e['from']}➝${e['to']}")
                              .join(' | '),
                          '$fileCount',
                        ]);

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: ListTile(
                            title: Text(data['fullName'] ?? ''),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Phone: ${data['phone'] ?? ''}"),
                                Text("Loads: $loadCount"),
                                Text(
                                    "Last Active: ${lastActive?.toString().split(' ').first ?? 'N/A'}"),
                                if (daysOff.isNotEmpty)
                                  Text(
                                      "Days Off: ${daysOff.map((e) => "${e['from']}➝${e['to']}").join(' | ')}"),
                                if (fileCount > 0)
                                  Text("Documents: $fileCount"),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: exportFilteredCSV,
                  icon: const Icon(Icons.download),
                  label: const Text('Export Filtered CSV'),
                ),
                ElevatedButton.icon(
                  onPressed: exportFilteredPDF,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export Filtered PDF'),
                ),
                ElevatedButton.icon(
                  onPressed: exportAllEmployeeFilesAsZip,
                  icon: const Icon(Icons.archive),
                  label: const Text('Export Files ZIP'),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
