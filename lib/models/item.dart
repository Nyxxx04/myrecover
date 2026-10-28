import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

const itemCategories = ['Electronics', 'Clothing', 'Accessories', 'Documents', 'Keys', 'Other'];

String categoryEmoji(String category) => switch (category) {
  'Electronics' => '📱',
  'Clothing' => '👕',
  'Accessories' => '👜',
  'Documents' => '📄',
  'Keys' => '🔑',
  _ => '📦',
};

class Item {
  Item({
    required this.id,
    required this.userId,
    required this.reporter,
    required this.type,
    required this.title,
    required this.category,
    required this.description,
    required this.location,
    required this.date,
    required this.contact,
    required this.status,
    this.latitude,
    this.longitude,
    this.imageBase64,
    this.createdAt,
    this.updatedAt,
    this.claimQuestions = const [],
    this.claimStatus,
  });

  final String id;
  final String userId;
  final String reporter;
  final String type; // lost | found
  final String title;
  final String category;
  final String description;
  final String location;
  final double? latitude;
  final double? longitude;
  final DateTime date;
  final String contact;
  final String status; // pending | returned
  final String? imageBase64;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Questions claimants answer; the finder's secret detail they check is
  /// stored separately in `secrets/{id}`, readable only by the finder and the admin.
  final List<String> claimQuestions;

  /// Set by the admin: 'review' while a claim passed the AI check and awaits
  /// approval, 'claimed' once approved. Lets the finder follow progress
  /// without seeing who claimed it.
  final String? claimStatus;

  bool get isLost => type == 'lost';
  bool get isProtected => claimQuestions.isNotEmpty;
  bool get hasCoordinates => latitude != null && longitude != null;
  String get emoji => categoryEmoji(category);

  late final Uint8List? imageBytes = imageBase64 == null || imageBase64!.isEmpty ? null : base64Decode(imageBase64!);

  factory Item.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Item(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      reporter: d['reporter'] as String? ?? '',
      type: d['type'] as String? ?? 'lost',
      title: d['title'] as String? ?? '',
      category: d['category'] as String? ?? 'Other',
      description: d['description'] as String? ?? '',
      location: d['location'] as String? ?? '',
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      date: (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      contact: d['contact'] as String? ?? '',
      status: d['status'] as String? ?? 'pending',
      imageBase64: d['imageBase64'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      claimQuestions: List<String>.from(d['claimQuestions'] as List? ?? const []),
      claimStatus: d['claimStatus'] as String?,
    );
  }
}

/// Data collected by the report form, before it is saved.
class ItemDraft {
  ItemDraft({
    required this.type,
    required this.title,
    required this.category,
    required this.description,
    required this.location,
    required this.date,
    required this.contact,
    this.latitude,
    this.longitude,
    this.imageBase64,
    this.claimQuestions = const [],
  });

  final String type;
  final String title;
  final String category;
  final String description;
  final String location;
  final double? latitude;
  final double? longitude;
  final DateTime date;
  final String contact;
  final String? imageBase64;
  final List<String> claimQuestions;
}
