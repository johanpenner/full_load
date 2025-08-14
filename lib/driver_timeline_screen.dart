// driver_timeline_screen.dart — Visual timeline of loads assigned to a driver with dispatcher controls

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverTimelineScreen extends StatefulWidget {
  final String driverId;
  const DriverTimelineScreen({super.key, required this.driverId});

  @override
  State<DriverTimelineScreen> createState() => _DriverTimelineScreenState();
}

class _DriverTimelineScreenState extends State<DriverTimelineScreen> {
  Future<void> updateStatus(String loadId, String newStatus) async {
    await FirebaseFirestore.instance.collection('loads').doc(loadId).update({
      'status': newStatus,
    });
  }

  Future<void> reassignDriver(String loadId) async {
    final employees = await FirebaseFirestore.instance.collection('employees').get();
    String? selected;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reassign Driver'),
        content: DropdownButtonFormField<String>(
          value: selected,
          items: employees.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return DropdownMenuItem(
              value: doc.id,
              child: Text(data['fullName'] ?? ''),
            );
          }).toList(),
          onChanged: (val) => selected = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (selected != null) {
                await FirebaseFirestore.instance.collection('loads').doc(loadId).update({
                  'driverId': selected,
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Update'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Timeline')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('loads')
            .where('driverId', isEqualTo: widget.driverId)
            .orderBy('pickupDate')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final loads = snapshot.data!.docs;

          if (loads.isEmpty) {
            return const Center(child: Text('No assigned loads for this driver.'));
          }

          return ListView.builder(
            itemCount: loads.length,
            itemBuilder: (context, index) {
              final doc = loads[index];
              final data = doc.data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.all(8),
                child: ExpansionTile(
                  title: Text("Load #${data['loadNumber']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Status: ${data['status']}"),
                      Text("Pickup: ${data['pickupDate'] ?? 'N/A'}"),
                      Text("Delivery: ${data['deliveryDate'] ?? 'N/A'}"),
                    ],
                  ),
                  children: [
                    const Text("Stops:", style: TextStyle(fontWeight: FontWeight.bold)),
                    ...List.generate((data['stops'] as List).length, (i) {
                      final stop = data['stops'][i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text("• ${stop['type']} - ${stop['address']}")
                      );
                    }),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('Change Status'),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Update Status'),
                              content: DropdownButtonFormField<String>(
                                value: data['status'],
                                items: const [
                                  DropdownMenuItem(value: 'Planned', child: Text('Planned')),
                                  DropdownMenuItem(value: 'Assigned', child: Text('Assigned')),
                                  DropdownMenuItem(value: 'En Route', child: Text('En Route')),
                                  DropdownMenuItem(value: 'Delivered', child: Text('Delivered')),
                                ],
                                onChanged: (val) => updateStatus(doc.id, val!),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.person),
                          label: const Text('Reassign Driver'),
                          onPressed: () => reassignDriver(doc.id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
