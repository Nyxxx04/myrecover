import 'package:shared_preferences/shared_preferences.dart';

/// The user's recent searches, newest first, saved on this device so the
/// Discover tab can recommend similar items the next time the app opens.
class SearchHistory {
  SearchHistory(this.uid);

  final String uid;
  static const _max = 10;

  String get _key => 'search_history_$uid';
  List<String> _queries = [];

  List<String> get queries => List.unmodifiable(_queries);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _queries = prefs.getStringList(_key) ?? [];
    } catch (_) {
      _queries = [];
    }
  }

  Future<void> add(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return;
    // Typing "bl", "bla", "black" in one go should leave only "black".
    _queries
      ..removeWhere((old) => old == q || q.startsWith(old) || old.startsWith(q))
      ..insert(0, q);
    if (_queries.length > _max) _queries = _queries.sublist(0, _max);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _queries);
    } catch (_) {
      // History is a convenience; ignore storage failures.
    }
  }

  Future<void> clear() async {
    _queries = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
