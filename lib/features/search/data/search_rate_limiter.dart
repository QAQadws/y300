import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';

class SearchRateLimiter {
  SearchRateLimiter({
    this.cooldown = const Duration(seconds: 10),
    SharedPreferences? sharedPreferences,
    DateTime Function()? nowProvider,
  }) : _sharedPreferences = sharedPreferences,
       _nowProvider = nowProvider ?? DateTime.now;

  static const String _lastSearchAtKey = 'search.last_search_at_ms';

  final Duration cooldown;
  final SharedPreferences? _sharedPreferences;
  final DateTime Function() _nowProvider;

  Future<SearchRateLimitResult> check() async {
    final prefs = _sharedPreferences ?? await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastSearchAtKey);
    if (lastMs == null) {
      return const SearchRateLimitResult.allowed();
    }
    final now = _nowProvider();
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    final elapsed = now.difference(last);
    if (elapsed >= cooldown) {
      return const SearchRateLimitResult.allowed();
    }
    return SearchRateLimitResult.blocked(cooldown - elapsed);
  }

  Future<void> markTriggered() async {
    final prefs = _sharedPreferences ?? await SharedPreferences.getInstance();
    await prefs.setInt(_lastSearchAtKey, _nowProvider().millisecondsSinceEpoch);
  }
}

