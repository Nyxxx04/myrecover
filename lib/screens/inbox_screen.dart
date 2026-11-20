import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../services/inbox_service.dart';
import '../services/item_service.dart';
import '../theme.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/animations.dart';
import '../widgets/item_card.dart';
import '../widgets/item_list.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.user});
  final AppUser user;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  static final _timeFmt = DateFormat('d MMM, h:mm a');

  late final _entries = InboxService.instance.entries(widget.user.uid);

  /// Unread on arrival: stays highlighted until the page is closed, even
  /// though it is marked as read straight away.
  final _fresh = <String>{};

  void _markSeen(List<InboxEntry> entries) {
    final unseen = [
      for (final e in entries)
        if (!e.read && !_fresh.contains(e.id)) e.id,
    ];
    if (unseen.isEmpty) return;
    _fresh.addAll(unseen);
    InboxService.instance.markRead(widget.user.uid, unseen).ignore();
  }

  /// `match:mineId:otherId` entries point at the other person's report.
  static String? _matchedItemId(InboxEntry e) => e.id.startsWith('match:') ? e.id.split(':').last : null;

  /// Shows the matched report with its "This is mine" / "I found this" button.
  Future<void> _openMatch(String itemId) async {
    final item = await ItemService.instance.itemById(itemId);
    if (!mounted) return;
    if (item == null || item.status != 'pending') {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('This report is no longer listed. It may already be returned.')));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ItemCard(item: item, actions: [contactAction(sheetContext, item, widget.user)]),
          ),
        ),
      ),
    );
  }

  Future<void> _clearAll(List<InboxEntry> entries) async {
    if (!await confirmDialog(context, 'Clear all notifications?', confirmLabel: 'Clear all')) return;
    await InboxService.instance.clear(widget.user.uid, entries.map((e) => e.id));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<InboxEntry>>(
    stream: _entries,
    builder: (context, snap) {
      final entries = snap.data ?? const <InboxEntry>[];
      _markSeen(entries);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            if (entries.isNotEmpty) TextButton(onPressed: () => _clearAll(entries), child: const Text('Clear all')),
          ],
        ),
        body: _body(snap, entries),
      );
    },
  );

  Widget _body(AsyncSnapshot<List<InboxEntry>> snap, List<InboxEntry> entries) {
    if (snap.hasError) return const _Message(Icons.cloud_off, 'Could not load your notifications.');
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    if (entries.isEmpty) {
      return const _Message(
        Icons.notifications_none,
        'No notifications yet.\nMatches and claim updates will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return AnimatedEntry(
          key: ValueKey(entry.id),
          index: i,
          child: Dismissible(
            key: ValueKey('dismiss:${entry.id}'),
            onDismissed: (_) => InboxService.instance.remove(widget.user.uid, entry.id).ignore(),
            background: const SizedBox.shrink(),
            child: Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: _fresh.contains(entry.id) ? BorderSide(color: context.brandText, width: 1.5) : BorderSide.none,
              ),
              child: InkWell(
                onTap: _matchedItemId(entry) == null ? null : () => _openMatch(_matchedItemId(entry)!),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(entry.body, style: TextStyle(fontSize: 13, color: context.mutedText)),
                      if (entry.createdAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _timeFmt.format(entry.createdAt!),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                      if (_matchedItemId(entry) != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Tap to view the item →',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.aiText),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}
