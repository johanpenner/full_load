import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class DispatcherSummaryScreen extends StatefulWidget {
  const DispatcherSummaryScreen({super.key});

  @override
  State<DispatcherSummaryScreen> createState() =>
      _DispatcherSummaryScreenState();
}

class _DispatcherSummaryScreenState extends State<DispatcherSummaryScreen> {
  Map<String, List<Map<String, dynamic>>> grouped = {};

  Future<void> fetchGroupedData() async {
    final snap = await FirebaseFirestore.instance.collection('loads').get();
    final docs = snap.docs.map((doc) => doc.data()).toList();

    final result = <String, List<Map<String, dynamic>>>{};

    for (final doc in docs) {
      final dispatcher = doc['dispatcherName'] ?? 'Unknown';
      result.putIfAbsent(dispatcher, () => []).add(doc);
    }

    setState(() {
      grouped = result;
    });
  }

  Future<void> exportToCSV() async {
    final rows = <List<String>>[
      ['Dispatcher', 'Loads', 'On-Time %', 'Total Revenue']
    ];

    grouped.forEach((dispatcher, loads) {
      final onTime = _calculateOnTime(loads);
      final revenue = _calculateRevenue(loads);
      rows.add([
        dispatcher,
        loads.length.toString(),
        '${onTime.toStringAsFixed(1)}%',
        '\$${revenue.toStringAsFixed(2)}'
      ]);
    });

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/dispatcher_export_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(path);
    await file.writeAsString(csv);
    Share.shareXFiles([XFile(file.path)], text: 'Dispatcher Summary CSV');
  }

  Future<void> exportToPDF() async {
    final pdf = pw.Document();
    final headers = ['Dispatcher', 'Loads', 'On-Time %', 'Total Revenue'];

    final rows = grouped.entries.map((e) {
      final dispatcher = e.key;
      final loads = e.value;
      final onTime = _calculateOnTime(loads);
      final revenue = _calculateRevenue(loads);

      return [
        dispatcher,
        '${loads.length}',
        '${onTime.toStringAsFixed(1)}%',
        '\$${revenue.toStringAsFixed(2)}'
      ];
    }).toList();

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Table.fromTextArray(
          headers: headers,
          data: rows,
          border: pw.TableBorder.all(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellPadding: const pw.EdgeInsets.all(6),
        ),
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/dispatcher_export_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    Share.shareXFiles([XFile(file.path)], text: 'Dispatcher Summary PDF');
  }

  double _calculateOnTime(List<Map<String, dynamic>> loads) {
    if (loads.isEmpty) return 0;
    int onTime = 0;
    for (final load in loads) {
      final expected = DateTime.tryParse(load['deliveryDate'] ?? '');
      final actual = DateTime.tryParse(load['deliveredAt'] ?? '');
      if (expected != null && actual != null && !actual.isAfter(expected)) {
        onTime++;
      }
    }
    return (onTime / loads.length) * 100;
  }

  double _calculateRevenue(List<Map<String, dynamic>> loads) {
    double total = 0;
    for (final load in loads) {
      final amount = double.tryParse(load['amount']?.toString() ?? '0');
      if (amount != null) total += amount;
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    fetchGroupedData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dispatcher Performance')),
      body: Column(
        children: [
          Expanded(
            child: grouped.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: grouped.entries.map((entry) {
                      final name = entry.key;
                      final loads = entry.value;
                      final onTime = _calculateOnTime(loads);
                      final revenue = _calculateRevenue(loads);
                      return ListTile(
                        title: Text(name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Loads: ${loads.length}"),
                            Text("On-Time: ${onTime.toStringAsFixed(1)}%"),
                            Text("Revenue: \$${revenue.toStringAsFixed(2)}"),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Export CSV'),
                  onPressed: exportToCSV,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                  onPressed: exportToPDF,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
