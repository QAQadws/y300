import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/technical_storage_keys.dart';

final class SearchRateLimitResult {
  const SearchRateLimitResult.allowed()
    : isAllowed = true,
      retryAfter = Duration.zero;

  const SearchRateLimitResult.blocked(this.retryAfter) : isAllowed = false;

  final bool isAllowed;
  final Duration retryAfter;
}

class SearchRateLimiter {
  SearchRateLimiter({
    this.cooldown = defaultCooldown,
    SharedPreferences? sharedPreferences,
    DateTime Function()? nowProvider,
  }) : _sharedPreferences = sharedPreferences,
       _nowProvider = nowProvider ?? DateTime.now;

  static const Duration defaultCooldown = Duration(milliseconds: 10500);

  final Duration cooldown;
  final SharedPreferences? _sharedPreferences;
  final DateTime Function() _nowProvider;

  Future<SearchRateLimitResult> check() async {
    final prefs = _sharedPreferences ?? await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(TechnicalStorageKeys.searchLastSearchAtMs);
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
    await prefs.setInt(
      TechnicalStorageKeys.searchLastSearchAtMs,
      _nowProvider().millisecondsSinceEpoch,
    );
  }
}
