import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item.dart';
import '../theme.dart';

final _dateFmt = DateFormat('d MMM y');

class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.item,
    this.showReporter = false,
    this.showStatus = false,
    this.actions = const [],
    this.footer,
  });

  final Item item;
  final bool showReporter;
  final bool showStatus;
  final List<Widget> actions;

  /// Extra content above the actions (e.g. AI claim info).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final typeColor = item.isLost ? lostColor : foundColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (item.imageBytes != null)
            Image.memory(item.imageBytes!, height: 200, fit: BoxFit.cover, gaplessPlayback: true),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(item.emoji, style: const TextStyle(fontSize: 32)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          Text(
                            item.isLost ? '🔍 LOST' : '✅ FOUND',
                            style: text.labelMedium?.copyWith(color: typeColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    if (showStatus) _StatusChip(status: item.status),
                  ],
                ),
                const SizedBox(height: 10),
                Text(item.description, style: text.bodyMedium),
                const SizedBox(height: 10),
                _detail('📍 Location', item.location),
                _detail('📅 Date', _dateFmt.format(item.date)),
                _detail('🏷️ Category', item.category),
                if (showReporter) ...[_detail('📧 Contact', item.contact), _detail('👤 Reporter', item.reporter)],
                if (footer != null) ...[const SizedBox(height: 12), footer!],
                if (actions.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(alignment: WrapAlignment.end, children: actions),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Builder(
      builder: (context) => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
        style: TextStyle(fontSize: 13, color: context.mutedText),
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final returned = status == 'returned';
    final (background, foreground) = switch ((returned, context.isDark)) {
      (true, false) => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      (true, true) => (const Color(0xFF14532D), const Color(0xFFBBF7D0)),
      (false, false) => (const Color(0xFFDBEAFE), const Color(0xFF1E40AF)),
      (false, true) => (const Color(0xFF1E3A8A), const Color(0xFFBFDBFE)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground),
      ),
    );
  }
}
