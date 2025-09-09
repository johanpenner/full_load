// lib/widgets/firestore_search_picker.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Simple value object for a chosen Firestore document.
class DocRefSelection {
  final String id;
  final String name;
  DocRefSelection({required this.id, required this.name});
  @override
  String toString() => name;
}

/// A text field with autocomplete + a button to open a scrollable picker.
/// - Type to search (Firestore prefix search on [displayField]).
/// - Or tap the trailing icon to open a full scrollable list.
/// - Emits [DocRefSelection] on selection.
/// - No external packages required.
class FirestoreSearchPicker extends StatefulWidget {
  const FirestoreSearchPicker({
    super.key,
    required this.label,
    required this.collectionPath,
    this.displayField = 'name',
    this.initialSelection,
    this.onSelected,
    this.hintText,
    this.required = true,
    this.searchLimit = 25,
    this.preloadLimit = 100,
    this.enabled = true,
  });

  final String label;
  final String collectionPath; // e.g. 'clients', 'shippers', 'receivers'
  final String displayField; // defaults to 'name'
  final DocRefSelection? initialSelection;
  final ValueChanged<DocRefSelection?>? onSelected;
  final String? hintText;
  final bool required;
  final int searchLimit;
  final int preloadLimit;
  final bool enabled;

  @override
  State<FirestoreSearchPicker> createState() => _FirestoreSearchPickerState();
}

class _FirestoreSearchPickerState extends State<FirestoreSearchPicker> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<DocRefSelection> _preloaded = [];
  List<DocRefSelection> _lastQueryResults = [];
  Timer? _debounce;
  DocRefSelection? _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialSelection;
    if (_current != null) _controller.text = _current!.name;
    _preload();
  }

  @override
  void didUpdateWidget(covariant FirestoreSearchPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelection?.id != oldWidget.initialSelection?.id) {
      _current = widget.initialSelection;
      _controller.text = _current?.name ?? '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _preload() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection(widget.collectionPath)
          .orderBy(widget.displayField)
          .limit(widget.preloadLimit)
          .get();

      setState(() {
        _preloaded = qs.docs
            .map((d) {
              final name = (d.data()[widget.displayField] ?? '').toString();
              return DocRefSelection(id: d.id, name: name);
            })
            .where((o) => o.name.isNotEmpty)
            .toList();
      });
    } catch (_) {
      // If there is no index, fallback to unordered preload (best effort).
      try {
        final qs = await FirebaseFirestore.instance
            .collection(widget.collectionPath)
            .limit(widget.preloadLimit)
            .get();
        setState(() {
          _preloaded = qs.docs
              .map((d) {
                final name = (d.data()[widget.displayField] ?? '').toString();
                return DocRefSelection(id: d.id, name: name);
              })
              .where((o) => o.name.isNotEmpty)
              .toList()
            ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        });
      } catch (_) {}
    }
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      await _runPrefixQuery(value.trim());
    });
  }

  Future<void> _runPrefixQuery(String pattern) async {
    if (pattern.isEmpty) {
      setState(() => _lastQueryResults = []);
      return;
    }
    try {
      final col = FirebaseFirestore.instance.collection(widget.collectionPath);
      final qs = await col
          .orderBy(widget.displayField)
          .startAt([pattern])
          .endAt(["$pattern\uf8ff"])
          .limit(widget.searchLimit)
          .get();

      setState(() {
        _lastQueryResults = qs.docs
            .map((d) {
              final name = (d.data()[widget.displayField] ?? '').toString();
              return DocRefSelection(id: d.id, name: name);
            })
            .where((o) => o.name.isNotEmpty)
            .toList();
      });
    } catch (_) {
      // If index is missing, do local filter from preload.
      final lower = pattern.toLowerCase();
      setState(() {
        _lastQueryResults = _preloaded
            .where((o) => o.name.toLowerCase().contains(lower))
            .take(widget.searchLimit)
            .toList();
      });
    }
  }

  Future<void> _openScrollablePicker() async {
    // Ensure we have something to show.
    if (_preloaded.isEmpty) await _preload();

    final selected = await showModalBottomSheet<DocRefSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final TextEditingController searchCtl = TextEditingController();
        ValueNotifier<List<DocRefSelection>> filtered =
            ValueNotifier<List<DocRefSelection>>(List.of(_preloaded));

        void applyFilter(String q) {
          final lower = q.toLowerCase();
          final list = q.isEmpty
              ? _preloaded
              : _preloaded
                  .where((o) => o.name.toLowerCase().contains(lower))
                  .toList();
          list.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          filtered.value = list;
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: searchCtl,
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: applyFilter,
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder<List<DocRefSelection>>(
                    valueListenable: filtered,
                    builder: (ctx, items, _) {
                      if (items.isEmpty) {
                        return const Center(child: Text('No results'));
                      }
                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final item = items[i];
                          return ListTile(
                            title: Text(item.name),
                            onTap: () => Navigator.of(ctx).pop(item),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      _select(selected);
    }
  }

  void _select(DocRefSelection? sel) {
    setState(() {
      _current = sel;
      _controller.text = sel?.name ?? '';
    });
    widget.onSelected?.call(sel);
  }

  String? _validator(String? value) {
    if (!widget.required) return null;
    if (value == null || value.trim().isEmpty) {
      return '${widget.label} is required';
    }
    if (_current == null) return 'Please pick a ${widget.label} from the list';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<DocRefSelection>(
      focusNode: _focusNode,
      textEditingController: _controller,
      displayStringForOption: (o) => o.name,
      optionsBuilder: (TextEditingValue tev) {
        final input = tev.text.trim();
        final source = (input.isEmpty ? _preloaded : _lastQueryResults);
        final lower = input.toLowerCase();
        // Local filter to keep suggestions tight; network updates run in background.
        final filtered = source
            .where((o) => o.name.toLowerCase().contains(lower))
            .take(widget.searchLimit)
            .toList();
        // Kick off async fetch when user types.
        if (input.isNotEmpty) _onTextChanged(input);
        return filtered;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          enabled: widget.enabled,
          controller: controller,
          focusNode: focusNode,
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText ??
                'Start typing to search or pick from the list',
            suffixIcon: IconButton(
              tooltip: 'Browse all',
              icon: const Icon(Icons.list_alt),
              onPressed: widget.enabled ? _openScrollablePicker : null,
            ),
            border: const OutlineInputBorder(),
          ),
          validator: _validator,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, minWidth: 360),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final opt = list[i];
                  return ListTile(
                    title: Text(opt.name),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: _select,
      initialValue: _current,
    );
  }
}
