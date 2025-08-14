import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'update_load_status.dart';

class DispatcherDashboard extends StatelessWidget {
  const DispatcherDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dispatcher Dashboard')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('loads')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final docId = docs[index].id;
              final data = docs[index].data() as Map<String, dynamic>;
              String selectedStatus = data['status'] ?? 'Planned';

              return Card(
                margin: const EdgeInsets.all(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Load #${data['loadNumber']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text("Driver: ${data['driverId'] ?? 'Unassigned'}"),
                      Text("Pickup: ${data['pickupDate'] ?? ''}"),
                      Text("Delivery: ${data['deliveryDate'] ?? ''}"),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedStatus,
                              decoration: const InputDecoration(labelText: 'Status'),
                              items: const [
                                DropdownMenuItem(value: 'Planned', child: Text('Planned')),
                                DropdownMenuItem(value: 'Assigned', child: Text('Assigned')),
                                DropdownMenuItem(value: 'En Route', child: Text('En Route')),
                                DropdownMenuItem(value: 'Delivered', child: Text('Delivered')),
                              ],
                              onChanged: (val) {
                                if (val != null) selectedStatus = val;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.update),
                            label: const Text('Update'),
                            onPressed: () async {
                              await updateLoadStatus(context, docId, selectedStatus);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
