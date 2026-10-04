import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Version 1 binds node-local Unicode code points to the exact semantic text.
/// Missing and future versions remain uninterpreted; reading does not migrate.
abstract final class NovelReaderAnchorFormat {
  static const int legacyUnknown = 0;
  static const int semanticCodePoints = 1;

  static String textIdentity(String semanticText) =>
      'novel-text-v1:${sha256.convert(utf8.encode(semanticText))}';

  static bool isSupported(int version, String? textIdentity) =>
      version == semanticCodePoints &&
      textIdentity != null &&
      textIdentity.isNotEmpty;
}
