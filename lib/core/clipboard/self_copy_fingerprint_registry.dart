import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Process-local evidence of text successfully written by the app.
///
/// Only fingerprints are retained. It does not observe the clipboard or infer
/// writes performed by platform menus or keyboard shortcuts.
class SelfCopyFingerprintRegistry {
  SelfCopyFingerprintRegistry({this.capacity = 20}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive');
    }
  }

  final int capacity;
  final LinkedHashSet<String> _fingerprints = LinkedHashSet<String>();

  int get length => _fingerprints.length;

  bool containsText(String text) => _fingerprints.contains(_fingerprint(text));

  /// The writer calls this only after its platform write has completed.
  void recordSuccessfulWrite(String text) {
    final fingerprint = _fingerprint(text);
    _fingerprints
      ..remove(fingerprint)
      ..add(fingerprint);
    if (_fingerprints.length > capacity) {
      _fingerprints.remove(_fingerprints.first);
    }
  }

  static String _fingerprint(String text) =>
      sha256.convert(utf8.encode(text)).toString();
}
