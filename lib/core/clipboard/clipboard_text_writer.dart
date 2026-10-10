import 'package:flutter/services.dart';

import 'self_copy_fingerprint_registry.dart';

abstract interface class ClipboardTextWriter {
  Future<void> writeText(String text);
}

/// Preserves platform write failures and records only successful writes.
class PlatformClipboardTextWriter implements ClipboardTextWriter {
  PlatformClipboardTextWriter({
    required SelfCopyFingerprintRegistry selfCopyRegistry,
    Future<void> Function(String text)? platformWrite,
  }) : _selfCopyRegistry = selfCopyRegistry,
       _platformWrite = platformWrite ?? _writePlatformText;

  final SelfCopyFingerprintRegistry _selfCopyRegistry;
  final Future<void> Function(String text) _platformWrite;

  @override
  Future<void> writeText(String text) async {
    await _platformWrite(text);
    _selfCopyRegistry.recordSuccessfulWrite(text);
  }

  static Future<void> _writePlatformText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
