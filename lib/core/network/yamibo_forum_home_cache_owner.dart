import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_auth_cookie.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/preferences/preferences_store.dart';

/// A local cache permission, never a verified session or command identity.
final class Y300ForumHomeCacheOwner {
  const Y300ForumHomeCacheOwner(this.accountId, this._isCurrent);

  final String accountId;
  final bool Function() _isCurrent;

  bool get isCurrent => _isCurrent();
}

/// Remembers the last remotely confirmed account for these exact auth
/// cookies. Only a digest is persisted; WAF and other changing cookies do not
/// affect the binding. A cold boot may use it solely to read that home's cache.
final class Y300ForumHomeCacheOwnerStore {
  Y300ForumHomeCacheOwnerStore({
    required CookieStore cookies,
    Uri? siteUri,
    SharedPreferencesLoader? preferencesLoader,
  }) : _cookies = cookies,
       _siteUri = siteUri ?? Uri.parse(AppConfig.siteBaseUrl),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final CookieStore _cookies;
  final Uri _siteUri;
  final SharedPreferencesLoader _preferencesLoader;

  Future<void> remember({
    required String accountId,
    required bool Function() isCurrent,
  }) async {
    if ((int.tryParse(accountId) ?? 0) < 1 || !isCurrent()) return;
    final revision = _cookies.revision;
    try {
      final digest = _authDigest(await _cookies.readCookieMap(_siteUri));
      final preferences = await _preferencesLoader();
      if (digest == null || _cookies.revision != revision || !isCurrent()) {
        return;
      }
      await preferences.setString(
        TechnicalStorageKeys.forumHomeCacheOwnerV1,
        jsonEncode({
          'site': _siteUri.origin,
          'accountId': accountId,
          'authDigest': digest,
        }),
      );
    } catch (_) {
      // This optional startup hint must not fail session confirmation.
    }
  }

  Future<Y300ForumHomeCacheOwner?> restore({
    required bool Function() isCurrent,
  }) async {
    final revision = _cookies.revision;
    bool canRead() => isCurrent() && _cookies.revision == revision;
    if (!canRead()) return null;
    try {
      final preferences = await _preferencesLoader();
      final raw = preferences.getString(
        TechnicalStorageKeys.forumHomeCacheOwnerV1,
      );
      if (raw == null) return null;
      final record = jsonDecode(raw);
      if (record is! Map<String, dynamic> ||
          record['site'] != _siteUri.origin) {
        return null;
      }
      final accountId = record['accountId'];
      if (accountId is! String || (int.tryParse(accountId) ?? 0) < 1) {
        return null;
      }
      final digest = _authDigest(await _cookies.readCookieMap(_siteUri));
      if (!canRead() || digest == null || record['authDigest'] != digest) {
        return null;
      }
      return Y300ForumHomeCacheOwner(accountId, canRead);
    } catch (_) {
      return null;
    }
  }

  String? _authDigest(Map<String, String> cookies) {
    if (!YamiboAuthCookie.isLoggedIn(cookies)) return null;
    final entries =
        cookies.entries
            .where(
              (entry) =>
                  entry.key.toLowerCase().endsWith(YamiboAuthCookie.authSuffix),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              for (final entry in entries) [entry.key, entry.value],
            ]),
          ),
        )
        .toString();
  }
}

final yamiboForumHomeCacheOwnerStoreProvider =
    Provider<Y300ForumHomeCacheOwnerStore>((ref) {
      return Y300ForumHomeCacheOwnerStore(
        cookies: ref.watch(cookieStoreProvider),
      );
    });
