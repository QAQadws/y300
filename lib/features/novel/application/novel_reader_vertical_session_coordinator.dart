final class NovelReaderVerticalSessionToken {
  NovelReaderVerticalSessionToken._(this.surfaceIdentity, this.episodeId);

  final String surfaceIdentity;
  final String episodeId;

  String get owner => '$surfaceIdentity|vertical-restore';
}

final class NovelReaderVerticalRestoreRequest {
  NovelReaderVerticalRestoreRequest._(this.session);

  final NovelReaderVerticalSessionToken session;
}

final class NovelReaderVerticalFrameRequest {
  NovelReaderVerticalFrameRequest._(this.session);

  final NovelReaderVerticalSessionToken session;
}

final class NovelReaderVerticalThemeRequest {
  NovelReaderVerticalThemeRequest._(this.session, this.signature);

  final NovelReaderVerticalSessionToken session;
  final String signature;
}

final class NovelReaderChapterTransitionRequest {
  NovelReaderChapterTransitionRequest._({
    required this.surfaceIdentity,
    required this.episodeId,
    required this.contentWasReady,
    required this.visibleOffset,
  });

  final String surfaceIdentity;
  final String episodeId;
  final bool contentWasReady;
  final double? visibleOffset;
}

class NovelReaderVerticalSessionCoordinator {
  NovelReaderVerticalSessionToken? _session;
  NovelReaderVerticalRestoreRequest? _restore;
  NovelReaderVerticalFrameRequest? _scheduled;
  NovelReaderVerticalThemeRequest? _theme;
  NovelReaderChapterTransitionRequest? _chapterTransition;
  bool _contentReady = false;
  bool _terminalReady = false;
  bool _restored = false;
  bool _disposed = false;
  double? _themeRestoreOffset;
  double? _restoreOffsetOverride;
  _SuspendedVerticalSurface? _suspended;

  NovelReaderVerticalSessionToken? get session => _session;
  bool get contentReady => _contentReady;
  bool get terminalReady => _terminalReady;
  bool get hasRestoredOffset => _restored;
  bool get hasPendingThemeRestore => _themeRestoreOffset != null;
  double? get restoreOffsetOverride => _restoreOffsetOverride;

  NovelReaderVerticalSessionToken bind({
    required String surfaceIdentity,
    required String episodeId,
    bool isTransitioning = false,
  }) {
    if (isTransitioning) {
      return _suspended?.session ??
          NovelReaderVerticalSessionToken._(surfaceIdentity, episodeId);
    }
    final current = _session;
    if (current != null &&
        current.surfaceIdentity == surfaceIdentity &&
        current.episodeId == episodeId) {
      return current;
    }
    final suspended = _suspended;
    retireSurface();
    final next = _session = NovelReaderVerticalSessionToken._(
      surfaceIdentity,
      episodeId,
    );
    if (suspended?.session.surfaceIdentity == surfaceIdentity &&
        suspended?.session.episodeId == episodeId) {
      _contentReady = suspended!.contentReady;
      _terminalReady = suspended.terminalReady;
      _restoreOffsetOverride = suspended.visibleOffset;
    }
    return next;
  }

  bool isCurrent(NovelReaderVerticalSessionToken session) =>
      !_disposed && identical(_session, session);

  void retireSurface() {
    _session = null;
    _restore = null;
    _scheduled = null;
    _theme = null;
    _contentReady = false;
    _terminalReady = false;
    _restored = false;
    _themeRestoreOffset = null;
    _restoreOffsetOverride = null;
    _suspended = null;
  }

  void suspendForChapterTransition({double? visibleOffset}) {
    final current = _session;
    if (current == null) return;
    final suspended = _SuspendedVerticalSurface(
      current,
      _contentReady,
      _terminalReady,
      visibleOffset,
    );
    retireSurface();
    _suspended = suspended;
  }

  void observeSurface(String surfaceIdentity) {
    final suspended = _suspended;
    if (suspended != null &&
        suspended.session.surfaceIdentity != surfaceIdentity) {
      // The HTML may still be mounted before the next frame, but a new open
      // owns its position even if it returns to that same physical document.
      _suspended = _SuspendedVerticalSurface(
        suspended.session,
        suspended.contentReady,
        suspended.terminalReady,
        null,
        acceptsReadyUpdates: false,
      );
    }
  }

  void retire({bool preserveContentProof = false}) {
    final current = _session;
    final proof = preserveContentProof
        ? current == null
              ? _suspended
              : _SuspendedVerticalSurface(
                  current,
                  _contentReady,
                  _terminalReady,
                  null,
                )
        : null;
    retireSurface();
    _chapterTransition = null;
    if (proof != null && (proof.contentReady || proof.terminalReady)) {
      // Keep only confirmed physical content readiness, never old position or
      // request authority. A rendered loading branch discards this proof too.
      _suspended = _SuspendedVerticalSurface(
        proof.session,
        proof.contentReady,
        proof.terminalReady,
        null,
        acceptsReadyUpdates: false,
      );
    }
  }

  void dispose() {
    _disposed = true;
    retire();
  }

  bool markContentReady(NovelReaderVerticalSessionToken session) {
    if (!isCurrent(session)) return false;
    _contentReady = true;
    return true;
  }

  bool markContentTerminal(NovelReaderVerticalSessionToken session) {
    if (!isCurrent(session)) return false;
    _terminalReady = true;
    return true;
  }

  void markSuspendedContent(
    NovelReaderVerticalSessionToken session, {
    bool terminal = false,
  }) {
    final suspended = _suspended;
    if (_disposed ||
        suspended == null ||
        !suspended.acceptsReadyUpdates ||
        !identical(suspended.session, session)) {
      return;
    }
    _suspended = _SuspendedVerticalSurface(
      session,
      suspended.contentReady || !terminal,
      suspended.terminalReady || terminal,
      suspended.visibleOffset,
    );
  }

  bool claimPosition(NovelReaderVerticalSessionToken session) {
    if (!isCurrent(session)) return false;
    _restore = null;
    _scheduled = null;
    _restored = true;
    _restoreOffsetOverride = null;
    return true;
  }

  bool hasScheduledRestore(NovelReaderVerticalSessionToken session) =>
      isCurrent(session) && identical(_scheduled?.session, session);

  NovelReaderVerticalFrameRequest? scheduleRestore(
    NovelReaderVerticalSessionToken session,
  ) {
    if (!isCurrent(session) ||
        !_contentReady ||
        _restored ||
        _restore != null ||
        _scheduled != null) {
      return null;
    }
    return _scheduled = NovelReaderVerticalFrameRequest._(session);
  }

  bool takeScheduledRestore(NovelReaderVerticalFrameRequest request) {
    if (!isCurrent(request.session) || !identical(_scheduled, request)) {
      return false;
    }
    _scheduled = null;
    return true;
  }

  void clearScheduledRestore(NovelReaderVerticalSessionToken session) {
    if (isCurrent(session)) _scheduled = null;
  }

  NovelReaderVerticalRestoreRequest? beginRestore(
    NovelReaderVerticalSessionToken session,
  ) {
    if (!isCurrent(session) ||
        !_contentReady ||
        _restored ||
        _restore != null) {
      return null;
    }
    _scheduled = null;
    return _restore = NovelReaderVerticalRestoreRequest._(session);
  }

  bool ownsRestore(NovelReaderVerticalRestoreRequest request) =>
      isCurrent(request.session) && identical(_restore, request);

  bool finishRestore(
    NovelReaderVerticalRestoreRequest request, {
    required bool applied,
  }) {
    if (!ownsRestore(request)) return false;
    _restore = null;
    if (!applied) return false;
    _restored = true;
    _restoreOffsetOverride = null;
    return true;
  }

  NovelReaderVerticalThemeRequest trackTheme(
    NovelReaderVerticalSessionToken session,
    String signature, {
    double? visibleOffset,
  }) {
    final current = _theme;
    if (isCurrent(session) &&
        identical(current?.session, session) &&
        current?.signature == signature) {
      return current!;
    }
    if (isCurrent(session)) {
      if (current != null && _restored) _themeRestoreOffset ??= visibleOffset;
      return _theme = NovelReaderVerticalThemeRequest._(session, signature);
    }
    return NovelReaderVerticalThemeRequest._(session, signature);
  }

  bool ownsTheme(NovelReaderVerticalThemeRequest request) =>
      isCurrent(request.session) && identical(_theme, request);

  double? themeRestoreOffset(NovelReaderVerticalThemeRequest request) =>
      ownsTheme(request) ? _themeRestoreOffset : null;

  void clearThemeRestore(NovelReaderVerticalThemeRequest request) {
    if (ownsTheme(request)) _themeRestoreOffset = null;
  }

  NovelReaderChapterTransitionRequest beginChapterTransition({
    required String surfaceIdentity,
    required String episodeId,
    double? visibleOffset,
  }) => _chapterTransition = NovelReaderChapterTransitionRequest._(
    surfaceIdentity: surfaceIdentity,
    episodeId: episodeId,
    contentWasReady: _contentReady,
    visibleOffset: visibleOffset,
  );

  bool ownsChapterTransition(NovelReaderChapterTransitionRequest request) =>
      !_disposed && identical(_chapterTransition, request);

  NovelReaderVerticalSessionToken? recoverChapterTransition(
    NovelReaderChapterTransitionRequest request,
  ) {
    if (!ownsChapterTransition(request)) return null;
    final current = bind(
      surfaceIdentity: request.surfaceIdentity,
      episodeId: request.episodeId,
    );
    _contentReady = _contentReady || request.contentWasReady;
    if (!_restored) _restoreOffsetOverride ??= request.visibleOffset;
    return current;
  }

  void finishChapterTransition(NovelReaderChapterTransitionRequest request) {
    if (ownsChapterTransition(request)) _chapterTransition = null;
  }
}

final class _SuspendedVerticalSurface {
  const _SuspendedVerticalSurface(
    this.session,
    this.contentReady,
    this.terminalReady,
    this.visibleOffset, {
    this.acceptsReadyUpdates = true,
  });

  final NovelReaderVerticalSessionToken session;
  final bool contentReady;
  final bool terminalReady;
  final double? visibleOffset;
  final bool acceptsReadyUpdates;
}
