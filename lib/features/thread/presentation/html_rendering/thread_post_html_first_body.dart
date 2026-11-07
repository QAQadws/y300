import 'package:flutter/material.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_html_image_reader_bridge.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';
import 'package:y300/features/thread/presentation/services/thread_body_reading_coordinator.dart';
import 'package:y300/features/thread/presentation/services/thread_body_reading_image_host.dart';
import 'package:y300/features/thread/presentation/services/thread_body_presentation.dart';

typedef ThreadPostHtmlFirstImageFallback = void Function(
  ThreadPost post,
  ForumHtmlImageRequest request,
);

typedef ThreadPreparedBodyHandoff = bool Function(
  BuildContext context,
  ForumHtmlPreparationRequest request,
  ForumHtmlPreparedRenderDocument document,
);
typedef ThreadPreparedBodyPreparerSelector = ForumHtmlRenderPreparer Function(
  ForumHtmlPreparationRequest request,
);
typedef ThreadPostHtmlFirstImageDiagnostics = void Function(
  ThreadPost post,
  ForumHtmlImageRequest request,
  ThreadHtmlImageReaderBridgeResult result,
);

class ThreadPostHtmlFirstBody extends ConsumerStatefulWidget {
  const ThreadPostHtmlFirstBody({
    super.key,
    required this.post,
    this.sourcePost,
    required this.threadId,
    required this.imageReferer,
    required this.onOpenPostLink,
    this.onOpenSelectedPostLink,
    required this.onOpenPostImage,
    required this.theme,
    this.onImageFallback,
    this.onImageDiagnostics,
    this.onImageLayoutShift,
    this.imageFallbackAspectRatioFor,
    this.onBlockImageResolved,
    this.imageViewportCoordinator,
    this.imageAnchorController,
    this.readingCoordinator,
    this.bodyPresentation,
    this.wholeBodyPresentation,
    this.imagePrecacheService,
    this.fallback,
    this.renderPreparer = const DefaultForumHtmlRenderPreparer(),
    this.preparationExecutor,
    this.onPreparedBody,
    this.preparerSelector,
    this.imageReaderBridge = const ThreadHtmlImageReaderBridge(),
    this.nativeBody = false,
    this.selectEntireBody = false,
    this.isSelectionCurrent,
  });

  final ThreadPost post;
  final ThreadPost? sourcePost;
  final String threadId;
  final String imageReferer;
  final ValueChanged<String> onOpenPostLink;
  final ForumSelectionLinkOpener? onOpenSelectedPostLink;
  final void Function(ThreadPost post, ThreadImageOpenRequest request)?
  onOpenPostImage;
  final ForumHtmlThemeContext theme;
  final ThreadPostHtmlFirstImageFallback? onImageFallback;
  final ThreadPostHtmlFirstImageDiagnostics? onImageDiagnostics;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final double? Function(ForumImageLoadSpec spec, ImageCacheRequest request)?
  imageFallbackAspectRatioFor;
  final void Function(
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )?
  onBlockImageResolved;
  final ForumHtmlImageViewportCoordinator? imageViewportCoordinator;
  final ForumHtmlImageAnchorController? imageAnchorController;
  final ThreadBodyReadingCoordinator? readingCoordinator;
  final ForumHtmlBodyPresentation? bodyPresentation;
  final ThreadBodyPresentation? wholeBodyPresentation;
  final ForumImagePrecacheService? imagePrecacheService;
  final Widget? fallback;
  final ForumHtmlRenderPreparer renderPreparer;
  final ForumHtmlPreparationExecutor? preparationExecutor;
  final ThreadPreparedBodyHandoff? onPreparedBody;
  final ThreadPreparedBodyPreparerSelector? preparerSelector;
  final ThreadHtmlImageReaderBridge imageReaderBridge;
  final bool nativeBody;
  final bool selectEntireBody;
  final bool Function()? isSelectionCurrent;

  @override
  ConsumerState<ThreadPostHtmlFirstBody> createState() =>
      _ThreadPostHtmlFirstBodyState();
}

class _ThreadPostHtmlFirstBodyState
    extends ConsumerState<ThreadPostHtmlFirstBody> {
  ForumHtmlComparisonBodyBuilder? _comparisonBuilder;
  bool get _nativeBody => widget.nativeBody || _comparisonBuilder == null;
  bool _loggedEmptyBody = false;
  String? _lastPreparedLogKey;
  String? _lastRenderFailureLogKey;
  late var _preparation = _createPreparation();

  ForumHtmlPreparationController _createPreparation() =>
      ForumHtmlPreparationController(executor: widget.preparationExecutor)
        ..addListener(_onPreparationChanged);
  final _readingKey = GlobalKey();
  final _readingExpansion = <String, bool>{};
  ThreadBodyReadingImageTracker? _readingImages;
  ForumHtmlImageHost? _readingImageHost;
  Object? _readingIdentity;
  bool _readingReady = false;
  bool _nativeBoundaryKnown = false;
  int _readingRevision = 0;
  final _bodyLayoutConsumer = Object();
  ThreadBodyLayoutLease? _bodyLayoutLease;
  ThreadBodyLayoutPhase _bodyLayoutPhase = ThreadBodyLayoutPhase.preparing;
  ForumHtmlBodyLayoutPhase _nativeLayoutPhase =
      ForumHtmlBodyLayoutPhase.preparing;

  void _onPreparationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ThreadPostHtmlFirstBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preparationExecutor != widget.preparationExecutor) {
      _preparation.dispose();
      _preparation = _createPreparation();
    }
    if (_preparation.hasError) _preparation.reset();
    if (!identical(oldWidget.readingCoordinator, widget.readingCoordinator)) {
      oldWidget.readingCoordinator?.unregister(this);
      _clearReading();
    }
    if (!identical(
          oldWidget.wholeBodyPresentation,
          widget.wholeBodyPresentation,
        ) ||
        widget.readingCoordinator != null) {
      _releaseBodyLayout();
    }
  }

  void _releaseBodyLayout() {
    _bodyLayoutLease?.release();
    _bodyLayoutLease = null;
    _bodyLayoutPhase = ThreadBodyLayoutPhase.preparing;
  }

  void _clearReading({bool preserveExpansion = false}) {
    _readingReady = false;
    _nativeBoundaryKnown = false;
    _readingIdentity = null;
    _readingImageHost = null;
    _readingImages?.dispose();
    _readingImages = null;
    if (!preserveExpansion) _readingExpansion.clear();
    _readingRevision++;
  }

  @override
  void dispose() {
    _releaseBodyLayout();
    widget.readingCoordinator?.unregister(this);
    _readingImages?.dispose();
    _preparation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _comparisonBuilder = widget.nativeBody
        ? null
        : ref.watch(forumHtmlComparisonBodyBuilderProvider);
    final html = widget.post.message.trim();
    final sourcePost = widget.sourcePost ?? widget.post;
    if (html.isEmpty) {
      _releaseBodyLayout();
      _preparation.reset();
      widget.readingCoordinator?.unregister(this);
      _clearReading();
      if (!_loggedEmptyBody) {
        _loggedEmptyBody = true;
        _logNative(
          'render_empty_body',
          'tid=${widget.threadId} pid=${sourcePost.pid} '
              'postNo=${sourcePost.number} authorId=${sourcePost.authorId}',
        );
      }
      return widget.fallback ?? const SizedBox.shrink();
    }
    final fontBinding = ref.watch(forumHtmlReaderFontBindingProvider);
    final preferences = fontBinding.preferences;
    final textStyle = resolveForumHtmlReaderTextStyle(
      context,
      preferences: preferences,
      theme: widget.theme,
      font: fontBinding.resolvedFont,
    );
    final retained = widget.bodyPresentation;
    if (_nativeBody && retained != null && retained.isActive) {
      _releaseBodyLayout();
      if (!fontBinding.isReady) {
        widget.readingCoordinator?.unregister(this);
        _clearReading();
      }
      return _buildRetainedNativeBody(
        html,
        preferences,
        textStyle: textStyle,
        fontIdentity: fontBinding.cacheKey,
        fontReady: fontBinding.isReady,
        presentation: retained,
      );
    }
    if (!fontBinding.isReady) {
      _releaseBodyLayout();
      widget.readingCoordinator?.unregister(this);
      _clearReading();
      // Font resolution blocks publication, not font-neutral HTML work. A
      // later preference snapshot still retires preparation through identity.
      return _buildHtmlBody(
        html,
        preferences,
        textStyle: textStyle,
        fontIdentity: fontBinding.cacheKey,
        fontReady: false,
      );
    }
    // B-class conversion is owned by the page-level display projector. This
    // boundary only prepares and renders the already projected HTML.
    final presentation = widget.wholeBodyPresentation;
    if (widget.readingCoordinator != null ||
        presentation == null ||
        !presentation.isActive ||
        presentation.html != widget.post.message) {
      _releaseBodyLayout();
      return _buildHtmlBody(
        html,
        preferences,
        textStyle: textStyle,
        fontIdentity: fontBinding.cacheKey,
      );
    }
    late ForumHtmlPreparationRequest request;
    try {
      request = _requestForBody(html, preferences);
    } catch (error, stackTrace) {
      _releaseBodyLayout();
      _logRenderFailure(
        htmlLength: html.length,
        error: error,
        stackTrace: stackTrace,
      );
      return widget.fallback ?? const ThreadPostHtmlBodyError();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final lease = presentation.bind(
          consumer: _bodyLayoutConsumer,
          layoutIdentity: (
            request.identity,
            preferences.renderOptions,
            fontBinding.cacheKey,
            textStyle,
            Theme.of(context),
            DefaultTextStyle.of(context).style,
            constraints.maxWidth,
            MediaQuery.textScalerOf(context),
            Directionality.of(context),
            Localizations.localeOf(context),
          ),
        );
        if (!identical(_bodyLayoutLease, lease)) {
          _bodyLayoutLease = lease;
          _bodyLayoutPhase = ThreadBodyLayoutPhase.preparing;
        }
        return ThreadBodyWaitingLayout(
          lease: lease,
          phase: () => _bodyLayoutPhase,
          child: _buildHtmlBody(
            html,
            preferences,
            textStyle: textStyle,
            fontIdentity: fontBinding.cacheKey,
            bodyLayout: lease,
            preparationRequest: request,
          ),
        );
      },
    );
  }

  Widget _buildRetainedNativeBody(
    String html,
    ForumHtmlReaderPreferences preferences, {
    required TextStyle textStyle,
    required Object fontIdentity,
    required bool fontReady,
    required ForumHtmlBodyPresentation presentation,
  }) {
    try {
      final request = _requestForBody(html, preferences);
      return ForumHtmlBodyLayout.observed(
        presentation: presentation,
        sourceId: request.sourceId,
        revision: (
          request.identity,
          preferences.renderOptions,
          fontIdentity,
          textStyle,
          MediaQuery.textScalerOf(context),
          Directionality.of(context),
          Localizations.localeOf(context),
        ),
        phase: () => _nativeLayoutPhase,
        child: _buildHtmlBody(
          html,
          preferences,
          textStyle: textStyle,
          fontIdentity: fontIdentity,
          fontReady: fontReady,
          preparationRequest: request,
        ),
      );
    } catch (error, stackTrace) {
      _logRenderFailure(
        htmlLength: html.length,
        error: error,
        stackTrace: stackTrace,
      );
      return widget.fallback ?? const ThreadPostHtmlBodyError();
    }
  }

  ForumHtmlPreparationRequest _requestForBody(
    String html,
    ForumHtmlReaderPreferences preferences,
  ) {
    final sourcePost = widget.sourcePost ?? widget.post;
    final sourceId = sourcePost.pid.trim().isEmpty
        ? 'post'
        : sourcePost.pid.trim();
    final baseRequest = ForumHtmlPreparationRequest(
      html: html,
      preferences: preferences,
      theme: widget.theme,
      sourceId: sourceId,
      threadId: widget.threadId,
      imageCacheOwnerId: widget.threadId,
      preparer: widget.renderPreparer,
    );
    final selected = widget.preparerSelector?.call(baseRequest);
    return selected == null || identical(selected, baseRequest.preparer)
        ? baseRequest
        : baseRequest.withPreparer(selected);
  }

  Widget _buildHtmlBody(
    String html,
    ForumHtmlReaderPreferences preferences, {
    required TextStyle textStyle,
    required Object fontIdentity,
    bool fontReady = true,
    ThreadBodyLayoutLease? bodyLayout,
    ForumHtmlPreparationRequest? preparationRequest,
  }) {
    final sourcePost = widget.sourcePost ?? widget.post;
    try {
      final sourceId = sourcePost.pid.trim().isEmpty
          ? 'post'
          : sourcePost.pid.trim();
      final request = preparationRequest ?? _requestForBody(html, preferences);
      final identity = request.identity;
      if (_preparation.identity != identity) {
        // Retire the previous reading handle before a new asynchronous wait.
        widget.readingCoordinator?.unregister(this);
        _clearReading();
      }
      final preparedDocument = _preparation.resolve(
        request,
        cache: _nativeBody ? widget.wholeBodyPresentation?.nativeCache : null,
      );
      if (preparedDocument == null || !fontReady) {
        _bodyLayoutPhase = ThreadBodyLayoutPhase.preparing;
        _nativeLayoutPhase = ForumHtmlBodyLayoutPhase.preparing;
        return const ForumHtmlPreparationPlaceholder();
      }
      if (widget.onPreparedBody?.call(context, request, preparedDocument) ==
          true) {
        _bodyLayoutPhase = ThreadBodyLayoutPhase.preparing;
        _nativeLayoutPhase = ForumHtmlBodyLayoutPhase.preparing;
        widget.readingCoordinator?.unregister(this);
        _clearReading();
        return const ForumHtmlPreparationPlaceholder();
      }
      final coordinator = widget.readingCoordinator;
      final tracked =
          coordinator?.tracks(widget.threadId, sourcePost.pid) == true;
      final readingIdentity = (
        identity,
        // Preparation reuse does not remove reading layout/ready invalidation.
        preferences.renderOptions,
        fontIdentity,
        textStyle,
        sourcePost.message,
        widget.imageReferer,
        widget.imagePrecacheService,
        _nativeBody,
        widget.bodyPresentation,
      );
      if ((tracked || _nativeBody) && _readingIdentity != readingIdentity) {
        // A font or image-host change retires layout readiness, while folds
        // still belong to the same prepared HTML document.
        _clearReading(preserveExpansion: true);
        _readingIdentity = readingIdentity;
        if (tracked) {
          _readingImages = ThreadBodyReadingImageTracker(coordinator!.schedule);
        }
        if (preparedDocument.sequence.entries.isNotEmpty ||
            (_nativeBody && preparedDocument.skippedStickerCount > 0)) {
          final delegate = ref
              .read(forumHtmlImageHostProvider)
              .forContent(
                threadId: widget.threadId,
                imageReferer: widget.imageReferer,
                imageCacheOwnerId: widget.threadId,
                fallbackAspectRatioFor: widget.imageFallbackAspectRatioFor,
                onBlockImageResolved: widget.onBlockImageResolved,
                imagePrecacheService: widget.imagePrecacheService,
              );
          _readingImageHost = tracked
              ? ThreadBodyReadingImageHost(
                  delegate: delegate,
                  tracker: _readingImages!,
                )
              : delegate;
        }
      }
      if (tracked) {
        coordinator!.register(
          ThreadBodyReadingHandle(
            owner: this,
            key: _readingKey,
            tid: widget.threadId,
            pid: sourcePost.pid,
            bodyIdentity: readingIdentity,
            htmlReady: () =>
                _readingReady && (!_nativeBody || _nativeBoundaryKnown),
            imagesReady: (viewport) =>
                _readingImages?.readyIn(viewport) ?? true,
            // This boundary measures the current rendered body. Closed folds
            // contribute their visible header, not their unmounted contents.
            finalBoundaryKnown: () => !_nativeBody || _nativeBoundaryKnown,
            layoutRevision: () => (
              _readingRevision,
              Object.hashAll(
                _readingExpansion.entries.map(
                  (entry) => (entry.key, entry.value),
                ),
              ),
            ),
          ),
        );
      }
      _logPreparedDocument(
        sourceId: sourceId,
        htmlLength: html.length,
        preparedDocument: preparedDocument,
      );
      final readingRevision = _readingRevision;
      final expansion = tracked
          ? _readingExpansion
          : (bodyLayout?.rendering ?? widget.bodyPresentation)
                ?.collapseExpansion;
      final callbacks = ForumHtmlRenderCallbacks(
        onInteraction: !tracked
            ? null
            : () {
                _readingRevision++;
                coordinator!.observer.cancelPendingCompletion();
                coordinator.schedule();
              },
        onTapUrl: (url) {
          widget.onOpenPostLink(url);
          return true;
        },
        onTapImage: _nativeBody
            ? null
            : (request) => _handleTapImage(preparedDocument.sequence, request),
        onImageLayoutShift: widget.onImageLayoutShift,
      );
      final body = KeyedSubtree(
        key: Key('thread-post-html-first-body-${sourcePost.pid}'),
        child: _nativeBody
            ? ForumNativeBodyFlow(
                key: widget.bodyPresentation == null
                    ? null
                    : ObjectKey(widget.bodyPresentation),
                prepared: preparedDocument,
                cache: widget.wholeBodyPresentation?.nativeCache,
                preferences: preferences,
                theme: widget.theme,
                textStyle: textStyle,
                fontRevision: fontIdentity.toString(),
                imageHost: _readingImageHost,
                imageAnchorController: widget.imageAnchorController,
                bodyPresentation:
                    bodyLayout?.rendering ?? widget.bodyPresentation,
                expansion: expansion ?? _readingExpansion,
                callbacks: callbacks,
                onOpenImage: _handleTapImage,
                clipboardTextWriter: ref.read(clipboardTextWriterProvider),
                onOpenSelectedLink: widget.onOpenSelectedPostLink,
                selectionEnabled: widget.selectEntireBody,
                selectEntireBody: widget.selectEntireBody,
                isSelectionCurrent: widget.isSelectionCurrent,
                errorBuilder: (_) =>
                    widget.fallback ?? const ThreadPostHtmlBodyError(),
                onLayoutPhase:
                    widget.bodyPresentation == null && bodyLayout == null
                    ? null
                    : (phase) {
                        _nativeLayoutPhase = phase;
                        if (bodyLayout?.isCurrent == true &&
                            identical(_bodyLayoutLease, bodyLayout)) {
                          // The inner flow reports during layout, before the
                          // waiting box records this frame's completed height.
                          _bodyLayoutPhase = switch (phase) {
                            ForumHtmlBodyLayoutPhase.preparing =>
                              ThreadBodyLayoutPhase.preparing,
                            ForumHtmlBodyLayoutPhase.built =>
                              ThreadBodyLayoutPhase.built,
                            ForumHtmlBodyLayoutPhase.failed =>
                              ThreadBodyLayoutPhase.failed,
                          };
                        }
                      },
                onGeometry: (ready, complete) {
                  if (!mounted || _readingIdentity != readingIdentity) return;
                  _readingReady = ready;
                  _nativeBoundaryKnown = complete;
                  coordinator?.schedule();
                },
              )
            : _comparisonBuilder!(
                ForumHtmlComparisonBodyInput(
                  html: html,
                  theme: widget.theme,
                  textStyle: textStyle,
                  preparedDocument: preparedDocument,
                  sourceId: sourceId,
                  threadId: widget.threadId,
                  imageReferer: widget.imageReferer,
                  imageCacheOwnerId: widget.threadId,
                  imageFallbackAspectRatioFor:
                      widget.imageFallbackAspectRatioFor,
                  onBlockImageResolved: widget.onBlockImageResolved,
                  imageViewportCoordinator: widget.imageViewportCoordinator,
                  imageAnchorController: widget.imageAnchorController,
                  bodyPresentation:
                      bodyLayout?.rendering ?? widget.bodyPresentation,
                  collapseExpansion: expansion,
                  imageHost: tracked ? _readingImageHost : null,
                  onBodyBuilt: !tracked && bodyLayout == null
                      ? null
                      : () {
                          if (tracked &&
                              mounted &&
                              readingRevision == _readingRevision) {
                            _readingReady = true;
                            coordinator!.schedule();
                          }
                          if (mounted &&
                              identical(_bodyLayoutLease, bodyLayout) &&
                              _preparation.identity == identity &&
                              bodyLayout?.isCurrent == true) {
                            _bodyLayoutPhase = ThreadBodyLayoutPhase.built;
                          }
                        },
                  imagePrecacheService: widget.imagePrecacheService,
                  preferences: preferences,
                  callbacks: callbacks,
                ),
              ),
      );
      final viewport = widget.imageViewportCoordinator;
      final viewportBody = _nativeBody && viewport != null
          ? ForumHtmlImageViewportScope(coordinator: viewport, child: body)
          : body;
      return !tracked
          ? viewportBody
          : ThreadBodyReadingBoundary(
              key: _readingKey,
              coordinator: coordinator!,
              child: viewportBody,
            );
    } catch (error, stackTrace) {
      _bodyLayoutPhase = ThreadBodyLayoutPhase.failed;
      _nativeLayoutPhase = ForumHtmlBodyLayoutPhase.failed;
      _logRenderFailure(
        htmlLength: html.length,
        error: error,
        stackTrace: stackTrace,
      );
      return widget.fallback ?? const ThreadPostHtmlBodyError();
    }
  }

  void _logPreparedDocument({
    required String sourceId,
    required int htmlLength,
    required ForumHtmlPreparedRenderDocument preparedDocument,
  }) {
    if (!kDebugMode) {
      return;
    }
    final key = [
      sourceId,
      htmlLength,
      preparedDocument.preparedHtml.length,
      preparedDocument.sequence.entries.length,
      preparedDocument.totalImageCount,
      preparedDocument.themeSignature,
    ].join(':');
    if (_lastPreparedLogKey == key) {
      return;
    }
    _lastPreparedLogKey = key;
    final sourcePost = widget.sourcePost ?? widget.post;
    final themeStats = preparedDocument.themeAdaptationStats;
    final minimumContrast = themeStats.minimumResultContrast;
    _logNative(
      'render_prepare_success',
      'tid=${widget.threadId} pid=${sourcePost.pid} postNo=${sourcePost.number} '
          'rawLength=$htmlLength preparedLength=${preparedDocument.preparedHtml.length} '
          'totalImages=${preparedDocument.totalImageCount} '
          'readableImages=${preparedDocument.sequence.entries.length} '
          'stickers=${preparedDocument.skippedStickerCount} '
          'nonNetwork=${preparedDocument.skippedNonNetworkCount} '
          'duplicates=${preparedDocument.duplicatedReadableUrlCount} '
          'attachments=${preparedDocument.attachmentTaggedCount} '
          'theme=${widget.theme.brightness.name} '
          'foregrounds=${themeStats.explicitForegroundCount} '
          'foregroundRemapped=${themeStats.remappedForegroundCount} '
          'backgrounds=${themeStats.explicitBackgroundCount} '
          'backgroundRemapped=${themeStats.remappedBackgroundCount} '
          'unsupported=${themeStats.unsupportedColorCount} '
          'concealed=${themeStats.concealedTextRangeCount} '
          'minimumContrast=${minimumContrast?.toStringAsFixed(2) ?? '-'}',
    );
  }

  void _logRenderFailure({
    required int htmlLength,
    required Object error,
    required StackTrace stackTrace,
  }) {
    if (!kDebugMode) {
      return;
    }
    final sourcePost = widget.sourcePost ?? widget.post;
    final key = '${sourcePost.pid}:$htmlLength:$error';
    if (_lastRenderFailureLogKey == key) {
      return;
    }
    _lastRenderFailureLogKey = key;
    _logNative(
      'render_failure',
      'tid=${widget.threadId} pid=${sourcePost.pid} postNo=${sourcePost.number} '
          'rawLength=$htmlLength error=${_oneLine(error.toString())} '
          'stack=${_stackHead(stackTrace)}',
    );
  }

  void _handleTapImage(
    ForumHtmlReadableImageSequence sequence,
    ForumHtmlImageRequest request,
  ) {
    final sourcePost = widget.sourcePost ?? widget.post;
    final result = widget.imageReaderBridge.buildOpenRequest(
      post: sourcePost,
      threadId: widget.threadId,
      imageReferer: widget.imageReferer,
      sequence: sequence,
      imageRequest: request,
    );
    widget.onImageDiagnostics?.call(sourcePost, request, result);
    final openRequest = result.request;
    if (openRequest == null) {
      if (!request.isSticker) {
        widget.onImageFallback?.call(sourcePost, request);
      }
      return;
    }
    final imageOpenHandler = widget.onOpenPostImage;
    if (imageOpenHandler == null) {
      widget.onImageFallback?.call(sourcePost, request);
      return;
    }
    imageOpenHandler(sourcePost, openRequest);
  }

  void _logNative(String stage, String message) {
    debugPrint('[ThreadDetail][native][$stage] $message');
  }

  String _oneLine(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _stackHead(StackTrace stackTrace) {
    final text = stackTrace.toString().trim();
    if (text.isEmpty) {
      return '-';
    }
    return _oneLine(text.split('\n').first);
  }
}

/// Production HTML-first thread body.
///
/// Renders prepared HTML and opens images from that document's readable
/// sequence. Preparation failures show a recoverable error block.
class ThreadPostHtmlBody extends StatelessWidget {
  const ThreadPostHtmlBody({
    super.key,
    required this.post,
    this.sourcePost,
    required this.threadId,
    required this.imageReferer,
    required this.onOpenPostLink,
    this.onOpenSelectedPostLink,
    required this.onOpenPostImage,
    required this.theme,
    this.onImageFallback,
    this.onImageDiagnostics,
    this.onImageLayoutShift,
    this.imageFallbackAspectRatioFor,
    this.onBlockImageResolved,
    this.imageViewportCoordinator,
    this.imageAnchorController,
    this.readingCoordinator,
    this.bodyPresentation,
    this.wholeBodyPresentation,
    this.imagePrecacheService,
    this.renderPreparer = const DefaultForumHtmlRenderPreparer(),
    this.preparationExecutor,
    this.onPreparedBody,
    this.preparerSelector,
    this.imageReaderBridge = const ThreadHtmlImageReaderBridge(),
    this.nativeBody = false,
    this.selectEntireBody = false,
    this.isSelectionCurrent,
  });

  final ThreadPost post;
  final ThreadPost? sourcePost;
  final String threadId;
  final String imageReferer;
  final ValueChanged<String> onOpenPostLink;
  final ForumSelectionLinkOpener? onOpenSelectedPostLink;
  final void Function(ThreadPost post, ThreadImageOpenRequest request)?
  onOpenPostImage;
  final ForumHtmlThemeContext theme;
  final ThreadPostHtmlFirstImageFallback? onImageFallback;
  final ThreadPostHtmlFirstImageDiagnostics? onImageDiagnostics;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
  final double? Function(ForumImageLoadSpec spec, ImageCacheRequest request)?
  imageFallbackAspectRatioFor;
  final void Function(
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )?
  onBlockImageResolved;
  final ForumHtmlImageViewportCoordinator? imageViewportCoordinator;
  final ForumHtmlImageAnchorController? imageAnchorController;
  final ThreadBodyReadingCoordinator? readingCoordinator;
  final ForumHtmlBodyPresentation? bodyPresentation;
  final ThreadBodyPresentation? wholeBodyPresentation;
  final ForumImagePrecacheService? imagePrecacheService;
  final ForumHtmlRenderPreparer renderPreparer;
  final ForumHtmlPreparationExecutor? preparationExecutor;
  final ThreadPreparedBodyHandoff? onPreparedBody;
  final ThreadPreparedBodyPreparerSelector? preparerSelector;
  final ThreadHtmlImageReaderBridge imageReaderBridge;
  final bool nativeBody;
  final bool selectEntireBody;
  final bool Function()? isSelectionCurrent;

  @override
  Widget build(BuildContext context) {
    return ThreadPostHtmlFirstBody(
      post: post,
      sourcePost: sourcePost,
      threadId: threadId,
      imageReferer: imageReferer,
      onOpenPostLink: onOpenPostLink,
      onOpenSelectedPostLink: onOpenSelectedPostLink,
      onOpenPostImage: onOpenPostImage,
      theme: theme,
      onImageFallback: onImageFallback,
      onImageDiagnostics: onImageDiagnostics,
      onImageLayoutShift: onImageLayoutShift,
      imageFallbackAspectRatioFor: imageFallbackAspectRatioFor,
      onBlockImageResolved: onBlockImageResolved,
      imageViewportCoordinator: imageViewportCoordinator,
      imageAnchorController: imageAnchorController,
      readingCoordinator: readingCoordinator,
      bodyPresentation: bodyPresentation,
      wholeBodyPresentation: wholeBodyPresentation,
      imagePrecacheService: imagePrecacheService,
      renderPreparer: renderPreparer,
      preparationExecutor: preparationExecutor,
      onPreparedBody: onPreparedBody,
      preparerSelector: preparerSelector,
      imageReaderBridge: imageReaderBridge,
      nativeBody: nativeBody,
      selectEntireBody: selectEntireBody,
      isSelectionCurrent: isSelectionCurrent,
    );
  }
}

class ThreadPostHtmlBodyError extends StatelessWidget {
  const ThreadPostHtmlBodyError({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('thread-post-html-body-error'),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          AppLocalizations.of(context).threadHtmlRenderFailed,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: colors.onErrorContainer),
        ),
      ),
    );
  }
}
