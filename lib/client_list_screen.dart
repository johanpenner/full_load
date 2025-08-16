import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/client_model.dart';
import 'client_edit_screen.dart';

class ClientListScreen extends StatelessWidget {
  const ClientListScreen({super.key});

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
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ClientEditScreen()),
            ),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (c, snap) {
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs.map((d) => Client.fromDoc(d)).toList();
          if (docs.isEmpty) return const Center(child: Text('No clients yet'));
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final cl = docs[i];
              final alertColor = cl.alertLevel == 'red'
                  ? Colors.red
                  : cl.alertLevel == 'warn'
                      ? Colors.orange
                      : null;
              return ListTile(
                title: Text(cl.displayName),
                subtitle: Text(cl.billingContact.email.isNotEmpty
                    ? cl.billingContact.email
                    : cl.primaryContact.email),
                trailing:
                    cl.prepayRequired ? const Icon(Icons.lock, size: 18) : null,
                leading: alertColor == null
                    ? const Icon(Icons.business)
                    : Icon(Icons.warning, color: alertColor),
                onTap: () => Navigator.push(
                  _,
                  MaterialPageRoute(
                      builder: (_) => ClientEditScreen(clientId: cl.id)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
