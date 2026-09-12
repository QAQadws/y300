import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Opt in with --dart-define=Y300_COVER_TRACE=true; never emits in release.
class LibraryCoverLoadTrace {
  LibraryCoverLoadTrace(this.fingerprint, this.width, this.height)
    : _watch = enabled ? (Stopwatch()..start()) : null;

  static const enabled =
      !kReleaseMode && bool.fromEnvironment('Y300_COVER_TRACE');
  final String fingerprint;
  final int? width;
  final int? height;
  final Stopwatch? _watch;

  void mark(String stage, {int? bytes, int? active, int? pending}) {
    if (!enabled) return;
    developer.Timeline.instantSync(
      'LibraryCover.$stage',
      arguments: <String, Object>{
        'keyHash': fingerprint,
        'width': ?width,
        'height': ?height,
        'elapsedUs': _watch!.elapsedMicroseconds,
        'bytes': ?bytes,
        'active': ?active,
        'pending': ?pending,
      },
    );
  }
}
