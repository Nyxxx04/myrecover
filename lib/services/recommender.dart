import 'dart:math';

import '../models/item.dart';

/// Content-based search and recommendations using TF-IDF + cosine similarity.
///
/// Every item becomes a weighted bag of words (title counts most, then
/// category, then description/location). Words are normalised first:
/// lowercased, plural "s" stripped, and synonyms (including common Malay
/// words) folded together, so "beg hitam" matches "black backpack".
class ItemRecommender {
  ItemRecommender(List<Item> items) {
    for (final item in items) {
      final tf = <String, double>{};
      void add(String text, double weight) {
        for (final t in tokenize(text)) {
          tf[t] = (tf[t] ?? 0) + weight;
        }
      }

      add(item.title, 3);
      add(item.category, 2);
      add(item.description, 1);
      add(item.location, 0.5);
      _termFreq[item.id] = tf;
      for (final t in tf.keys) {
        _docFreq[t] = (_docFreq[t] ?? 0) + 1;
      }
    }
    for (final entry in _termFreq.entries) {
      final vec = {for (final t in entry.value.entries) t.key: t.value * _idf(t.key)};
      _vectors[entry.key] = vec;
      _norms[entry.key] = sqrt(vec.values.fold(0.0, (s, w) => s + w * w));
    }
  }

  final _termFreq = <String, Map<String, double>>{};
  final _docFreq = <String, int>{};
  final _vectors = <String, Map<String, double>>{};
  final _norms = <String, double>{};

  double _idf(String term) => log((_termFreq.length + 1) / ((_docFreq[term] ?? 0) + 1)) + 1;

  /// Cosine similarity (0..1) between a query and an item.
  double score(Item item, String query) {
    final doc = _vectors[item.id];
    final docNorm = _norms[item.id] ?? 0;
    if (doc == null || docNorm == 0) return 0;

    final queryVec = <String, double>{};
    for (final q in tokenize(query)) {
      // Partial words while typing: "bla" matches "black", "backp" matches
      // "backpack" (stored under its canonical word "bag").
      final terms = doc.containsKey(q) || q.length < 3
          ? {q}
          : {
              ...doc.keys.where((t) => t.startsWith(q)),
              for (final e in _synonyms.entries)
                if (e.key.startsWith(q)) e.value,
            };
      for (final t in terms.isEmpty ? {q} : terms) {
        queryVec[t] = (queryVec[t] ?? 0) + _idf(t);
      }
    }
    if (queryVec.isEmpty) return 0;

    var dot = 0.0;
    queryVec.forEach((t, w) => dot += w * (doc[t] ?? 0));
    final queryNorm = sqrt(queryVec.values.fold(0.0, (s, w) => s + w * w));
    return dot / (queryNorm * docNorm);
  }

  /// Items matching an explicit search, best first.
  List<Item> search(List<Item> items, String query) {
    final scored = [for (final item in items) (item, score(item, query))].where((e) => e.$2 > 0).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored) e.$1];
  }

  /// Items similar to the user's recent searches. Newer searches count more.
  List<Item> recommend(List<Item> items, List<String> recentQueries, {double threshold = 0.08, int limit = 5}) {
    if (recentQueries.isEmpty) return [];
    final scored = <(Item, double)>[];
    for (final item in items) {
      var total = 0.0;
      for (var i = 0; i < recentQueries.length; i++) {
        total += pow(0.7, i) * score(item, recentQueries[i]);
      }
      if (total >= threshold) scored.add((item, total));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored.take(limit)) e.$1];
  }
}

const _stopWords = {
  'a',
  'an',
  'the',
  'and',
  'or',
  'of',
  'in',
  'on',
  'at',
  'to',
  'for',
  'with',
  'my',
  'is',
  'it',
  'was',
  'i',
  'near',
  'inside',
  'lost',
  'found',
  'yang',
  'dan',
  'di',
  'saya',
  'ini',
  'itu',
};

/// word → canonical word, so synonyms and Malay terms share one dimension.
const _synonyms = {
  // bags
  'backpack': 'bag', 'handbag': 'bag', 'beg': 'bag', 'sling': 'bag', 'tote': 'bag', 'luggage': 'bag',
  'pouch': 'bag', 'knapsack': 'bag', 'rucksack': 'bag',
  // wallets / cards
  'purse': 'wallet', 'dompet': 'wallet', 'kad': 'card', 'ic': 'card', 'matric': 'card', 'id': 'card',
  // phones & electronics
  'handphone': 'phone', 'smartphone': 'phone', 'iphone': 'phone', 'telefon': 'phone',
  'hp': 'phone', 'mobile': 'phone', 'android': 'phone', 'samsung': 'phone',
  'notebook': 'laptop', 'macbook': 'laptop', 'komputer': 'laptop', 'computer': 'laptop',
  'earphone': 'earbud', 'earpod': 'earbud', 'airpod': 'earbud', 'headphone': 'earbud', 'headset': 'earbud',
  'pengecas': 'charger', 'powerbank': 'charger',
  // keys, bottles, glasses, clothes
  'kunci': 'key', 'keychain': 'key', 'botol': 'bottle', 'tumbler': 'bottle', 'flask': 'bottle',
  'spectacle': 'glass', 'spec': 'glass', 'cermin': 'glass', 'jam': 'watch',
  'baju': 'shirt', 'tshirt': 'shirt', 'jaket': 'jacket', 'hoodie': 'jacket',
  'tudung': 'scarf', 'payung': 'umbrella', 'kasut': 'shoe', 'sneaker': 'shoe', 'selipar': 'shoe',
  // colours
  'hitam': 'black', 'putih': 'white', 'merah': 'red', 'biru': 'blue', 'navy': 'blue', 'hijau': 'green',
  'kuning': 'yellow', 'coklat': 'brown', 'kelabu': 'grey', 'gray': 'grey', 'silver': 'grey',
  'ungu': 'purple', 'oren': 'orange', 'emas': 'gold',
};

List<String> tokenize(String text) {
  final out = <String>[];
  for (final word in text.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
    if (word.isEmpty || _stopWords.contains(word)) continue;
    final w = _singular(word);
    out.add(_synonyms[w] ?? w);
  }
  return out;
}

String _singular(String w) {
  if (w.length <= 3 || w.endsWith('ss')) return w;
  for (final suffix in ['sses', 'ches', 'shes', 'xes']) {
    if (w.endsWith(suffix)) return w.substring(0, w.length - 2);
  }
  return w.endsWith('s') ? w.substring(0, w.length - 1) : w;
}
