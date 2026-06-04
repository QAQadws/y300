import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 轻量 Cookie 存储：按 host 维度持久化键值对
class CookieStore {
  static const String _storageKey = 'network.cookies.v1';

  Future<Map<String, String>> readCookieMap(Uri uri) async {
    final all = await _readAll();
    final cookieMap = all[uri.host];
    if (cookieMap == null || cookieMap.isEmpty) {
      return <String, String>{};
    }
    return Map<String, String>.from(cookieMap);
  }

  Future<String?> readCookieHeader(Uri uri) async {
    final cookieMap = await readCookieMap(uri);
    if (cookieMap.isEmpty) {
      return null;
    }
    return cookieMap.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  Future<void> saveFromSetCookie(Uri uri, List<String> setCookieHeaders) async {
    if (setCookieHeaders.isEmpty) {
      return;
    }

    final all = await _readAll();
    final hostCookies = <String, String>{...?all[uri.host]};

    for (final header in setCookieHeaders) {
      final segments = header
          .split(';')
          .map((segment) => segment.trim())
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      if (segments.isEmpty) {
        continue;
      }

      // 只解析 Set-Cookie 第一段 name=value，属性字段仅用于识别删除语义。
      final firstSegment = segments.first;
      if (firstSegment.isEmpty || !firstSegment.contains('=')) {
        continue;
      }
      final separatorIndex = firstSegment.indexOf('=');
      final name = firstSegment.substring(0, separatorIndex).trim();
      final value = firstSegment.substring(separatorIndex + 1).trim();
      if (name.isEmpty) {
        continue;
      }
      if (_shouldDeleteCookie(value: value, attributes: segments.skip(1))) {
        hostCookies.remove(name);
        continue;
      }
      if (value.isNotEmpty) {
        hostCookies[name] = value;
      }
    }

    if (hostCookies.isEmpty) {
      all.remove(uri.host);
    } else {
      all[uri.host] = hostCookies;
    }
    await _writeAll(all);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<Map<String, Map<String, String>>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return <String, Map<String, String>>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <String, Map<String, String>>{};
      }

      final result = <String, Map<String, String>>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) {
          continue;
        }
        result[entry.key] = value.map(
          (key, dynamic mapValue) =>
              MapEntry(key.toString(), mapValue.toString()),
        );
      }
      return result;
    } catch (_) {
      // 本地数据损坏时降级为空，避免影响主流程
      return <String, Map<String, String>>{};
    }
  }

  Future<void> _writeAll(Map<String, Map<String, String>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  bool _shouldDeleteCookie({
    required String value,
    required Iterable<String> attributes,
  }) {
    final normalizedValue = value.trim().toLowerCase();
    if (normalizedValue.isEmpty || normalizedValue == 'deleted') {
      return true;
    }

    for (final attribute in attributes) {
      final separatorIndex = attribute.indexOf('=');
      final key = (separatorIndex >= 0
              ? attribute.substring(0, separatorIndex)
              : attribute)
          .trim()
          .toLowerCase();
      final rawValue = separatorIndex >= 0
          ? attribute.substring(separatorIndex + 1).trim()
          : '';
      switch (key) {
        case 'max-age':
          final maxAge = int.tryParse(rawValue);
          if (maxAge != null && maxAge <= 0) {
            return true;
          }
          break;
        case 'expires':
          final expiresAt = _tryParseCookieExpiry(rawValue);
          if (expiresAt != null &&
              !expiresAt.isAfter(DateTime.now().toUtc())) {
            return true;
          }
          break;
      }
    }

    return false;
  }

  DateTime? _tryParseCookieExpiry(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.contains('1970')) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    final match = RegExp(
      r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})[- ]([A-Za-z]{3})[- ](\d{2,4})\s+'
      r'(\d{2}):(\d{2}):(\d{2})\s+GMT$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) {
      return null;
    }

    final month = _monthFromAbbreviation(match.group(2));
    if (month == null) {
      return null;
    }

    final rawYear = int.parse(match.group(3)!);
    final year = rawYear >= 100
        ? rawYear
        : (rawYear >= 70 ? 1900 + rawYear : 2000 + rawYear);
    return DateTime.utc(
      year,
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  int? _monthFromAbbreviation(String? rawValue) {
    final value = rawValue?.trim().toLowerCase();
    return switch (value) {
      'jan' => 1,
      'feb' => 2,
      'mar' => 3,
      'apr' => 4,
      'may' => 5,
      'jun' => 6,
      'jul' => 7,
      'aug' => 8,
      'sep' => 9,
      'oct' => 10,
      'nov' => 11,
      'dec' => 12,
      _ => null,
    };
  }
}
