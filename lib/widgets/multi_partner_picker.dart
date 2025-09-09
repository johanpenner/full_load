// lib/widgets/multi_partner_picker.dart
import 'package:flutter/material.dart';
import 'firestore_search_picker.dart';

/// A vertical list of pickers for Shippers or Receivers.
/// - Supports add/remove
/// - Each row uses FirestoreSearchPicker
class MultiPartnerPicker extends StatefulWidget {
  const MultiPartnerPicker({
    super.key,
    required this.label, // "Shippers" or "Receivers"
    required this.singleItemLabel, // "Shipper" or "Receiver"
    required this.collectionPath,
    this.displayField = 'name',
    this.initialSelections = const [],
    this.requiredAtLeastOne = true,
    this.onChanged,
  });

  final String label;
  final String singleItemLabel;
  final String collectionPath;
  final String displayField;
  final List<DocRefSelection> initialSelections;
  final bool requiredAtLeastOne;
  final ValueChanged<List<DocRefSelection>>? onChanged;

  @override
  State<MultiPartnerPicker> createState() => _MultiPartnerPickerState();
}

class _MultiPartnerPickerState extends State<MultiPartnerPicker> {
  final GlobalKey<FormState> _localKey = GlobalKey<FormState>();
  final List<DocRefSelection?> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialSelections.isEmpty) {
      _items.add(null);
    } else {
      _items.addAll(widget.initialSelections);
    }
  }

  void _notify() {
    widget.onChanged?.call(_items.whereType<DocRefSelection>().toList());
  }

  void _add() {
    setState(() => _items.add(null));
  }

  void _remove(int index) {
    setState(() => _items.removeAt(index));
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _localKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...List.generate(_items.length, (i) {
            final initial = _items[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: FirestoreSearchPicker(
                      label: '${widget.singleItemLabel} ${i + 1}',
                      collectionPath: widget.collectionPath,
                      displayField: widget.displayField,
                      initialSelection: initial,
                      onSelected: (sel) {
                        _items[i] = sel;
                        _notify();
                      },
                      hintText: 'Type to search or browse',
                      required: widget.requiredAtLeastOne,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: _items.length > 1 ? () => _remove(i) : null,
                    icon: const Icon(Icons.delete_outline),
                  )
                ],
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: Text('Add ${widget.singleItemLabel}'),
            ),
          ),
        ],
      ),
    );
  }
}
