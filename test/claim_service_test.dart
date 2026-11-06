import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrecover/services/claim_service.dart';

/// Three people claim one found item; only Aina knows the secret detail.
void main() {
  late FakeFirebaseFirestore db;
  late ClaimService service;

  Future<Map<String, dynamic>> claimData(String id) async => (await db.collection('claims').doc(id).get()).data()!;

  Future<List<Claim>> claims() async {
    final snap = await db.collection('claims').get();
    return snap.docs.map(Claim.fromDoc).toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    service = ClaimService.withDb(db);
    await db.collection('items').doc('umbrella').set({
      'userId': 'finder',
      'type': 'found',
      'title': 'Red umbrella',
      'status': 'pending',
      'claimStatus': 'review',
    });
    // After the AI check: Aina answered correctly, the other two did not.
    for (final (uid, status, confidence) in [('aina', 'verified', 95), ('badrul', 'rejected', 10), ('chong', 'rejected', 20)]) {
      await db.collection('claims').doc('umbrella_$uid').set({
        'itemId': 'umbrella',
        'itemTitle': 'Red umbrella',
        'ownerUid': 'finder',
        'claimantUid': uid,
        'claimantName': uid,
        'claimantContact': '$uid@example.com',
        'answers': [
          {'question': 'What colour is the handle?', 'answer': uid == 'aina' ? 'red' : 'blue'},
        ],
        'status': status,
        'confidence': confidence,
      });
    }
  });

  test('approving the correct claimant closes the other two in one step', () async {
    final [aina, badrul, chong] = await claims();
    expect(aina.claimantUid, 'aina');

    await service.approve(aina, closeOthers: [badrul, chong]);

    final approved = await claimData('umbrella_aina');
    expect(approved['status'], 'approved');
    expect(approved['handoverCode'], matches(RegExp(r'^[A-HJ-NP-Z2-9]{8}$')));
    expect((await claimData('umbrella_badrul'))['status'], 'dismissed');
    expect((await claimData('umbrella_chong'))['status'], 'dismissed');
    expect((await db.collection('items').doc('umbrella').get()).data()!['claimStatus'], 'claimed');
  });

  test('the two who lost out are marked as "went to its owner", not just rejected', () async {
    final [aina, badrul, chong] = await claims();
    await service.approve(aina, closeOthers: [badrul, chong]);

    final [ainaAfter, badrulAfter, chongAfter] = await claims();
    expect(badrulAfter.lostToOwner, isTrue);
    expect(chongAfter.lostToOwner, isTrue);
    expect(ainaAfter.lostToOwner, isFalse);
  });

  test('a claim the admin dismisses on its own is a plain rejection', () async {
    final [_, badrul, _] = await claims();
    await service.dismiss(badrul);

    final [_, badrulAfter, _] = await claims();
    expect(badrulAfter.isDismissed, isTrue);
    expect(badrulAfter.lostToOwner, isFalse);
  });

  test('only the approved claimant has a handover code, and it finds their claim', () async {
    final [aina, badrul, chong] = await claims();
    await service.approve(aina, closeOthers: [badrul, chong]);

    final code = (await claimData('umbrella_aina'))['handoverCode'] as String;
    expect((await claimData('umbrella_badrul'))['handoverCode'], isNull);
    expect((await claimData('umbrella_chong'))['handoverCode'], isNull);

    final found = await service.claimForCode(code);
    expect(found?.claimantUid, 'aina');
    expect(found?.isApproved, isTrue);
    expect(await service.claimForCode('WRONGCOD'), isNull);
  });

  test('a claim the admin unticks stays open', () async {
    final [aina, badrul, chong] = await claims();

    await service.approve(aina, closeOthers: [badrul]);

    expect((await claimData('umbrella_badrul'))['status'], 'dismissed');
    expect((await claimData('umbrella_chong'))['status'], 'rejected');
  });

  test('remaining claims can be closed later, after the owner was approved', () async {
    final [aina, badrul, chong] = await claims();
    await service.approve(aina);
    expect((await claimData('umbrella_badrul'))['status'], 'rejected');

    await service.dismissAll([badrul, chong]);

    expect((await claimData('umbrella_aina'))['status'], 'approved');
    expect((await claimData('umbrella_badrul'))['closedReason'], 'ownerFound');
    expect((await claimData('umbrella_chong'))['closedReason'], 'ownerFound');
  });
}
