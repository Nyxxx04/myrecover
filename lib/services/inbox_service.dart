import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class InboxEntry {
  InboxEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc)
    : id = doc.id,
      title = doc.data()!['title'] as String? ?? '',
      body = doc.data()!['body'] as String? ?? '',
      read = doc.data()!['read'] as bool? ?? false,
      createdAt = (doc.data()!['createdAt'] as Timestamp?)?.toDate();

  final String id;
  final String title;
  final String body;
  final bool read;
  final DateTime? createdAt;
}

/// Keeps a copy of each notification in `users/{uid}/inbox`, so it can still
/// be read after being dismissed from the phone.
class InboxService {
  InboxService._();
  static final instance = InboxService._();

  static const _maxShown = 50;

  CollectionReference<Map<String, dynamic>> _inbox(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('inbox');

  Stream<List<InboxEntry>> entries(String uid) => _inbox(uid)
      .orderBy('createdAt', descending: true)
      .limit(_maxShown)
      .snapshots()
      .map((s) => s.docs.map(InboxEntry.fromDoc).toList());

  /// [key] is the notification's unique key, so a repeat replaces the entry.
  /// A failure here must never stop the phone notification or later checks.
  Future<void> add(String key, String title, String body) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _inbox(uid).doc(key).set({
        'title': title,
        'body': body,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Inbox: could not save "$title": $e');
    }
  }

  Future<void> markRead(String uid, Iterable<String> ids) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final id in ids) {
      batch.update(_inbox(uid).doc(id), {'read': true});
    }
    await batch.commit();
  }

  Future<void> remove(String uid, String id) => _inbox(uid).doc(id).delete();

  Future<void> clear(String uid, Iterable<String> ids) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final id in ids) {
      batch.delete(_inbox(uid).doc(id));
    }
    await batch.commit();
  }
}
