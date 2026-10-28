import 'package:flutter_test/flutter_test.dart';
import 'package:myrecover/models/item.dart';
import 'package:myrecover/services/recommender.dart';

Item _item(String id, String title, {String category = 'Other', String description = ''}) => Item(
      id: id,
      userId: 'u',
      reporter: 'r',
      type: 'lost',
      title: title,
      category: category,
      description: description,
      location: 'UiTM Arau',
      date: DateTime(2026, 10, 1),
      contact: '012',
      status: 'pending',
    );

void main() {
  final items = [
    _item('phone', 'iPhone 13', category: 'Electronics', description: 'Black case'),
    _item('blackbag', 'Black backpack', category: 'Accessories', description: 'JanSport with laptop'),
    _item('bluebag', 'Blue sling bag', category: 'Accessories'),
    _item('keys', 'Car keys', category: 'Keys', description: 'Honda keychain'),
  ];
  final rec = ItemRecommender(items);

  test('tokenize folds plurals, synonyms and Malay words', () {
    expect(tokenize('Beg Hitam'), ['bag', 'black']);
    expect(tokenize('Black backpacks'), ['black', 'bag']);
    expect(tokenize('glasses and watches'), ['glass', 'watch']);
  });

  test('search ranks the black bag first, other bags next, keys excluded', () {
    final ids = rec.search(items, 'black bag').map((i) => i.id).toList();
    expect(ids.first, 'blackbag');
    expect(ids.indexOf('bluebag'), lessThan(ids.indexOf('phone')));
    expect(ids, isNot(contains('keys')));
  });

  test('partial words match while typing', () {
    // "backp" folds into "bag", so both bags match and nothing else does.
    expect(rec.search(items, 'backp').map((i) => i.id).toSet(), {'blackbag', 'bluebag'});
    expect(rec.search(items, 'bla').first.id, 'blackbag');
  });

  test('Malay search finds English items', () {
    expect(rec.search(items, 'beg hitam').first.id, 'blackbag');
  });

  test('recommendations follow recent searches', () {
    final ids = rec.recommend(items, ['black bag']).map((i) => i.id).toList();
    expect(ids.first, 'blackbag');
    expect(ids, isNot(contains('keys')));
    expect(rec.recommend(items, []), isEmpty);
  });

  test('unrelated reports score below the partner threshold', () {
    final pair = [
      _item('lostUmbrella', 'Blue umbrella', category: 'Accessories', description: 'Navy blue foldable umbrella'),
      _item('honda', 'Honda key', category: 'Keys', description: 'Honda car key with a red keychain'),
    ];
    final r = ItemRecommender(pair);
    const query = 'Navy umbrella Accessories Found a navy foldable umbrella at the cafeteria';
    expect(r.score(pair[0], query), greaterThan(0.15));
    expect(r.score(pair[1], query), lessThan(0.05));
  });
}
