import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';

import '../app_config.dart';
import '../models/app_user.dart';
import '../models/item.dart';
import '../services/ai_service.dart';
import '../services/claim_service.dart';
import '../services/item_service.dart';
import '../services/recommender.dart';
import '../theme.dart';
import 'animations.dart';
import 'item_card.dart';
import 'item_list.dart';

const aiColor = Color(0xFF7C3AED);

/// Heavy blur for photos showing IC/bank card details (runs off the UI thread).
Future<Uint8List> blurSensitivePhoto(Uint8List jpeg) => compute(_blur, jpeg);

Uint8List _blur(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return bytes;
  return img.encodeJpg(img.gaussianBlur(image, radius: 24), quality: 75);
}

/// "✨ AI is …" progress line.
class AiThinking extends StatelessWidget {
  const AiThinking(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: context.aiText)),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.aiText, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        const Text('This can take a few seconds', style: TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    ),
  );
}

class AiErrorBox extends StatelessWidget {
  const AiErrorBox(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        const Icon(Icons.cloud_off, color: Colors.grey, size: 36),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        if (onRetry != null)
          TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
      ],
    ),
  );
}

Future<void> _showSheet(BuildContext context, Widget Function(ScrollController) builder) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => builder(controller),
    ),
  );
}

// ---------------------------------------------------------------------------
// Smart matching
// ---------------------------------------------------------------------------

void showMatches(BuildContext context, Item item, AppUser user) =>
    _showSheet(context, (controller) => _MatchesSheet(item: item, user: user, controller: controller));

class _MatchesSheet extends StatefulWidget {
  const _MatchesSheet({required this.item, required this.user, required this.controller});
  final Item item;
  final AppUser user;
  final ScrollController controller;

  @override
  State<_MatchesSheet> createState() => _MatchesSheetState();
}

class _MatchesSheetState extends State<_MatchesSheet> {
  List<(Item, AiMatch)>? _results;
  String? _error;

  String get _opposite => widget.item.isLost ? 'found' : 'lost';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _results = null;
      _error = null;
    });
    try {
      final all = await ItemService.instance.allItemsOnce();
      final pool = all
          .where((i) => i.type == _opposite && i.userId != widget.item.userId && i.id != widget.item.id)
          .toList();
      if (pool.isEmpty) {
        setState(() => _results = []);
        return;
      }
      // Cheap TF-IDF pre-filter so the AI only compares the most plausible few.
      final rec = ItemRecommender(all);
      final query = '${widget.item.title} ${widget.item.category} ${widget.item.description}';
      pool.sort((a, b) => rec.score(b, query).compareTo(rec.score(a, query)));
      final candidates = pool.take(6).toList();

      final matches = await AiService.instance.match(widget.item, candidates);
      final byId = {for (final c in candidates) c.id: c};
      final results = [
        for (final m in matches)
          if (byId[m.id] != null) (byId[m.id]!, m),
      ]..sort((a, b) => b.$2.score.compareTo(a.$2.score));
      if (mounted) setState(() => _results = results);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not check matches: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Text(
          '✨ Possible matches',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          'AI compared "${widget.item.title}" with $_opposite reports, including their photos.',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        if (_error != null)
          AiErrorBox(_error!, onRetry: _load)
        else if (results == null)
          const AiThinking('AI is comparing photos and descriptions…')
        else if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'No likely matches yet. We will keep the report up — check again later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.mutedText),
            ),
          )
        else
          for (final (i, (candidate, match)) in results.indexed)
            AnimatedEntry(
              index: i,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ScoreBanner(match: match),
                  ItemCard(item: candidate, actions: [contactAction(context, candidate, widget.user)]),
                ],
              ),
            ),
      ],
    );
  }
}

class _ScoreBanner extends StatelessWidget {
  const _ScoreBanner({required this.match});
  final AiMatch match;

  @override
  Widget build(BuildContext context) {
    final color = match.score >= 75 ? foundColor : (match.score >= 50 ? lostColor : Colors.grey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
            child: Text(
              '${match.score}% match',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(match.reason, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ownership verification ("This is mine")
// ---------------------------------------------------------------------------

/// The button that leads to contact details: claim a found item, or reach
/// the owner of a lost one. Contacts are never shown on cards directly.
Widget contactAction(BuildContext context, Item item, AppUser user) => item.isLost
    ? TextButton.icon(
        onPressed: () => showFoundIt(context, item),
        style: TextButton.styleFrom(foregroundColor: context.aiText),
        icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
        label: const Text('I found this'),
      )
    : TextButton.icon(
        onPressed: () => showClaim(context, item, user),
        style: TextButton.styleFrom(foregroundColor: context.aiText),
        icon: const Icon(Icons.shield_outlined, size: 18),
        label: const Text('This is mine'),
      );

void showFoundIt(BuildContext context, Item item) => _showSheet(
  context,
  (controller) => ListView(
    controller: controller,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
    children: [
      Text(
        'Found "${item.title}"?',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text('Thank you for helping! To keep everyone safe, items are returned through the admin, not directly.'),
      const SizedBox(height: 16),
      const HandoverCard(
        steps: [
          'Report it in the app as found (Report Item → I found something).',
          'Hand the item in at the $handoverPlace.',
          'The admin verifies the owner and returns it. You stay anonymous.',
        ],
      ),
    ],
  ),
);

/// Where to hand in / collect items, with the admin's number.
class HandoverCard extends StatelessWidget {
  const HandoverCard({super.key, this.steps = const []});
  final List<String> steps;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.isDark ? const Color(0xFF12352A) : const Color(0xFFECFDF5),
      border: Border.all(color: context.isDark ? const Color(0xFF1F6F54) : const Color(0xFFA7F3D0)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, step) in steps.indexed)
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('${i + 1}. $step')),
        if (steps.isNotEmpty) const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.account_balance_outlined, color: foundColor),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(handoverPlace, style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.phone_outlined, color: foundColor),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Admin: $adminPhone', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: 'Copy number',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: adminPhone));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Copied: $adminPhone')));
              },
            ),
          ],
        ),
      ],
    ),
  );
}

void showClaim(BuildContext context, Item item, AppUser user) =>
    _showSheet(context, (controller) => _ClaimSheet(item: item, user: user, controller: controller));

class _ClaimSheet extends StatefulWidget {
  const _ClaimSheet({required this.item, required this.user, required this.controller});
  final Item item;
  final AppUser user;
  final ScrollController controller;

  @override
  State<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends State<_ClaimSheet> {
  final _form = GlobalKey<FormState>();
  late final _contact = TextEditingController(text: widget.user.email);
  late final _answers = [for (final _ in widget.item.claimQuestions) TextEditingController()];
  // Rules only allow reading a claim once it exists (it names the claimant),
  // so a denied read just means "no claim yet"; we listen again after sending.
  late Stream<Claim?> _claim = ClaimService.instance.myClaimOn(widget.item.id, widget.user.uid);
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    for (final c in [_contact, ..._answers]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ClaimService.instance.submit(
        widget.item,
        widget.user,
        contact: _contact.text.trim(),
        answers: [
          for (var i = 0; i < _answers.length; i++)
            {'question': widget.item.claimQuestions[i], 'answer': _answers[i].text.trim()},
        ],
      );
      if (mounted) setState(() => _claim = ClaimService.instance.myClaimOn(widget.item.id, widget.user.uid));
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Text(
          '🛡 Claim "${widget.item.title}"',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        StreamBuilder<Claim?>(
          stream: _claim,
          builder: (context, snap) => AnimatedSwitcher(
            duration: motionMedium,
            child: snap.connectionState == ConnectionState.waiting && !snap.hasData && !snap.hasError
                ? const Center(key: ValueKey('loading'), child: CircularProgressIndicator())
                : !snap.hasError && snap.data != null
                ? _ClaimStatus(key: ValueKey(snap.data!.status), claim: snap.data!)
                : !widget.item.isProtected
                ? const _Unprotected(key: ValueKey('unprotected'))
                : _formView(),
          ),
        ),
      ],
    );
  }

  Widget _formView() {
    final questions = widget.item.claimQuestions;
    return Form(
      key: _form,
      child: Column(
        key: const ValueKey('form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The finder added a hidden detail. Answer from memory: AI checks your answers and the admin reviews '
            'your claim. You get one try.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < questions.length; i++) ...[
            Text('${i + 1}. ${questions[i]}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _answers[i],
              decoration: const InputDecoration(hintText: 'Your answer'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please answer this question.' : null,
            ),
            const SizedBox(height: 14),
          ],
          const Divider(height: 24),
          Text('Claiming as ${widget.user.username}', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contact,
            decoration: const InputDecoration(
              labelText: 'Your phone or email',
              helperText: 'Only the admin sees this. The finder never does.',
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter how the admin can reach you.' : null,
          ),
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
          const SizedBox(height: 20),
          PressScale(
            child: FilledButton(
              onPressed: _sending ? null : _submit,
              child: ButtonLabel('Send claim', loading: _sending),
            ),
          ),
        ],
      ),
    );
  }
}

class _Unprotected extends StatelessWidget {
  const _Unprotected({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Icon(Icons.info_outline, size: 48, color: Colors.grey),
      SizedBox(height: 8),
      Text(
        "The finder didn't add a verification detail for this item. Visit the admin with proof of ownership "
        '(e.g. a photo of you with it, or a receipt).',
        textAlign: TextAlign.center,
      ),
      SizedBox(height: 12),
      HandoverCard(),
    ],
  );
}

class _ClaimStatus extends StatelessWidget {
  const _ClaimStatus({super.key, required this.claim});
  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, body) = switch (claim.status) {
      'approved' => (
        Icons.verified,
        foundColor,
        'Approved! It looks like yours.',
        'Collect it at the $handoverPlace. Bring your student ID.',
      ),
      'dismissed' => (
        Icons.help_outline,
        lostColor,
        "Your claim wasn't approved",
        'If you have proof of ownership, contact the admin.',
      ),
      _ => (
        Icons.hourglass_top,
        context.aiText,
        'Claim sent',
        "AI checks your answers and the admin reviews your claim. You'll get a notification with the result.",
      ),
    };
    return Column(
      children: [
        Icon(icon, size: 64, color: color),
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(body, textAlign: TextAlign.center),
        if (claim.isApproved && claim.handoverCode != null) ...[
          const SizedBox(height: 16),
          _HandoverQr(code: claim.handoverCode!),
        ],
        if (claim.isApproved || claim.isDismissed) ...[const SizedBox(height: 16), const HandoverCard()],
      ],
    );
  }
}

/// Shown at the office. The admin scans it, or types the code underneath.
class _HandoverQr extends StatelessWidget {
  const _HandoverQr({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: QrImageView(data: code, size: 190, backgroundColor: Colors.white),
      ),
      const SizedBox(height: 10),
      SelectableText(
        code,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3),
      ),
      const SizedBox(height: 4),
      Text(
        'Show this to the admin when you collect your item.',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.mutedText, fontSize: 13),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Admin: insights
// ---------------------------------------------------------------------------

class AiInsightsCard extends StatefulWidget {
  const AiInsightsCard({super.key, required this.items, required this.returned});
  final List<Item> items;
  final int returned;

  @override
  State<AiInsightsCard> createState() => _AiInsightsCardState();
}

class _AiInsightsCardState extends State<AiInsightsCard> {
  AiInsights? _insights;
  String? _error;
  bool _loading = false;

  Map<String, dynamic> _stats() {
    Map<String, int> countBy(Iterable<String> keys) {
      final m = <String, int>{};
      for (final k in keys) {
        m[k] = (m[k] ?? 0) + 1;
      }
      return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
    }

    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final items = widget.items;
    final now = DateTime.now();
    final openDays = [for (final i in items) now.difference(i.date).inDays];
    return {
      'total_active': items.length,
      'lost': items.where((i) => i.isLost).length,
      'found': items.where((i) => !i.isLost).length,
      'returned_all_time': widget.returned,
      'by_category': countBy(items.map((i) => i.category)),
      'top_locations': Map.fromEntries(countBy(items.map((i) => i.location.split(',').first.trim())).entries.take(8)),
      'lost_or_found_by_weekday': countBy(items.map((i) => weekdays[i.date.weekday - 1])),
      'average_days_open': openDays.isEmpty ? 0 : (openDays.reduce((a, b) => a + b) / openDays.length).round(),
      'oldest_open_days': openDays.isEmpty ? 0 : openDays.reduce((a, b) => a > b ? a : b),
      'with_photo': items.where((i) => i.imageBytes != null).length,
    };
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final insights = await AiService.instance.insights(_stats());
      if (mounted) setState(() => _insights = insights);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insights = _insights;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: context.aiText.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AnimatedSize(
          duration: motionMedium,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '✨ AI Insights',
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.aiText),
                  ),
                  const Spacer(),
                  if (insights != null && !_loading)
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _generate,
                      icon: Icon(Icons.refresh, color: context.aiText),
                    ),
                ],
              ),
              if (_loading)
                const AiThinking('AI is analysing your reports…')
              else if (_error != null)
                AiErrorBox(_error!, onRetry: _generate)
              else if (insights == null) ...[
                const SizedBox(height: 6),
                const Text(
                  'Get a plain-language summary of trends: where items get lost, what, when, and what to do about it.',
                ),
                const SizedBox(height: 12),
                PressScale(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: aiColor, foregroundColor: Colors.white),
                    onPressed: widget.items.isEmpty ? null : _generate,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Generate insights'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(insights.headline, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 10),
                for (final s in insights.insights) _bullet('📊', s),
                if (insights.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Suggestions', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  for (final s in insights.suggestions) _bullet('💡', s),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullet(String icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Admin: spam / duplicate scan
// ---------------------------------------------------------------------------

void showModeration(BuildContext context) =>
    _showSheet(context, (controller) => _ModerationSheet(controller: controller));

class _ModerationSheet extends StatefulWidget {
  const _ModerationSheet({required this.controller});
  final ScrollController controller;

  @override
  State<_ModerationSheet> createState() => _ModerationSheetState();
}

class _ModerationSheetState extends State<_ModerationSheet> {
  List<(AiFlag, Item, Item?)>? _flags;
  String? _error;
  final _deleted = <String>{};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _flags = null;
      _error = null;
    });
    try {
      final items = await ItemService.instance.allItemsOnce();
      if (items.isEmpty) {
        setState(() => _flags = []);
        return;
      }
      final byId = {for (final i in items) i.id: i};
      final flags = await AiService.instance.moderate(items);
      if (mounted) {
        setState(
          () => _flags = [
            for (final f in flags)
              if (byId[f.id] != null) (f, byId[f.id]!, byId[f.relatedId]),
          ],
        );
      }
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _delete(Item item) async {
    if (!await confirmDialog(context, 'Delete "${item.title}"?')) return;
    await ItemService.instance.delete(item.id);
    setState(() => _deleted.add(item.id));
  }

  @override
  Widget build(BuildContext context) {
    final flags = _flags?.where((f) => !_deleted.contains(f.$2.id)).toList();
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Text(
          '🕵️ Fake report check',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Text(
          'AI flags reports that may be fake, duplicated, spam or inappropriate. Review before deleting.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        if (_error != null)
          AiErrorBox(_error!, onRetry: _scan)
        else if (flags == null)
          const AiThinking('AI is reviewing every report…')
        else if (flags.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(Icons.verified_user, size: 48, color: foundColor),
                SizedBox(height: 8),
                Text('All clear: no suspicious reports found.'),
              ],
            ),
          )
        else
          for (final (i, (flag, item, related)) in flags.indexed)
            AnimatedEntry(
              index: i,
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _IssueChip(flag.issue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.title,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(flag.reason),
                      if (related != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Same as: "${related.title}" by ${related.reporter}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                      Text('Reported by ${item.reporter}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _delete(item),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete report'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _IssueChip extends StatelessWidget {
  const _IssueChip(this.issue);
  final String issue;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (issue) {
      'fake' => ('Possibly fake', Colors.deepOrange),
      'duplicate' => ('Duplicate', lostColor),
      'inappropriate' => ('Inappropriate', Colors.red),
      _ => ('Spam', Colors.purple),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
