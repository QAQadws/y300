import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 轻量 Cookie 存储：按 host 维度持久化键值对
class CookieStore {
  static const String _storageKey = 'network.cookies.v1';

  Future<String?> readCookieHeader(Uri uri) async {
    final all = await _readAll();
    final cookieMap = all[uri.host];
    if (cookieMap == null || cookieMap.isEmpty) {
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
      // 只解析 Set-Cookie 第一段 name=value，忽略属性字段
      final firstSegment = header.split(';').first.trim();
      if (firstSegment.isEmpty || !firstSegment.contains('=')) {
        continue;
      }
      final separatorIndex = firstSegment.indexOf('=');
      final name = firstSegment.substring(0, separatorIndex).trim();
      final value = firstSegment.substring(separatorIndex + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        hostCookies[name] = value;
      }
    }

    all[uri.host] = hostCookies;
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
}
