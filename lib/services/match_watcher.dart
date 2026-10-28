import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item.dart';
import 'ai_service.dart';
import 'claim_service.dart';
import 'item_service.dart';
import 'notifier.dart';
import 'recommender.dart';

/// Background (and on-open) checks for the signed-in user:
/// 1. AI-compare their open reports with new reports; notify on a strong match.
/// 2. Admins: AI-check new ownership claims and notify that one needs review.
/// 3. Claimants: tell them when the admin decides on their claim.
/// 4. Finders: tell them when an item they found has been claimed (anonymously).
///
/// Remembers what it already checked/notified so the AI isn't asked twice.
class MatchWatcher {
  static const notifyAtScore = 75;
  static const _checkedKey = 'watcher_checked_pairs';
  static const _notifiedKey = 'watcher_notified';

  static bool _running = false;

  static Future<void> run({int maxAiCalls = 3}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _running) return;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final notified = (prefs.getStringList(_notifiedKey) ?? []).toSet();
      final role = (await FirebaseFirestore.instance.collection('users').doc(uid).get()).data()?['role'];

      // Each check is independent: one failing (AI busy, offline, rules) doesn't stop the others.
      await _guard(() => _checkMatches(uid, prefs, maxAiCalls));
      if (role == 'admin') await _guard(_reviewClaimsAsAdmin);
      await _guard(() => _reportClaimResults(uid, notified));
      await _guard(() => _reportClaimedItems(uid, notified));
      await prefs.setStringList(_notifiedKey, notified.toList());
    } catch (e) {
      debugPrint('MatchWatcher: skipped this run: $e'); // e.g. storage unavailable; retry next run
    } finally {
      _running = false;
    }
  }

  static Future<void> _guard(Future<void> Function() check) async {
    try {
      await check();
    } catch (e) {
      debugPrint('MatchWatcher: check failed, will retry next run: $e');
    }
  }

  static Future<void> _checkMatches(String uid, SharedPreferences prefs, int maxAiCalls) async {
    final checked = (prefs.getStringList(_checkedKey) ?? []).toSet();
    final all = await ItemService.instance.allItemsOnce();
    final rec = ItemRecommender(all);
    var calls = 0;

    for (final mine in all.where((i) => i.userId == uid && i.status == 'pending')) {
      if (calls >= maxAiCalls) break;
      final query = '${mine.title} ${mine.category} ${mine.description}';
      // Plausible new candidates only (cheap TF-IDF filter before any AI call).
      final scored = [
        for (final c in all)
          if (c.type != mine.type && c.userId != uid && !checked.contains('${mine.id}:${c.id}'))
            (c, rec.score(c, query)),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      final fresh = [
        for (final (c, s) in scored.take(4))
          if (s > 0.05) c,
      ];
      if (fresh.isEmpty) continue;

      calls++;
      final matches = await AiService.instance.match(mine, fresh);
      debugPrint('MatchWatcher: ${mine.title} vs ${fresh.length} -> ${matches.map((m) => m.score).toList()}');
      checked.addAll(fresh.map((c) => '${mine.id}:${c.id}'));

      final byId = {for (final c in fresh) c.id: c};
      for (final m in matches.where((m) => m.score >= notifyAtScore)) {
        final other = byId[m.id];
        if (other == null) continue;
        await Notifier.show(
          'match:${mine.id}:${other.id}',
          '✨ ${m.score}% match for your ${mine.title}',
          '${_label(other)}: ${other.title}. ${m.reason}',
        );
      }
    }
    // Keep the memory bounded.
    final list = checked.toList();
    await prefs.setStringList(_checkedKey, list.length > 1000 ? list.sublist(list.length - 1000) : list);
  }

  static Future<void> _reviewClaimsAsAdmin() async {
    for (final claim in await ClaimService.instance.processPendingClaims()) {
      await Notifier.show(
        'claim-review:${claim.id}',
        '🛡 New claim to review: ${claim.itemTitle}',
        claim.isVerified
            ? 'AI check passed (${claim.confidence}%). Open Claims to approve.'
            : 'AI could not verify the answers (${claim.confidence}%). Open Claims to decide.',
      );
    }
  }

  /// Claimant side: one notification per final decision.
  static Future<void> _reportClaimResults(String uid, Set<String> notified) async {
    for (final claim in await ClaimService.instance.claimsByMe(uid)) {
      if (!claim.isApproved && !claim.isDismissed) continue;
      final key = 'claim:${claim.id}:${claim.status}';
      if (!notified.add(key)) continue;
      await Notifier.show(
        key,
        claim.isApproved ? '✅ Your claim was approved' : "Your claim wasn't approved",
        claim.isApproved
            ? 'Collect your ${claim.itemTitle} at the Student Affairs Department. Bring your student ID.'
            : '${claim.itemTitle}: contact the Student Affairs Department if you have proof of ownership.',
      );
    }
  }

  /// Finder side: told when an item they handed in has been claimed (no names).
  static Future<void> _reportClaimedItems(String uid, Set<String> notified) async {
    for (final item in await ItemService.instance.itemsOfOnce(uid)) {
      if (item.isLost || item.claimStatus != 'claimed') continue;
      final key = 'claimed:${item.id}';
      if (!notified.add(key)) continue;
      await Notifier.show(
        key,
        '🎉 The ${item.title} you found has been claimed',
        'Its owner was verified by the admin. Thank you for handing it in!',
      );
    }
  }

  static String _label(Item i) => i.isLost ? 'Lost report' : 'Found report';
}
