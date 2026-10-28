import 'dart:async';

import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/ai_service.dart';
import '../services/recommender.dart';
import '../services/search_history.dart';
import '../theme.dart';
import 'animations.dart';

/// Streams items with a search box and the All / Lost / Found filter chips.
///
/// When [history] is given, searches are remembered and, while the search
/// box is empty, items similar to recent searches are shown first.
///
/// With [aiSearch], a descriptive search ("lost my black wallet at the
/// library yesterday") is turned into filters by AI when submitted.
class FilteredItemList extends StatefulWidget {
  const FilteredItemList({
    super.key,
    required this.stream,
    required this.itemBuilder,
    this.emptyText = 'No items found',
    this.showFilter = true,
    this.history,
    this.aiSearch = false,
    this.header,
  });

  final Stream<List<Item>> stream;
  final Widget Function(BuildContext, Item) itemBuilder;
  final String emptyText;
  final bool showFilter;
  final SearchHistory? history;
  final bool aiSearch;

  /// Shown above the search box, e.g. an admin tool button.
  final Widget? header;

  @override
  State<FilteredItemList> createState() => _FilteredItemListState();
}

class _FilteredItemListState extends State<FilteredItemList> {
  final _search = TextEditingController();
  Timer? _saveDebounce;
  String _filter = 'all';
  String _query = '';
  AiSearchFilters? _ai;
  String? _aiQuery;
  bool _aiBusy = false;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    widget.history?.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value.trim();
      _aiError = null;
      if (_ai != null && _query != _aiQuery) _ai = null; // edited: back to plain search
    });
    // Remember the search once the user pauses typing.
    _saveDebounce?.cancel();
    if (widget.history != null && _query.length >= 2) {
      _saveDebounce = Timer(const Duration(seconds: 2), () => widget.history!.add(_query));
    }
  }

  bool get _looksDescriptive => _query.split(RegExp(r'\s+')).length >= 3;

  Future<void> _runAiSearch() async {
    final query = _query;
    FocusScope.of(context).unfocus();
    setState(() {
      _aiBusy = true;
      _aiError = null;
    });
    try {
      final filters = await AiService.instance.parseSearch(query);
      if (!mounted || _query != query) return;
      setState(() {
        _ai = filters;
        _aiQuery = query;
        if (filters.type != 'any') _filter = filters.type;
      });
    } on AiException catch (e) {
      if (mounted) setState(() => _aiError = e.message);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _clearSearch() {
    _search.clear();
    _onQueryChanged('');
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.header != null) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: widget.header),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _search,
            onChanged: _onQueryChanged,
            onSubmitted: (v) {
              if (v.trim().length >= 2) widget.history?.add(v);
              if (widget.aiSearch && _looksDescriptive) _runAiSearch();
            },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.aiSearch
                  ? 'Search or describe, e.g. lost black wallet at library'
                  : 'Search items, e.g. black bag',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.aiSearch && _ai == null)
                          IconButton(
                            tooltip: 'Ask AI',
                            icon: const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED)),
                            onPressed: _aiBusy ? null : _runAiSearch,
                          ),
                        IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: _clearSearch),
                      ],
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ),
        AnimatedSize(duration: motionMedium, curve: Curves.easeOutCubic, child: _aiStatus()),
        if (widget.showFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                for (final (value, label) in [('all', 'All Items'), ('lost', '🔍 Lost'), ('found', '✅ Found')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == value,
                      selectedColor: brandGreen,
                      labelStyle: TextStyle(color: _filter == value ? Colors.white : null),
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = value),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: StreamBuilder<List<Item>>(
            stream: widget.stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load items.\n${snap.error}', textAlign: TextAlign.center),
                  ),
                );
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return _buildList(snap.data!);
            },
          ),
        ),
      ],
    );
  }

  Widget _aiStatus() {
    const purple = Color(0xFF7C3AED);
    if (_aiBusy) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Row(
          children: [
            SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: purple)),
            SizedBox(width: 10),
            Text('✨ AI is understanding your search…', style: TextStyle(color: purple)),
          ],
        ),
      );
    }
    if (_aiError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text(_aiError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
      );
    }
    final ai = _ai;
    if (ai == null) return const SizedBox(width: double.infinity);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(color: purple.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: purple),
            const SizedBox(width: 8),
            Expanded(
              child: Text('AI: ${ai.summary}', style: const TextStyle(color: purple, fontSize: 13)),
            ),
            IconButton(
              tooltip: 'Use plain search',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18, color: purple),
              onPressed: () => setState(() => _ai = null),
            ),
          ],
        ),
      ),
    );
  }

  /// Applies AI-understood filters, loosening them if nothing matches.
  List<Item> _aiResults(List<Item> all, ItemRecommender recommender, AiSearchFilters ai) {
    final byType = _filter == 'all' ? all : all.where((i) => i.type == _filter).toList();
    final since = ai.daysAgo >= 0 ? DateTime.now().subtract(Duration(days: ai.daysAgo + 1)) : null;
    final strict = byType
        .where((i) => ai.category == 'any' || i.category == ai.category)
        .where((i) => since == null || !i.date.isBefore(DateTime(since.year, since.month, since.day)))
        .toList();
    final query = [ai.keywords, ai.color, ai.location].where((s) => s.isNotEmpty).join(' ');
    final results = recommender.search(strict, query.isEmpty ? _query : query);
    return results.isNotEmpty ? results : recommender.search(byType, ai.keywords.isEmpty ? _query : ai.keywords);
  }

  Widget _buildList(List<Item> all) {
    final items = _filter == 'all' ? all : all.where((i) => i.type == _filter).toList();
    final recommender = ItemRecommender(all);
    final entries = <Object>[]; // a String is a section header, an Item is a card

    if (_ai != null && _query.isNotEmpty) {
      entries.addAll(_aiResults(all, recommender, _ai!));
      if (entries.isEmpty) return _message('Nothing matches what you described yet.');
    } else if (_query.isNotEmpty) {
      entries.addAll(recommender.search(items, _query));
      if (entries.isEmpty) return _message('No items match "$_query"');
    } else {
      final history = widget.history?.queries ?? const <String>[];
      final recommended = recommender.recommend(items, history);
      if (recommended.isNotEmpty) {
        entries
          ..add('✨ Recommended for you · based on "${history.first}"')
          ..addAll(recommended)
          ..add('Latest items');
      }
      entries.addAll(items.where((i) => !recommended.contains(i)));
      if (items.isEmpty) return _message(widget.emptyText);
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        if (entry is String) {
          return AnimatedEntry(
            key: ValueKey('header:$entry'),
            index: i,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
              child: Text(
                entry,
                style: const TextStyle(fontWeight: FontWeight.bold, color: brandGreen),
              ),
            ),
          );
        }
        final item = entry as Item;
        return AnimatedEntry(key: ValueKey(item.id), index: i, child: widget.itemBuilder(context, item));
      },
    );
  }

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.grey),
      ),
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, String message, {String confirmLabel = 'Delete'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
