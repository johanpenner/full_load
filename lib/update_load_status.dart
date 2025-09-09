// lib/update_load_status.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

Future<bool?> updateLoadStatus(
    BuildContext context, String loadId, String roleName) async {
  String status = 'planned';
  final meta = <String, dynamic>{};

  bool isYard = false;
  bool isWaiting = false;
  bool isHold = false;
  final location = TextEditingController();
  final note = TextEditingController();

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: StatefulBuilder(builder: (ctx, setState) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Update Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: -6,
                children: [
                  for (final s in const [
                    'planned',
                    'assigned',
                    'enroute',
                    'yard',
                    'waiting_delivery',
                    'delivered',
                    'invoiced',
                    'on_hold',
                    'canceled'
                  ])
                    ChoiceChip(
                      label: Text(_cap(s)),
                      selected: status == s,
                      onSelected: (_) {
                        setState(() {
                          status = s;
                          isYard = s == 'yard';
                          isWaiting = s == 'waiting_delivery';
                          isHold = s == 'on_hold';
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (isYard) ...[
                const Text('Dropped in yard — where is the trailer now?'),
                const SizedBox(height: 6),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(
                    labelText: 'Yard / Address',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (isWaiting) ...[
                const Text('Waiting for delivery — where is it waiting?'),
                const SizedBox(height: 6),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(
                    labelText: 'Address / Location',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (isHold) ...[
                const Text('On hold — reason'),
                const SizedBox(height: 6),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const Text('Notes (optional)'),
              const SizedBox(height: 6),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      meta['byRole'] = roleName;
                      if (location.text.trim().isNotEmpty) {
                        meta['location'] = location.text.trim();
                      }
                      if (note.text.trim().isNotEmpty) {
                        meta['note'] = note.text.trim();
                      }

                      await FirebaseFirestore.instance
                          .collection('loads')
                          .doc(loadId)
                          .set(
                        {
                          'status': status,
                          'statusMeta': meta,
                          'updatedAt': FieldValue.serverTimestamp(),
                        },
                        SetOptions(merge: true),
                      );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      }),
    ),
  );

  location.dispose();
  note.dispose();
  return result;
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
