import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/item.dart';
import 'ai_service.dart';

/// A request by someone saying a found item is theirs.
class Claim {
  Claim.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc)
    : id = doc.id,
      itemId = doc.data()!['itemId'] as String,
      itemTitle = doc.data()!['itemTitle'] as String? ?? 'Item',
      ownerUid = doc.data()!['ownerUid'] as String,
      claimantUid = doc.data()!['claimantUid'] as String,
      claimantName = doc.data()!['claimantName'] as String? ?? '',
      claimantContact = doc.data()!['claimantContact'] as String? ?? '',
      answers = [
        for (final a in doc.data()!['answers'] as List? ?? const [])
          {'question': a['question'] as String, 'answer': a['answer'] as String},
      ],
      status = doc.data()!['status'] as String? ?? 'pending',
      confidence = (doc.data()!['confidence'] as num?)?.toInt() ?? 0,
      feedback = doc.data()!['feedback'] as String? ?? '',
      handoverCode = doc.data()!['handoverCode'] as String?,
      createdAt = (doc.data()!['createdAt'] as Timestamp?)?.toDate();

  final String id, itemId, itemTitle, ownerUid, claimantUid, claimantName, claimantContact;
  final List<Map<String, String>> answers;

  /// pending (waiting for the AI check) → verified / rejected (AI verdict,
  /// waiting for the admin) → approved (admin: collect at the office) or
  /// dismissed (admin said no).
  final String status;
  final int confidence;
  final String feedback;
  final String? handoverCode;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';
  bool get isVerified => status == 'verified';
  bool get isApproved => status == 'approved';
  bool get isDismissed => status == 'dismissed';
  bool get awaitsAdmin => status == 'verified' || status == 'rejected';
}

/// Ownership verification, run through the admin:
/// - the finder's secret detail lives in `secrets/{itemId}` (finder and admin only);
/// - a claimant writes answers to `claims/{itemId}_{uid}` (one attempt per item);
///   finders can't read claims, so the two stay anonymous to each other;
/// - the admin's phone checks pending claims with AI, then the admin approves
///   or dismisses. Approving marks the item 'claimed' so the finder is told.
class ClaimService {
  ClaimService._();
  static final instance = ClaimService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _claims => _db.collection('claims');

  Future<void> saveSecret(String itemId, String ownerUid, String secret) =>
      _db.collection('secrets').doc(itemId).set({'ownerUid': ownerUid, 'secret': secret});

  Future<String?> secretFor(String itemId) async =>
      (await _db.collection('secrets').doc(itemId).get()).data()?['secret'] as String?;

  DocumentReference<Map<String, dynamic>> _claimRef(String itemId, String claimantUid) =>
      _claims.doc('${itemId}_$claimantUid');

  Stream<Claim?> myClaimOn(String itemId, String uid) =>
      _claimRef(itemId, uid).snapshots().map((d) => d.exists ? Claim.fromDoc(d) : null);

  Future<List<Claim>> claimsByMe(String uid) async =>
      (await _claims.where('claimantUid', isEqualTo: uid).get()).docs.map(Claim.fromDoc).toList();

  /// Admin: every claim, newest first.
  Stream<List<Claim>> allClaims() => _claims.snapshots().map((s) {
    final claims = s.docs.map(Claim.fromDoc).toList();
    claims.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
    return claims;
  });

  Future<void> submit(
    Item item,
    AppUser claimant, {
    required String contact,
    required List<Map<String, String>> answers,
  }) async {
    try {
      await _claimRef(item.id, claimant.uid).set({
        'itemId': item.id,
        'itemTitle': item.title,
        'ownerUid': item.userId,
        'claimantUid': claimant.uid,
        'claimantName': claimant.username,
        'claimantContact': contact,
        'answers': answers,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AiException(
        e.code == 'permission-denied'
            ? 'You have already claimed this item.'
            : 'Could not send your claim: ${e.message}',
      );
    }
  }

  /// Admin's phone: AI-checks every pending claim. Returns the checked claims.
  Future<List<Claim>> processPendingClaims() async {
    final pending = await _claims.where('status', isEqualTo: 'pending').get();
    final checked = <Claim>[];
    for (final doc in pending.docs) {
      final claim = Claim.fromDoc(doc);
      final secret = await secretFor(claim.itemId);
      if (secret == null) continue;
      final result = await AiService.instance.judgeClaim(claim.itemTitle, secret, claim.answers);
      await doc.reference.update({
        'status': result.verified ? 'verified' : 'rejected',
        'confidence': result.confidence,
        'feedback': result.feedback,
        'checkedAt': FieldValue.serverTimestamp(),
      });
      if (result.verified) await _setItemClaimStatus(claim.itemId, 'review');
      checked.add(Claim.fromDoc(await doc.reference.get()));
    }
    return checked;
  }

  /// Admin approves: the claimant collects the item at the office, showing
  /// the private handover code (as a QR) that only they can read.
  Future<void> approve(Claim claim) async {
    await _claims.doc(claim.id).update({
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
      'handoverCode': _newHandoverCode(),
    });
    await _setItemClaimStatus(claim.itemId, 'claimed');
  }

  /// No 0/O or 1/I, so it can be read out and typed without mistakes.
  static String _newHandoverCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  /// Admin: the claim a scanned or typed handover code belongs to.
  Future<Claim?> claimForCode(String code) async {
    final found = await _claims.where('handoverCode', isEqualTo: code).limit(1).get();
    return found.docs.isEmpty ? null : Claim.fromDoc(found.docs.first);
  }

  Future<void> dismiss(Claim claim) =>
      _claims.doc(claim.id).update({'status': 'dismissed', 'reviewedAt': FieldValue.serverTimestamp()});

  /// Runs the first time an admin opens the app in a new month: deletes
  /// finished claims (approved / dismissed) from earlier months. Claims still
  /// waiting for the admin are kept. Returns how many were cleared.
  Future<int> monthlyCleanup() async {
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final marker = _db.collection('stats').doc('claimsCleanup');
    if ((await marker.get()).data()?['month'] == month) return 0;

    final startOfMonth = DateTime(now.year, now.month);
    final finished = await _claims.where('status', whereIn: ['approved', 'dismissed']).get();
    final old = finished.docs.where((d) {
      final created = (d.data()['createdAt'] as Timestamp?)?.toDate();
      return created != null && created.isBefore(startOfMonth);
    }).take(450);

    final batch = _db.batch();
    for (final doc in old) {
      batch.delete(doc.reference);
    }
    batch.set(marker, {'month': month, 'cleared': old.length, 'at': FieldValue.serverTimestamp()});
    await batch.commit();
    return old.length;
  }

  Future<void> _setItemClaimStatus(String itemId, String status) async {
    try {
      await _db.collection('items').doc(itemId).update({
        'claimStatus': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      // Item already closed or removed; the claim itself is still recorded.
    }
  }
}
