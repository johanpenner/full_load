// lib/driver_timeline_screen.dart
// Horizontal timeline of loads for a driver.
// Updates: Added role gating (e.g., edit/update/reassign only for dispatchers/admins), realtime stream with error/loading, safe null-handling, zoom gestures, integrated formatting from utils, async safety.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'widgets/main_menu_button.dart';
import 'quick_load_screen.dart';

// Roles system
import 'auth/roles.dart';
import 'auth/current_user_role.dart';

// Utils (for fmtTs, etc.—assume you have it)
import 'util/utils.dart';

class DriverTimelineScreen extends StatefulWidget {
  final String driverId;
  const DriverTimelineScreen({super.key, required this.driverId});

  @override
  State<DriverTimelineScreen> createState() => _DriverTimelineScreenState();
}

class _DriverTimelineScreenState extends State<DriverTimelineScreen> {
  AppRole _role = AppRole.viewer;
  double _pxPerHour = 48; // between 24 and 120 for zoom

  static const double _axisHeight = 50.0;
  static const double _laneHeight = 80.0;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    _role = await currentUserRole();
    setState(() {});
  }

  // ---------- fire updates ----------

  Future<void> _updateStatus(String loadId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('loads').doc(loadId).update({
        'status': newStatus,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Status updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  Future<void> _reassignDriver(String loadId) async {
    final driversSnap = await FirebaseFirestore.instance
        .collection('employees')
        .where('roles', arrayContains: 'Driver')
        .orderBy('firstName')
        .limit(500)
        .get();

    if (driversSnap.docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No drivers found')));
      return;
    }

    final all = driversSnap.docs
        .map((d) => _DriverPick(
              id: d.id,
              name: (d.data()['name'] ??
                      ('${d.data()['firstName'] ?? ''} ${d.data()['lastName'] ?? ''}'))
                  .toString()
                  .trim(),
            ))
        .toList();

    String filter = '';
    String? selectedId;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final vis = all
              .where((x) =>
                  x.name.toLowerCase().contains(filter.toLowerCase()) ||
                  x.id.toLowerCase().contains(filter.toLowerCase()))
              .toList();
          return AlertDialog(
            title: const Text('Reassign Driver'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search driver…',
                    ),
                    onChanged: (v) => setLocal(() => filter = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedId,
                    items: vis
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text('${p.name}  •  ${p.id}'),
                            ))
                        .toList(),
                    onChanged: (v) => setLocal(() => selectedId = v),
                    decoration: const InputDecoration(
                      labelText: 'Select driver',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: selectedId == null
                    ? null
                    : () async {
                        try {
                          await FirebaseFirestore.instance
                              .collection('loads')
                              .doc(loadId)
                              .update({
                            'driverId': selectedId,
                            'status': 'Assigned',
                            'assignedAt': FieldValue.serverTimestamp(),
                          });
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Driver updated')));
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Reassign failed: $e')));
                          }
                        }
                      },
                child: const Text('Update'),
              )
            ],
          );
        },
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('loads')
        .where('driverId', isEqualTo: widget.driverId)
        .orderBy('pickupDate') // add index if needed
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Timeline'),
        actions: const [MainMenuButton()],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snap.data!.docs.map((d) => _toTimelineLoad(d)).toList();
          if (items.isEmpty) {
            return const Center(
                child: Text('No assigned loads for this driver.'));
          }

          // Build scale: min→max dates
          final minStart =
              items.map((e) => e.start).reduce((a, b) => a.isBefore(b) ? a : b);
          final maxEnd =
              items.map((e) => e.end).reduce((a, b) => a.isAfter(b) ? a : b);

          // Add padding: 12 hours on each side
          final paddedStart = minStart.subtract(const Duration(hours: 12));
          final paddedEnd = maxEnd.add(const Duration(hours: 12));

          // Compute lanes to avoid overlap
          final lanes = _packIntoLanes(items);

          // Canvas width in px
          final totalHours = paddedEnd.difference(paddedStart).inMinutes / 60.0;
          final canvasWidth = math.max(
              totalHours * _pxPerHour, MediaQuery.of(context).size.width);

          // Canvas height: axis + lanes
          final canvasHeight = _axisHeight + lanes.length * _laneHeight + 24;

          // Today marker (if within range)
          final now = DateTime.now();
          final showNow = !now.isBefore(paddedStart) && !now.isAfter(paddedEnd);
          final nowLeft = showNow ? _leftFor(paddedStart, now, _pxPerHour) : 0;

          return GestureDetector(
            onScaleUpdate: (details) {
              setState(() {
                _pxPerHour =
                    math.max(24, math.min(120, _pxPerHour * details.scale));
              });
            },
            child: Column(
              children: [
                // Zoom control (optional slider for fine tune)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.zoom_out),
                      Expanded(
                        child: Slider(
                          min: 24,
                          max: 120,
                          divisions: 96,
                          value: _pxPerHour,
                          label: '${_pxPerHour.toStringAsFixed(0)} px/hr',
                          onChanged: (v) => setState(() => _pxPerHour = v),
                        ),
                      ),
                      const Icon(Icons.zoom_in),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                // Timeline canvas
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: canvasWidth,
                        child: Stack(
                          children: [
                            // Axis (top)
                            Positioned.fill(
                              top: 0,
                              bottom: canvasHeight - _axisHeight,
                              child: _TimeAxis(
                                start: paddedStart,
                                end: paddedEnd,
                                pxPerHour: _pxPerHour,
                              ),
                            ),
                            // Today marker
                            if (showNow)
                              Positioned(
                                top: 0,
                                left: nowLeft.toDouble(),
                                bottom: 0,
                                child: Container(
                                  width: 2,
                                  color: Colors.red.withOpacity(0.45),
                                ),
                              ),
                            // Lanes with cards
                            for (int laneIdx = 0;
                                laneIdx < lanes.length;
                                laneIdx++)
                              for (final load in lanes[laneIdx])
                                Positioned(
                                  top: _axisHeight + laneIdx * _laneHeight + 8,
                                  left: _leftFor(
                                      paddedStart, load.start, _pxPerHour),
                                  width: math.max(
                                    64,
                                    _widthFor(load.start, load.end, _pxPerHour),
                                  ),
                                  height: _laneHeight - 16,
                                  child: _LoadCard(
                                    load: load,
                                    canEdit: can(_role, AppPerm.editDispatch),
                                    onEdit: () async {
                                      final changed = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => QuickLoadScreen(
                                                loadId: load.id)),
                                      );
                                      if (changed == true && mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text('Load updated')),
                                        );
                                      }
                                    },
                                    onChangeStatus: () => _showStatusDialog(
                                        load.id,
                                        load.status,
                                        can(_role, AppPerm.editDispatch)),
                                    onReassign: () => _reassignDriver(load.id),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- helpers ----------

  _TimelineLoad _toTimelineLoad(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();

    final ref = (m['loadNumber'] ?? m['shippingNumber'] ?? m['poNumber'] ?? '')
        .toString();
    final status = (m['status'] ?? 'Planned').toString();

    DateTime? start = _parseDate(m['pickupDate']) ?? _parseDate(m['createdAt']);
    DateTime? end =
        _parseDate(m['deliveryDate']) ?? _parseDate(m['expectedDeliveryAt']);
    // safety defaults
    start ??= DateTime.now();
    end ??= start.add(const Duration(hours: 6));
    if (!end.isAfter(start)) {
      end = start.add(const Duration(hours: 2));
    }

    final pickup = (m['pickupAddress'] ?? '').toString();
    final delivery = (m['deliveryAddress'] ?? '').toString();

    return _TimelineLoad(
      id: d.id,
      ref: ref.isEmpty ? d.id : ref,
      status: status,
      start: start,
      end: end,
      pickup: pickup,
      delivery: delivery,
    );
  }

  List<List<_TimelineLoad>> _packIntoLanes(List<_TimelineLoad> items) {
    // Sort by start time
    final sorted = [...items]..sort((a, b) => a.start.compareTo(b.start));
    final lanes = <List<_TimelineLoad>>[];
    final laneEnds = <DateTime>[];

    for (final item in sorted) {
      bool placed = false;
      for (int i = 0; i < laneEnds.length; i++) {
        if (item.start.isAfter(laneEnds[i])) {
          lanes[i].add(item);
          laneEnds[i] = item.end;
          placed = true;
          break;
        }
      }
      if (!placed) {
        lanes.add([item]);
        laneEnds.add(item.end);
      }
    }
    return lanes;
  }

  double _leftFor(DateTime start, DateTime when, double pxPerHour) {
    final hours = when.difference(start).inMinutes / 60.0;
    return hours * pxPerHour;
  }

  double _widthFor(DateTime s, DateTime e, double pxPerHour) {
    final hrs = e.difference(s).inMinutes / 60.0;
    return hrs * pxPerHour;
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  Future<void> _showStatusDialog(
      String loadId, String current, bool canEdit) async {
    String selected = current;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Update Status'),
        content: DropdownButtonFormField<String>(
          initialValue: selected,
          items: const [
            DropdownMenuItem(value: 'Planned', child: Text('Planned')),
            DropdownMenuItem(value: 'Assigned', child: Text('Assigned')),
            DropdownMenuItem(value: 'En Route', child: Text('En Route')),
            DropdownMenuItem(value: 'Delivered', child: Text('Delivered')),
          ],
          onChanged: canEdit ? (val) => selected = val ?? current : null,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          if (canEdit)
            FilledButton(
              onPressed: () async {
                await _updateStatus(loadId, selected);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Update'),
            ),
        ],
      ),
    );
  }
}

// ---------- visual components ----------

class _TimeAxis extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final double pxPerHour;
  const _TimeAxis(
      {required this.start, required this.end, required this.pxPerHour});

  @override
  Widget build(BuildContext context) {
    final hours = end.difference(start).inHours;
    final days = (hours / 24).ceil();
    final theme = Theme.of(context);

    // Generate day ticks
    final ticks = List.generate(
        days + 1,
        (i) => DateTime(start.year, start.month, start.day)
            .add(Duration(days: i)));

    return CustomPaint(
      painter: _AxisPainter(
          start: start,
          ticks: ticks,
          pxPerHour: pxPerHour,
          textStyle: theme.textTheme.bodySmall),
      size: Size(double.infinity, _DriverTimelineScreenState._axisHeight),
    );
  }
}

class _AxisPainter extends CustomPainter {
  final DateTime start;
  final List<DateTime> ticks;
  final double pxPerHour;
  final TextStyle? textStyle;
  _AxisPainter(
      {required this.start,
      required this.ticks,
      required this.pxPerHour,
      required this.textStyle});

  @override
  void paint(Canvas canvas, Size size) {
    final axisY = size.height - 24; // baseline
    final p = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..strokeWidth = 1.0;

    // Axis line
    canvas.drawLine(Offset(0, axisY), Offset(size.width, axisY), p);

    // Day ticks & labels
    for (final day in ticks) {
      final left = _leftFor(start, day, pxPerHour);
      // Major tick
      canvas.drawLine(Offset(left, axisY - 18), Offset(left, axisY + 2), p);

      final label =
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left + 4, axisY - 18 - tp.height));
    }
  }

  double _leftFor(DateTime start, DateTime when, double pxPerHour) {
    final hours = when.difference(start).inMinutes / 60.0;
    return hours * pxPerHour;
  }

  @override
  bool shouldRepaint(covariant _AxisPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.pxPerHour != pxPerHour ||
        oldDelegate.ticks != ticks ||
        oldDelegate.textStyle != textStyle;
  }
}

class _LoadCard extends StatelessWidget {
  final _TimelineLoad load;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onChangeStatus;
  final VoidCallback onReassign;

  const _LoadCard({
    required this.load,
    required this.canEdit,
    required this.onEdit,
    required this.onChangeStatus,
    required this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(load.status);
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.withOpacity(0.25))),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + status chip
              Row(
                children: [
                  Expanded(
                    child: Text(
                      load.ref,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.withOpacity(0.6)),
                    ),
                    child: Text(load.status,
                        style:
                            TextStyle(color: c, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Pickup: ${_fmt(load.start)} • Delivery: ${_fmt(load.end)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (load.pickup.isNotEmpty || load.delivery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${load.pickup}${load.delivery.isNotEmpty ? ' → ${load.delivery}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              if (canEdit) ...[
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit')),
                    const SizedBox(width: 4),
                    TextButton.icon(
                        onPressed: onChangeStatus,
                        icon: const Icon(Icons.flag, size: 16),
                        label: const Text('Status')),
                    const SizedBox(width: 4),
                    TextButton.icon(
                        onPressed: onReassign,
                        icon: const Icon(Icons.person, size: 16),
                        label: const Text('Driver')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'planned':
        return Colors.blueGrey;
      case 'assigned':
        return Colors.indigo;
      case 'en route':
        return Colors.orange;
      case 'delivered':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------- models ----------

class _TimelineLoad {
  final String id;
  final String ref;
  final String status;
  final DateTime start;
  final DateTime end;
  final String pickup;
  final String delivery;
  _TimelineLoad({
    required this.id,
    required this.ref,
    required this.status,
    required this.start,
    required this.end,
    required this.pickup,
    required this.delivery,
  });
}

class _DriverPick {
  final String id;
  final String name;
  _DriverPick({required this.id, required this.name});
}

// ---------- small shared ----------

String _fmtTs(dynamic v) {
  if (v == null) return '';
  DateTime? dt;
  if (v is Timestamp) dt = v.toDate();
  if (v is DateTime) dt = v;
  dt ??= DateTime.tryParse(v.toString());
  if (dt == null) return '';
  return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
