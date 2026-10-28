import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  AppUser({required this.uid, required this.name, required this.username, required this.email, required this.role});

  final String uid;
  final String name;
  final String username;
  final String email;
  final String role; // user | admin

  bool get isAdmin => role == 'admin';

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return AppUser(
      uid: doc.id,
      name: d['name'] as String? ?? '',
      username: d['username'] as String? ?? '',
      email: d['email'] as String? ?? '',
      role: d['role'] as String? ?? 'user',
    );
  }
}
