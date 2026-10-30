import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/item.dart';
import '../services/claim_service.dart';
import '../services/match_watcher.dart';
import '../theme.dart';
import '../widgets/animations.dart';
import 'admin_edit_screen.dart';
import 'handover_scan_screen.dart';

/// Admin review of ownership claims. Only the admin sees both the finder and
/// the claimant; they never see each other.
class AdminClaims extends StatefulWidget {
  const AdminClaims({super.key, required this.claims, required this.items});
  final Stream<List<Claim>> claims;
  final Stream<List<Item>> items;

  @override
  State<AdminClaims> createState() => _AdminClaimsState();
}

class _AdminClaimsState extends State<AdminClaims> {
  bool _checking = false;
  final _busy = <String>{};

  Future<void> _runAiCheck() async {
    setState(() => _checking = true);
    await MatchWatcher.run();
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _decide(Claim claim, {required bool approve}) async {
    if (!approve && !await _confirm('Dismiss the claim by ${claim.claimantName}?', 'Dismiss')) {
      return;
    }
    setState(() => _busy.add(claim.id));
    try {
      approve ? await ClaimService.instance.approve(claim) : await ClaimService.instance.dismiss(claim);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? 'Approved. ${claim.claimantName} and the finder will be notified.'
                  : 'Claim dismissed. ${claim.claimantName} will be notified.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(claim.id));
    }
  }

  Future<bool> _confirm(String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Item>>(
      stream: widget.items,
      builder: (context, itemsSnap) => StreamBuilder<List<Claim>>(
        stream: widget.claims,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load claims.\n${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (!itemsSnap.hasData) return const Center(child: CircularProgressIndicator());
          final itemsById = {for (final i in itemsSnap.data!) i.id: i};
          // Claims whose report was already closed (returned/deleted) need no action.
          final open = snap.data!.where((c) => itemsById.containsKey(c.itemId)).toList();
          final closed = snap.data!.where((c) => !itemsById.containsKey(c.itemId)).toList();
          final claims = snap.data!;
          final sections = [
            ('Needs your review', open.where((c) => c.awaitsAdmin).toList()),
            ('Waiting for AI check', open.where((c) => c.isPending).toList()),
            ('Approved: hand over at the office', open.where((c) => c.isApproved).toList()),
            ('Dismissed', open.where((c) => c.isDismissed).toList()),
            ('Report already closed', closed),
          ].where((s) => s.$2.isNotEmpty);

          if (claims.isEmpty) {
            return const Center(
              child: Text('No claims yet', style: TextStyle(color: Colors.grey)),
            );
          }
          var index = 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HandoverScanScreen())),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan handover QR'),
              ),
              const SizedBox(height: 8),
              for (final (title, list) in sections) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$title (${list.length})',
                          style: TextStyle(fontWeight: FontWeight.bold, color: context.brandText),
                        ),
                      ),
                      if (title.startsWith('Waiting'))
                        TextButton.icon(
                          onPressed: _checking ? null : _runAiCheck,
                          style: TextButton.styleFrom(foregroundColor: context.aiText),
                          icon: _checking
                              ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('Check now'),
                        ),
                    ],
                  ),
                ),
                for (final c in list)
                  AnimatedEntry(
                    key: ValueKey(c.id),
                    index: index++,
                    child: _ClaimCard(
                      claim: c,
                      item: itemsById[c.itemId],
                      busy: _busy.contains(c.id),
                      onApprove: () => _decide(c, approve: true),
                      onDismiss: () => _decide(c, approve: false),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ClaimCard extends StatelessWidget {
  const _ClaimCard({
    required this.claim,
    required this.item,
    required this.busy,
    required this.onApprove,
    required this.onDismiss,
  });

  final Claim claim;
  final Item? item;
  final bool busy;
  final VoidCallback onApprove, onDismiss;

  @override
  Widget build(BuildContext context) {
    final aiChecked = !claim.isPending;
    final aiPassed = claim.isVerified || (claim.isApproved && claim.confidence >= 60);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(item?.emoji ?? '📦', style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    claim.itemTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (aiChecked) _AiChip(passed: aiPassed, confidence: claim.confidence),
              ],
            ),
            if (claim.feedback.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('AI: ${claim.feedback}', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
            ],
            const Divider(height: 22),
            _Person(label: 'Claimant', name: claim.claimantName, contact: claim.claimantContact),
            const SizedBox(height: 6),
            item == null
                ? const Text('Finder: report already closed', style: TextStyle(color: Colors.grey, fontSize: 13))
                : _Person(label: 'Finder', name: item!.reporter, contact: item!.contact),
            const Divider(height: 22),
            _SecretLine(itemId: claim.itemId),
            const SizedBox(height: 8),
            for (final a in claim.answers) ...[
              Text('Q: ${a['question']}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              Text('A: ${a['answer']}', style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
            ],
            if (claim.awaitsAdmin && item != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: busy ? null : onDismiss,
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: 8),
                  PressScale(
                    child: FilledButton.icon(
                      onPressed: busy ? null : onApprove,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                    ),
                  ),
                ],
              )
            else if (claim.isApproved && item != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AdminEditScreen(item: item!))),
                  icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                  label: const Text('Handed over? Mark returned'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AiChip extends StatelessWidget {
  const _AiChip({required this.passed, required this.confidence});
  final bool passed;
  final int confidence;

  @override
  Widget build(BuildContext context) {
    final color = passed ? foundColor : lostColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        '${passed ? '✓ AI match' : '✗ AI unsure'} $confidence%',
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.label, required this.name, required this.contact});
  final String label, name, contact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(label == 'Finder' ? Icons.volunteer_activism_outlined : Icons.person_outline, size: 20, color: Colors.grey),
      const SizedBox(width: 8),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(color: Colors.grey),
              ),
              TextSpan(
                text: name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: '  ·  $contact'),
            ],
          ),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      IconButton(
        tooltip: 'Copy contact',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: contact));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✓ Copied: $contact')));
        },
      ),
    ],
  );
}

/// The finder's hidden detail, which only the admin can see besides the finder.
class _SecretLine extends StatelessWidget {
  const _SecretLine({required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: ClaimService.instance.secretFor(itemId).catchError((_) => null),
    builder: (context, snap) => Text.rich(
      TextSpan(
        children: [
          const TextSpan(
            text: '🛡 Secret detail: ',
            style: TextStyle(color: Colors.grey),
          ),
          TextSpan(
            text: snap.connectionState != ConnectionState.done ? '…' : (snap.data ?? 'not available'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    ),
  );
}
