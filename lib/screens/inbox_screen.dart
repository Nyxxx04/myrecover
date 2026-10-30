import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/inbox_service.dart';
import '../theme.dart';
import '../widgets/animations.dart';
import '../widgets/item_list.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.uid});
  final String uid;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  static final _timeFmt = DateFormat('d MMM, h:mm a');

  late final _entries = InboxService.instance.entries(widget.uid);

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
    InboxService.instance.markRead(widget.uid, unseen).ignore();
  }

  Future<void> _clearAll(List<InboxEntry> entries) async {
    if (!await confirmDialog(context, 'Clear all notifications?', confirmLabel: 'Clear all')) return;
    await InboxService.instance.clear(widget.uid, entries.map((e) => e.id));
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
            if (entries.isNotEmpty)
              TextButton(
                onPressed: () => _clearAll(entries),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Clear all'),
              ),
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
      return const _Message(Icons.notifications_none, 'No notifications yet.\nMatches and claim updates will appear here.');
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
            onDismissed: (_) => InboxService.instance.remove(widget.uid, entry.id).ignore(),
            background: const SizedBox.shrink(),
            child: Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: _fresh.contains(entry.id)
                    ? BorderSide(color: context.brandText, width: 1.5)
                    : BorderSide.none,
              ),
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
                  ],
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
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    ),
  );
}
