typedef _ImageIdentity = ({int imageIndex, String imageUrl});

/// Owns retry policy and request lifetime only. The reader controller validates
/// visible content and applies state; the existing reader service owns the probe.
final class ComicReaderImageRecoveryCoordinator {
  ComicReaderImageRecoveryCoordinator({
    required Future<void> Function(String sourceTid) probeEpisode,
  }) : _probeEpisode = probeEpisode;

  final Future<void> Function(String sourceTid) _probeEpisode;
  ComicReaderImageRecoverySession? _session;
  Future<void>? _probe;
  final _automaticRetries = <_ImageIdentity, ComicReaderAutomaticImageRetry>{};
  final _manualRetries = <_ImageIdentity>{};
  bool _closed = false;

  ComicReaderImageRecoverySession activate({
    required String episodeId,
    required String sourceTid,
    required int generation,
  }) {
    if (_closed) {
      throw StateError('The comic image recovery session is closed.');
    }
    final current = _session;
    if (current != null &&
        current.episodeId == episodeId &&
        current.sourceTid == sourceTid &&
        current.generation == generation) {
      return current;
    }
    retire();
    return _session = ComicReaderImageRecoverySession._(
      episodeId,
      sourceTid,
      generation,
    );
  }

  bool isCurrent(ComicReaderImageRecoverySession session) =>
      !_closed && identical(_session, session);

  /// Image identity is omitted for the legacy chapter-only retry entry point.
  Future<void> prepareManualRetry({
    required ComicReaderImageRecoverySession session,
    int? imageIndex,
    String? imageUrl,
  }) {
    if (!isCurrent(session)) return Future.value();
    if (imageIndex != null && imageUrl != null) {
      _manualRetries.add((imageIndex: imageIndex, imageUrl: imageUrl));
    }
    return _probeFor(session);
  }

  ComicReaderAutomaticImageRetry? startAutomaticRetry({
    required ComicReaderImageRecoverySession session,
    required int imageIndex,
    required String imageUrl,
  }) {
    if (!isCurrent(session)) return null;
    final image = (imageIndex: imageIndex, imageUrl: imageUrl);
    if (_automaticRetries.containsKey(image)) return null;
    final retry = ComicReaderAutomaticImageRetry._(
      this,
      session,
      image,
      _probeFor(session),
    );
    _automaticRetries[image] = retry;
    return retry;
  }

  void imageResolved({
    required ComicReaderImageRecoverySession session,
    required int imageIndex,
    required String imageUrl,
  }) {
    if (!isCurrent(session)) return;
    final image = (imageIndex: imageIndex, imageUrl: imageUrl);
    _automaticRetries.remove(image);
    _manualRetries.remove(image);
  }

  Future<void> _probeFor(ComicReaderImageRecoverySession session) {
    final existing = _probe;
    if (existing != null) return existing;
    late final Future<void> probe;
    probe = _runProbe(session.sourceTid).whenComplete(() {
      // Retired I/O may still finish after a new session starts another probe.
      if (identical(_probe, probe)) _probe = null;
    });
    _probe = probe;
    return probe;
  }

  Future<void> _runProbe(String sourceTid) async {
    try {
      await _probeEpisode(sourceTid);
    } catch (_) {
      // WAF recovery may succeed even when parsing fails; keep direct image
      // retry available. Probe results never replace the image directory.
    }
  }

  bool _canRetry(ComicReaderAutomaticImageRetry retry) =>
      isCurrent(retry.session) &&
      identical(_automaticRetries[retry._image], retry) &&
      !_manualRetries.contains(retry._image);

  void retire() {
    _session = null;
    _probe = null;
    _automaticRetries.clear();
    _manualRetries.clear();
  }

  void close() {
    retire();
    _closed = true;
  }
}

final class ComicReaderImageRecoverySession {
  const ComicReaderImageRecoverySession._(
    this.episodeId,
    this.sourceTid,
    this.generation,
  );
  final String episodeId;
  final String sourceTid;
  final int generation;
}

/// A single automatic retry permission, checked again when the controller is
/// ready to publish its failed image state, not merely when the probe finishes.
final class ComicReaderAutomaticImageRetry {
  ComicReaderAutomaticImageRetry._(
    this._owner,
    this.session,
    this._image,
    Future<void> probe,
  ) {
    ready = probe.then((_) {
      _ready = true;
    });
  }

  final ComicReaderImageRecoveryCoordinator _owner;
  final ComicReaderImageRecoverySession session;
  final _ImageIdentity _image;
  late final Future<void> ready;
  bool _ready = false;
  bool _claimed = false;

  int get imageIndex => _image.imageIndex;
  String get imageUrl => _image.imageUrl;

  bool claimRetry() {
    if (!_ready || _claimed || !_owner._canRetry(this)) return false;
    _claimed = true;
    return true;
  }
}
