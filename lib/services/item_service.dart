import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/item.dart';
import 'recommender.dart';

class ItemService {
  ItemService._();
  static final instance = ItemService._();

  final _items = FirebaseFirestore.instance.collection('items');
  final _returns = FirebaseFirestore.instance.collection('returns');

  /// Returned items are deleted, so this doc keeps a running count of them.
  final _stats = FirebaseFirestore.instance.collection('stats').doc('summary');

  Stream<int> returnedCount() => _stats.snapshots().map((doc) => (doc.data()?['returned'] as num?)?.toInt() ?? 0);

  /// Every item, newest first.
  Stream<List<Item>> allItems() =>
      _items.orderBy('createdAt', descending: true).snapshots().map((snap) => snap.docs.map(Item.fromDoc).toList());

  /// Every item right now (one read, not a live stream).
  Future<List<Item>> allItemsOnce() async =>
      (await _items.orderBy('createdAt', descending: true).get()).docs.map(Item.fromDoc).toList();

  Future<List<Item>> itemsOfOnce(String uid) async =>
      (await _items.where('userId', isEqualTo: uid).get()).docs.map(Item.fromDoc).toList();

  /// Items reported by one user, newest first. Sorted on the device so no
  /// composite Firestore index is needed.
  Stream<List<Item>> itemsOf(String uid) => _items.where('userId', isEqualTo: uid).snapshots().map((snap) {
    final items = snap.docs.map(Item.fromDoc).toList();
    items.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
    return items;
  });

  /// Saves a new report and returns its id.
  Future<String> create(ItemDraft draft, AppUser user) async => (await _items.add({
    'userId': user.uid,
    'reporter': user.username,
    'type': draft.type,
    'title': draft.title,
    'category': draft.category,
    'description': draft.description,
    'location': draft.location,
    'latitude': draft.latitude,
    'longitude': draft.longitude,
    'date': Timestamp.fromDate(DateTime(draft.date.year, draft.date.month, draft.date.day)),
    'contact': draft.contact,
    'status': 'pending',
    'imageBase64': draft.imageBase64,
    if (draft.claimQuestions.isNotEmpty) 'claimQuestions': draft.claimQuestions,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  })).id;

  /// Admin edit. Marking an item as returned removes it (and its matching
  /// report on the other side, if given), same as the web app.
  /// Returns true when the item was deleted.
  Future<bool> adminUpdate(
    String id, {
    required String title,
    required String description,
    required String status,
    String? partnerId,
  }) async {
    if (status == 'returned') {
      // The lost and found reports of the same object close together and
      // count as one return.
      final ids = [id, ?partnerId];
      final notices = await _returnNotices(ids);
      final batch = FirebaseFirestore.instance.batch()
        ..set(_stats, {'returned': FieldValue.increment(1)}, SetOptions(merge: true));
      for (final i in ids) {
        batch.delete(_items.doc(i));
      }
      notices.forEach((uid, notice) {
        batch.set(_returns.doc('${id}_$uid'), {...notice, 'userId': uid, 'returnedAt': FieldValue.serverTimestamp()});
      });
      await batch.commit();
      return true;
    }
    await _items.doc(id).update({
      'title': title,
      'description': description,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return false;
  }

  /// Who to tell that an item is back with its owner: the finder, the person
  /// who reported it lost, and anyone whose claim on it was approved.
  /// Returned items are deleted, so each gets a notice their app picks up.
  Future<Map<String, Map<String, dynamic>>> _returnNotices(List<String> itemIds) async {
    final notices = <String, Map<String, dynamic>>{};
    for (final snap in await Future.wait(itemIds.map((i) => _items.doc(i).get()))) {
      final data = snap.data();
      if (data == null) continue;
      notices[data['userId'] as String] = {
        'role': data['type'] == 'found' ? 'finder' : 'owner',
        'itemTitle': data['title'],
      };
    }
    final claims = await FirebaseFirestore.instance.collection('claims').where('itemId', whereIn: itemIds).get();
    for (final c in claims.docs.where((c) => c.data()['status'] == 'approved')) {
      notices.putIfAbsent(c.data()['claimantUid'] as String, () => {'role': 'owner', 'itemTitle': c.data()['itemTitle']});
    }
    return notices;
  }

  /// "Your item was returned" notices for [uid] (see [_returnNotices]).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> returnNoticesFor(String uid) async =>
      (await _returns.where('userId', isEqualTo: uid).get()).docs;

  Future<void> delete(String id) => _items.doc(id).delete();

  /// Opposite-side reports most likely to be the same object as [item], best
  /// first. A verified ownership claim links them for sure; otherwise text
  /// similarity is used.
  Future<List<Item>> likelyPartners(Item item) async {
    final all = await allItemsOnce();
    final pool = all.where((i) => i.type != item.type && i.id != item.id && i.status == 'pending').toList();
    if (pool.isEmpty) return [];

    // found item -> its verified claimant's lost reports; lost item -> found items it was verified on.
    final claims = await FirebaseFirestore.instance
        .collection('claims')
        .where('status', whereIn: ['verified', 'approved'])
        .get()
        .then((s) => s.docs.map((d) => d.data()).toList(), onError: (_) => <Map<String, dynamic>>[]);
    final linked = <String>{
      for (final c in claims)
        if (!item.isLost && c['itemId'] == item.id)
          ...pool.where((p) => p.userId == c['claimantUid']).map((p) => p.id)
        else if (item.isLost && c['claimantUid'] == item.userId)
          c['itemId'] as String,
    };

    final rec = ItemRecommender(all);
    final query = '${item.title} ${item.category} ${item.description}';
    // A claim link boosts a report only if it is also about the same kind of
    // thing; a claimant may have other, unrelated lost reports.
    double score(Item p) {
      final text = rec.score(p, query);
      return text + (linked.contains(p.id) && text > 0.05 ? 10 : 0);
    }

    final ranked = pool.where((p) => score(p) > 0.15).toList()..sort((a, b) => score(b).compareTo(score(a)));
    return ranked.take(3).toList();
  }
}
