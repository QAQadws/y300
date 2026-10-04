import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_render_environment.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

class NovelReaderPaginationMeasureRequest {
  const NovelReaderPaginationMeasureRequest({
    required this.html,
    required this.chapter,
    required this.key,
    this.atomId,
    this.startOffset,
    this.endOffset,
  });

  final String html;
  final NovelReaderPreparedChapter chapter;
  final NovelReaderPaginationKey key;
  final String? atomId;
  final int? startOffset;
  final int? endOffset;
}

class NovelReaderPaginationMeasureResult {
  const NovelReaderPaginationMeasureResult({
    required this.height,
    this.fromCache = false,
    this.frameWaitCount = 0,
  });

  final double height;
  final bool fromCache;
  final int frameWaitCount;

  NovelReaderPaginationMeasureResult copyWith({
    bool? fromCache,
    int? frameWaitCount,
  }) {
    return NovelReaderPaginationMeasureResult(
      height: height,
      fromCache: fromCache ?? this.fromCache,
      frameWaitCount: frameWaitCount ?? this.frameWaitCount,
    );
  }
}

abstract interface class NovelReaderPaginationMeasureAdapter {
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  );
}

abstract interface class NovelReaderPaginationMeasureSession {
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  );

  Future<void> dispose();
}

abstract interface class NovelReaderPaginationMeasureSessionFactory {
  NovelReaderPaginationMeasureSession create({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  });
}

/// Creates a session for adapters that only expose the original one-shot API.
///
/// This keeps deterministic test adapters and non-widget callers compatible
/// while the real HTML adapter uses a persistent probe host.
final class NovelReaderAdapterMeasureSessionFactory
    implements NovelReaderPaginationMeasureSessionFactory {
  const NovelReaderAdapterMeasureSessionFactory(this.adapter);

  final NovelReaderPaginationMeasureAdapter adapter;

  @override
  NovelReaderPaginationMeasureSession create({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    return _DirectPaginationMeasureSession(adapter);
  }
}

/// A bounded LRU cache for exact candidate measurements.
///
/// The candidate HTML is part of the key on purpose. Atom and range metadata
/// makes diagnostics useful, while the exact HTML prevents an unsafe cache hit
/// when two ranges happen to share offsets but produce different wrappers.
final class NovelReaderPaginationMeasureCache {
  NovelReaderPaginationMeasureCache({
    this.capacity = 512,
    this.maxEstimatedBytes = 4 * 1024 * 1024,
  }) : assert(capacity > 0),
       assert(maxEstimatedBytes >= 0);

  final int capacity;
  final int maxEstimatedBytes;
  final LinkedHashMap<
    _MeasureCacheKey,
    ({NovelReaderPaginationMeasureResult result, int bytes})
  >
  _entries =
      LinkedHashMap<
        _MeasureCacheKey,
        ({NovelReaderPaginationMeasureResult result, int bytes})
      >();
  final Map<_MeasureCacheKey, Future<NovelReaderPaginationMeasureResult>>
  _inFlight = <_MeasureCacheKey, Future<NovelReaderPaginationMeasureResult>>{};
  int _generation = 0;
  int _estimatedRetainedBytes = 0;
  bool _closed = false;

  int get length => _entries.length;
  bool get isClosed => _closed;

  /// Fixed-weight estimate of retained keys/results, excluding in-flight work.
  /// This is not an actual heap-memory measurement.
  int get estimatedRetainedBytes => _estimatedRetainedBytes;

  NovelReaderPaginationMeasureResult? get(
    NovelReaderPaginationMeasureRequest request,
  ) {
    final key = _MeasureCacheKey.from(request);
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    _entries[key] = entry;
    return entry.result.copyWith(fromCache: true);
  }

  void put(
    NovelReaderPaginationMeasureRequest request,
    NovelReaderPaginationMeasureResult result,
  ) {
    if (_closed) {
      return;
    }
    final key = _MeasureCacheKey.from(request);
    _evict(key);
    final bytes =
        96 +
        2 *
            (key.layoutIdentity.length +
                key.episodeId.length +
                key.atomId.length +
                key.html.length);
    if (bytes > maxEstimatedBytes) {
      return;
    }
    _entries[key] = (result: result.copyWith(fromCache: false), bytes: bytes);
    _estimatedRetainedBytes += bytes;
    while (_entries.length > capacity ||
        _estimatedRetainedBytes > maxEstimatedBytes) {
      _evict(_entries.keys.first);
    }
  }

  Future<NovelReaderPaginationMeasureResult> resolve({
    required NovelReaderPaginationMeasureRequest request,
    required Future<NovelReaderPaginationMeasureResult> Function() measure,
  }) {
    if (_closed) {
      return Future<NovelReaderPaginationMeasureResult>.error(
        StateError('The measurement cache has been disposed.'),
      );
    }
    final cached = get(request);
    if (cached != null) {
      return Future<NovelReaderPaginationMeasureResult>.value(
        cached.copyWith(fromCache: true, frameWaitCount: 0),
      );
    }

    final key = _MeasureCacheKey.from(request);
    final existing = _inFlight[key];
    if (existing != null) {
      return existing.then(
        (result) => result.copyWith(fromCache: true, frameWaitCount: 0),
      );
    }

    final requestGeneration = _generation;
    final future = Future<NovelReaderPaginationMeasureResult>.sync(measure)
        .then((result) {
          if (!_closed && requestGeneration == _generation) {
            put(request, result);
          }
          return result;
        });
    _inFlight[key] = future;
    unawaited(
      future.then<void>(
        (_) => _removeInFlight(key, future),
        onError: (Object error, StackTrace stackTrace) =>
            _removeInFlight(key, future),
      ),
    );
    return future;
  }

  void clear() {
    _generation += 1;
    _entries.clear();
    _inFlight.clear();
    _estimatedRetainedBytes = 0;
  }

  void dispose() {
    _closed = true;
    clear();
  }

  void _evict(_MeasureCacheKey key) {
    final entry = _entries.remove(key);
    if (entry != null) {
      _estimatedRetainedBytes -= entry.bytes;
    }
  }

  void _removeInFlight(
    _MeasureCacheKey key,
    Future<NovelReaderPaginationMeasureResult> future,
  ) {
    if (identical(_inFlight[key], future)) {
      _inFlight.remove(key);
    }
  }
}

final class NovelReaderCachingPaginationMeasureSession
    implements NovelReaderPaginationMeasureSession {
  NovelReaderCachingPaginationMeasureSession({
    required NovelReaderPaginationMeasureSession delegate,
    NovelReaderPaginationMeasureCache? cache,
  }) : _delegate = delegate,
       cache = cache ?? NovelReaderPaginationMeasureCache();

  final NovelReaderPaginationMeasureSession _delegate;
  final NovelReaderPaginationMeasureCache cache;
  bool _disposed = false;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    if (_disposed) {
      return Future<NovelReaderPaginationMeasureResult>.error(
        const NovelReaderPaginationException(
          code: 'measurementSessionDisposed',
          message: 'The pagination measurement session has been disposed.',
        ),
      );
    }
    try {
      return await cache.resolve(
        request: request,
        measure: () => _delegate.measure(request),
      );
    } on NovelReaderPaginationException catch (error) {
      if (_disposed || error.code != 'measurementSessionDisposed') rethrow;
      // A shared in-flight metric may belong to another session that exited.
      // This still-active waiter can measure it once using its own host.
      return cache.resolve(
        request: request,
        measure: () => _delegate.measure(request),
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _delegate.dispose();
  }
}

final class NovelReaderHtmlPaginationMeasureAdapter
    implements
        NovelReaderPaginationMeasureAdapter,
        NovelReaderPaginationMeasureSessionFactory {
  NovelReaderHtmlPaginationMeasureAdapter({
    required BuildContext hostContext,
    required this.theme,
    required this.preferences,
    required this.sourceId,
    this.threadId,
    this.imageCacheOwnerId,
    this.imageReferer,
    this.blockSpacingMode = ForumHtmlBlockSpacingMode.paragraphLikeDivs,
    this.timeout = const Duration(milliseconds: 800),
    NovelReaderPaginationRenderEnvironment? renderEnvironment,
  }) : _hostContext = hostContext,
       renderEnvironment =
           renderEnvironment ??
           NovelReaderPaginationRenderEnvironment.capture(
             hostContext,
             textStyle: ForumHtmlStylePolicy(
               preferences,
               theme: theme,
               blockSpacingMode: blockSpacingMode,
             ).baseTextStyle(hostContext),
             textAlign: TextAlign.start,
           );

  final BuildContext _hostContext;
  final ForumHtmlThemeContext theme;
  final ForumHtmlReaderPreferences preferences;
  final String sourceId;
  final String? threadId;
  final String? imageCacheOwnerId;
  final String? imageReferer;
  final ForumHtmlBlockSpacingMode blockSpacingMode;
  final Duration timeout;
  final NovelReaderPaginationRenderEnvironment renderEnvironment;

  @override
  NovelReaderPaginationMeasureSession create({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    return _NovelReaderHtmlPaginationMeasureSession(
      hostContext: _hostContext,
      theme: theme,
      preferences: preferences,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
      imageReferer: imageReferer,
      blockSpacingMode: blockSpacingMode,
      chapter: chapter,
      key: key,
      timeout: timeout,
      renderEnvironment: renderEnvironment,
    );
  }

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    final session = create(chapter: request.chapter, key: request.key);
    try {
      return await session.measure(request);
    } finally {
      await session.dispose();
    }
  }
}

final class _DirectPaginationMeasureSession
    implements NovelReaderPaginationMeasureSession {
  const _DirectPaginationMeasureSession(this.adapter);

  final NovelReaderPaginationMeasureAdapter adapter;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) => adapter.measure(request);

  @override
  Future<void> dispose() async {}
}

final class _NovelReaderHtmlPaginationMeasureSession
    implements NovelReaderPaginationMeasureSession {
  _NovelReaderHtmlPaginationMeasureSession({
    required BuildContext hostContext,
    required this.theme,
    required this.preferences,
    required this.sourceId,
    required this.threadId,
    required this.imageCacheOwnerId,
    required this.imageReferer,
    required this.blockSpacingMode,
    required this.chapter,
    required this.key,
    required this.timeout,
    required this.renderEnvironment,
  }) : _hostContext = hostContext;

  final BuildContext _hostContext;
  final ForumHtmlThemeContext theme;
  final ForumHtmlReaderPreferences preferences;
  final String sourceId;
  final String? threadId;
  final String? imageCacheOwnerId;
  final String? imageReferer;
  final ForumHtmlBlockSpacingMode blockSpacingMode;
  final NovelReaderPreparedChapter chapter;
  final NovelReaderPaginationKey key;
  final Duration timeout;
  final NovelReaderPaginationRenderEnvironment renderEnvironment;
  final GlobalKey<_NovelReaderPaginationMeasureHostState> _hostKey =
      GlobalKey<_NovelReaderPaginationMeasureHostState>();

  OverlayEntry? _entry;
  Future<void> _tail = Future<void>.value();
  int _token = 0;
  int? _pendingToken;
  int _frameWaitCount = 0;
  int? _pendingStartFrameWaitCount;
  Completer<NovelReaderPaginationMeasureResult>? _pending;
  Timer? _pendingTimeout;
  bool _disposed = false;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) {
    final completer = Completer<NovelReaderPaginationMeasureResult>();
    final operation = _tail.then<void>((_) async {
      try {
        completer.complete(await _measureNow(request));
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    _tail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return completer.future;
  }

  Future<NovelReaderPaginationMeasureResult> _measureNow(
    NovelReaderPaginationMeasureRequest request,
  ) {
    if (_disposed) {
      throw const NovelReaderPaginationException(
        code: 'measurementSessionDisposed',
        message: 'The pagination measurement session has been disposed.',
      );
    }
    if (request.chapter.episodeId != chapter.episodeId || request.key != key) {
      throw const NovelReaderPaginationException(
        code: 'measurementSessionMismatch',
        message: 'The request does not belong to this measurement session.',
      );
    }

    final token = ++_token;
    final hadHost = _entry != null;
    _pendingToken = token;
    _pendingStartFrameWaitCount = _frameWaitCount;
    final completer = Completer<NovelReaderPaginationMeasureResult>();
    _pending = completer;
    final requestEnded = completer.future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    // The timer starts before the first frame wait, not only after mounting.
    _pendingTimeout = Timer(timeout, () {
      _completeError(
        token,
        const NovelReaderPaginationException(
          code: 'measurementTimeout',
          message: 'HTML renderer pagination measurement timed out.',
        ),
      );
    });
    unawaited(
      _submit(
        request: request,
        token: token,
        hadHost: hadHost,
        requestEnded: requestEnded,
      ).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            _completeError(token, error, stack),
      ),
    );
    // Return immediately so errors are observed even before endOfFrame arrives.
    return completer.future;
  }

  Future<void> _submit({
    required NovelReaderPaginationMeasureRequest request,
    required int token,
    required bool hadHost,
    required Future<void> requestEnded,
  }) async {
    await _ensureHost(
      request: request,
      token: token,
      requestEnded: requestEnded,
    );
    if (_isPending(token) && hadHost) {
      _hostKey.currentState?.submit(request: request, token: token);
    }
  }

  Future<void> _ensureHost({
    required NovelReaderPaginationMeasureRequest request,
    required int token,
    required Future<void> requestEnded,
  }) async {
    if (_entry != null) {
      return;
    }
    final overlay = Overlay.maybeOf(_hostContext, rootOverlay: true);
    if (overlay == null) {
      throw const NovelReaderPaginationException(
        code: 'measurementHostUnavailable',
        message: 'No overlay is available for HTML pagination measurement.',
      );
    }
    // The coordinator can be started while a FutureBuilder is building.
    _frameWaitCount += 1;
    await Future.any<void>([WidgetsBinding.instance.endOfFrame, requestEnded]);
    if (!_isPending(token)) return;
    if (!overlay.mounted || !_hostContext.mounted) {
      throw const NovelReaderPaginationException(
        code: 'measurementHostUnavailable',
        message: 'The HTML pagination measurement host is no longer mounted.',
      );
    }
    _entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 0,
          top: 0,
          width: request.key.viewportWidthPx.toDouble(),
          child: IgnorePointer(
            child: Opacity(
              opacity: 0,
              // A root overlay is outside the reader's Scaffold. Interactive
              // blocks still require a Material ancestor during measurement.
              child: Material(
                type: MaterialType.transparency,
                child: renderEnvironment.wrap(
                  _NovelReaderPaginationMeasureHost(
                    key: _hostKey,
                    initialRequest: request,
                    initialToken: token,
                    onMeasured: _completeHeight,
                    onFrameWaited: _recordFrameWait,
                    childBuilder: _buildCandidate,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
  }

  Widget _buildCandidate(NovelReaderPaginationMeasureRequest request) {
    final preparedDocument = request.chapter.renderDocument.copyWith(
      preparedHtml: request.html,
    );
    return ForumHtmlWidgetPostRenderer(
      html: request.html,
      theme: theme,
      preparedDocument: preparedDocument,
      preferences: preferences,
      textStyle: renderEnvironment.textStyle,
      textAlign: renderEnvironment.textAlign,
      sourceId: sourceId,
      threadId: threadId,
      imageReferer: imageReferer,
      imageCacheOwnerId: imageCacheOwnerId,
      buildAsync: false,
      enableCaching: false,
      blockSpacingMode: blockSpacingMode,
    );
  }

  void _completeHeight(int token, double height) {
    if (!_isPending(token)) return;
    final completer = _pending!;
    _pending = null;
    _pendingToken = null;
    _pendingTimeout?.cancel();
    _pendingTimeout = null;
    completer.complete(
      NovelReaderPaginationMeasureResult(
        height: height,
        frameWaitCount:
            _frameWaitCount - (_pendingStartFrameWaitCount ?? _frameWaitCount),
      ),
    );
    _pendingStartFrameWaitCount = null;
  }

  void _completeError(int token, Object error, [StackTrace? stack]) {
    if (_pendingToken != token || _pending == null || _pending!.isCompleted) {
      return;
    }
    final completer = _pending!;
    _pending = null;
    _pendingToken = null;
    _pendingStartFrameWaitCount = null;
    _pendingTimeout?.cancel();
    _pendingTimeout = null;
    _removeHost();
    completer.completeError(error, stack);
  }

  bool _isPending(int token) =>
      !_disposed &&
      _pendingToken == token &&
      _pending != null &&
      !_pending!.isCompleted;

  void _recordFrameWait(int token) {
    if (_isPending(token)) _frameWaitCount += 1;
  }

  void _removeHost() {
    final entry = _entry;
    _entry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      _completeError(
        _pendingToken ?? -1,
        const NovelReaderPaginationException(
          code: 'measurementSessionDisposed',
          message: 'The pagination measurement session has been disposed.',
        ),
      );
    }
    _pendingTimeout?.cancel();
    _pendingTimeout = null;
    _removeHost();
  }
}

class _NovelReaderPaginationMeasureHost extends StatefulWidget {
  const _NovelReaderPaginationMeasureHost({
    super.key,
    required this.initialRequest,
    required this.initialToken,
    required this.onMeasured,
    required this.onFrameWaited,
    required this.childBuilder,
  });

  final NovelReaderPaginationMeasureRequest initialRequest;
  final int initialToken;
  final void Function(int token, double height) onMeasured;
  final void Function(int token) onFrameWaited;
  final Widget Function(NovelReaderPaginationMeasureRequest request)
  childBuilder;

  @override
  State<_NovelReaderPaginationMeasureHost> createState() =>
      _NovelReaderPaginationMeasureHostState();
}

class _NovelReaderPaginationMeasureHostState
    extends State<_NovelReaderPaginationMeasureHost> {
  late NovelReaderPaginationMeasureRequest _request = widget.initialRequest;
  late int _token = widget.initialToken;

  void submit({
    required NovelReaderPaginationMeasureRequest request,
    required int token,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _request = request;
      _token = token;
    });
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;
    return _NovelReaderPaginationMeasureProbe(
      key: ValueKey<int>(token),
      onMeasured: (height) => widget.onMeasured(token, height),
      onFrameWaited: () => widget.onFrameWaited(token),
      child: widget.childBuilder(_request),
    );
  }
}

class _NovelReaderPaginationMeasureProbe extends StatefulWidget {
  const _NovelReaderPaginationMeasureProbe({
    super.key,
    required this.onMeasured,
    required this.onFrameWaited,
    required this.child,
  });

  final ValueChanged<double> onMeasured;
  final VoidCallback onFrameWaited;
  final Widget child;

  @override
  State<_NovelReaderPaginationMeasureProbe> createState() =>
      _NovelReaderPaginationMeasureProbeState();
}

class _NovelReaderPaginationMeasureProbeState
    extends State<_NovelReaderPaginationMeasureProbe> {
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onFrameWaited();
      _reportSize();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _reportSize() {
    if (!mounted || _reported) {
      return;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onFrameWaited();
        _reportSize();
      });
      return;
    }
    _reported = true;
    widget.onMeasured(renderObject.size.height);
  }
}

final class _MeasureCacheKey {
  const _MeasureCacheKey({
    required this.layoutIdentity,
    required this.episodeId,
    required this.atomId,
    required this.startOffset,
    required this.endOffset,
    required this.html,
  });

  factory _MeasureCacheKey.from(NovelReaderPaginationMeasureRequest request) {
    return _MeasureCacheKey(
      layoutIdentity: request.key.cacheIdentity,
      episodeId: request.chapter.episodeId,
      atomId: request.atomId ?? '',
      startOffset: request.startOffset ?? -1,
      endOffset: request.endOffset ?? -1,
      html: request.html,
    );
  }

  final String layoutIdentity;
  final String episodeId;
  final String atomId;
  final int startOffset;
  final int endOffset;
  final String html;

  @override
  bool operator ==(Object other) {
    return other is _MeasureCacheKey &&
        other.layoutIdentity == layoutIdentity &&
        other.episodeId == episodeId &&
        other.atomId == atomId &&
        other.startOffset == startOffset &&
        other.endOffset == endOffset &&
        other.html == html;
  }

  @override
  int get hashCode => Object.hash(
    layoutIdentity,
    episodeId,
    atomId,
    startOffset,
    endOffset,
    html,
  );
}

class NovelReaderPaginationException implements Exception {
  const NovelReaderPaginationException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'NovelReaderPaginationException($code): $message';
}
