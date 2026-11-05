import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:html_pagination_core/html_pagination_core.dart'
    show HtmlProjectionAffinity;
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart' show ResolvedFont;
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

import '../controllers/novel_reader_native_paged_controller.dart';
import '../controllers/novel_reader_paged_navigation_controller.dart';
import '../models/novel_reader_chapter_turn.dart';
import '../models/novel_reader_anchor_navigation_request.dart';
import '../models/novel_reader_native_host_status.dart';
import '../models/novel_reader_native_page_coverage.dart';
import '../models/novel_reader_native_page_view.dart';
import '../models/novel_reader_native_image_tap.dart';
import '../models/novel_reader_native_link_handler.dart';
import '../models/novel_reader_native_prepared_chapter.dart';
import '../models/novel_reader_pagination_position.dart';
import '../models/novel_reader_native_text_selection.dart';
import '../services/novel_reader_native_layout_scope.dart';
import '../services/novel_reader_native_owner.dart';
import '../services/novel_reader_native_image_resources.dart';
import '../services/novel_reader_native_preparation_service.dart';
import '../services/novel_reader_native_render_environment.dart';
import '../services/novel_reader_native_work_scheduler.dart';
import '../services/novel_reader_pagination_cancellation.dart';
import '../services/novel_reader_pagination_demand.dart';
import '../services/novel_reader_pagination_performance_policy.dart';
import 'novel_reader_native_paged_viewport.dart';

/// Paged lifecycle assembly for the exact content box supplied by the shell.
/// Shell owns padding/safe-area/chrome, localized recovery, reading authority
/// and persistence. This Host owns actual layout requests, borrows the reading
/// owner/loaded font snapshot, and never writes modes/positions or falls back.
class NovelReaderNativeLayoutHost extends StatefulWidget {
  const NovelReaderNativeLayoutHost({
    super.key,
    required this.owner,
    required this.sourceId,
    required this.rawHtml,
    required this.semanticDocument,
    required this.preferences,
    required this.resolvedFont,
    required this.progressSnapshot,
    required this.readingAuthorityIdentity,
    required this.preparationService,
    this.converter = const IdentityTextConverter(),
    this.imageHost,
    this.imagePolicy = const ForumCacheHtmlPreparationImagePolicy(),
    this.imageThreadId,
    this.imageCacheOwnerId,
    this.stylePolicy,
    this.startsAtBeginning = false,
    this.chapterEntryRequest,
    this.conversionAnchor,
    this.onChapterEntryApplied,
    this.onChapterEntryRetired,
    this.navigationController,
    this.onTurnToAdjacentChapter,
    this.chapterTurnIsInFlight = false,
    this.previousChapterTitle,
    this.nextChapterTitle,
    this.chapterTurnPolicy = const NovelReaderChapterTurnPolicy(),
    this.onChapterTurnHintChanged,
    this.pageSeekRequest,
    this.onPageSeekFinished,
    this.navigationRequest,
    this.textHighlight,
    this.onNavigationFinished,
    this.onPositionChanged,
    this.onStatusChanged,
    this.onContentReady,
    this.onContentTerminal,
    this.onScrollActivityChanged,
    this.onTextSelection,
    this.onLinkTap,
    this.onImageTap,
    this.active = true,
    this.activity,
    this.placeholderBuilder,
    this.retryRevision = 0,
    this.scheduler = const NovelReaderNativeWorkScheduler(),
    this.performance = const NovelReaderPaginationPerformancePolicy(),
    this.idleScheduler,
    this.sessionLimits = const ForumBodyTextPageSessionLimits(
      maxPages: 10000,
      maxFragments: 100000,
      maxParagraphs: 16384,
      maxTextCodeUnits: 1024 * 1024,
      maxRuns: 100000,
      maxIssuedLeases: 512,
    ),
  });
  final NovelReaderNativeOwner owner;
  final String sourceId;
  final String rawHtml;
  final NovelReaderDocument semanticDocument;
  final NovelReaderPreferences preferences;
  final ResolvedFont resolvedFont;
  final NovelReaderProgressSnapshot progressSnapshot;
  final Object readingAuthorityIdentity;
  final NovelReaderNativePreparationService preparationService;
  final TextConverter converter;
  final ForumHtmlImageHost? imageHost;
  final ForumHtmlPreparationImagePolicy imagePolicy;
  final String? imageThreadId, imageCacheOwnerId;
  final ForumBodyStylePolicy? stylePolicy;
  final bool startsAtBeginning;
  final NovelReaderChapterEntryRequest? chapterEntryRequest;
  final NovelReaderTextAnchor? conversionAnchor;
  final ValueChanged<NovelReaderChapterEntryRequest>? onChapterEntryApplied;

  /// Releases a superseded entry's UI latch without claiming it was reached.
  final ValueChanged<NovelReaderChapterEntryRequest>? onChapterEntryRetired;
  final NovelReaderPagedNavigationController? navigationController;
  final bool Function(NovelReaderChapterEdge)? onTurnToAdjacentChapter;
  final bool chapterTurnIsInFlight;
  final String? previousChapterTitle;
  final String? nextChapterTitle;
  final NovelReaderChapterTurnPolicy chapterTurnPolicy;

  /// Localized hint UI belongs to the shell, outside the measured content box.
  final ValueChanged<NovelReaderChapterTurnHint?>? onChapterTurnHintChanged;
  final NovelReaderPageSeekRequest? pageSeekRequest;
  final void Function(NovelReaderPageSeekRequest, NovelReaderNavigationOutcome)?
  onPageSeekFinished;
  final NovelReaderAnchorNavigationRequest? navigationRequest;
  final NovelReaderTextRange? textHighlight;
  final void Function(
    NovelReaderAnchorNavigationRequest,
    NovelReaderNavigationOutcome,
  )?
  onNavigationFinished;
  final ValueChanged<NovelReaderPaginationPosition>? onPositionChanged;
  final ValueChanged<NovelReaderNativeHostStatus>? onStatusChanged;
  final VoidCallback? onContentReady;
  final VoidCallback? onContentTerminal;
  final ValueChanged<bool>? onScrollActivityChanged;
  final ValueChanged<NovelReaderNativeTextSelection>? onTextSelection;
  final NovelReaderNativeLinkHandler? onLinkTap;
  final ValueChanged<NovelReaderNativeImageTap>? onImageTap;

  /// Shell supplies frontmost && resumed && unobstructed reading authority.
  /// Hidden content keeps its mounted paint but owns no active pagination work.
  final bool active;

  /// Borrowed synchronous lifecycle gate. Work stops on false even when Flutter
  /// cannot build an inactive frame; true schedules normal Scope revalidation.
  final ValueListenable<bool>? activity;
  final Widget Function(BuildContext, NovelReaderNativeHostStatus)?
  placeholderBuilder;

  /// Explicit retry gets a new request/session and verifies a matching prefix.
  final int retryRevision;
  final NovelReaderNativeWorkScheduler scheduler;
  final NovelReaderPaginationPerformancePolicy performance;
  final NovelReaderPaginationIdleScheduler? idleScheduler;
  final ForumBodyTextPageSessionLimits sessionLimits;

  @override
  State<NovelReaderNativeLayoutHost> createState() => _NativeLayoutHostState();
}

class _NativeLayoutHostState extends State<NovelReaderNativeLayoutHost> {
  final _retired = <_LayoutRequest>{};
  _LayoutRequest? _current;
  StreamSubscription<void>? _changes;
  NovelReaderPaginationCancellationToken? _pending;
  Size? _box;
  int _epoch = 0;
  int _statusRevision = 0;
  int _chapterHintRevision = 0;
  NovelReaderChapterTurnHint? _chapterHint;
  int _readyEpoch = -1;
  int _terminalEpoch = -1;
  bool _needsLayout = true;
  int _selectionRevision = 0;
  bool _paintOnlyCandidate = false;
  bool _busy = true;
  bool _empty = false;
  bool _force = false;
  bool _disposed = false;
  bool _invalidBox = false;
  bool _beginningConsumed = false;
  (int, String, NovelReaderChapterEdge)? _finishedEntry;
  Object? _error;
  ForumBodyTextPageSnapshot? _verifiedPrefix;
  String? _prefixKey;
  NovelReaderNativeOwner? _prefixOwner;
  _NativeNavigationIntent? _navigationIntent;
  Object? _seenNavigation;
  bool _selectAnchorNavigation = false;
  int _navigationFrameRevision = 0;
  late bool _lastActive;
  ForumBodyIdentity? _collapseIdentity;
  final _collapseExpansion = <String, bool>{};
  NovelReaderTextAnchor? _collapseRestoreHint;
  ForumBodyIdentity? _imageGeometryIdentity;
  final _imageLayouts = <String, ForumHtmlImageLayout>{};
  final _inlineImageSizes = <String, Size>{};
  _LayoutRequest? _imageReflowRequest;
  bool _imageReflowScheduled = false;

  bool get _active => widget.active && (widget.activity?.value ?? true);

  @override
  void initState() {
    super.initState();
    _lastActive = _active;
    widget.activity?.addListener(_activityChanged);
    _selectAnchorNavigation = widget.navigationRequest != null;
    if (!widget.owner.isClosed) widget.owner.addListener(_ownerChanged);
    _notifyStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_needsLayout) _paintOnlyCandidate = true;
    _needsLayout = true;
  }

  @override
  void didUpdateWidget(covariant NovelReaderNativeLayoutHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.activity, widget.activity)) {
      oldWidget.activity?.removeListener(_activityChanged);
      widget.activity?.addListener(_activityChanged);
    }
    final pageChanged =
        _pageSeekKey(oldWidget.pageSeekRequest) !=
        _pageSeekKey(widget.pageSeekRequest);
    final anchorChanged =
        _anchorNavigationKey(oldWidget.navigationRequest) !=
        _anchorNavigationKey(widget.navigationRequest);
    final newPage = pageChanged && widget.pageSeekRequest != null;
    final newAnchor = anchorChanged && widget.navigationRequest != null;
    if (newPage ||
        newAnchor ||
        (_selectAnchorNavigation ? anchorChanged : pageChanged)) {
      final retiring = _navigationIntent;
      _finishNavigation(NovelReaderNavigationOutcome.retired);
      _seenNavigation = null;
      if (newPage ||
          newAnchor ||
          (retiring != null &&
              retiring.controller.navigationRevision == retiring.revision)) {
        _current?.controller.cancelPendingNavigation();
      }
      // An anchor wins simultaneous new inputs. Removing a consumed older
      // input never resurrects it or cancels the selected newer command.
      if (newAnchor) {
        _selectAnchorNavigation = true;
      } else if (newPage) {
        _selectAnchorNavigation = false;
      }
    }
    final ownerChanged = !identical(oldWidget.owner, widget.owner);
    final novelChanged =
        oldWidget.progressSnapshot.novelId != widget.progressSnapshot.novelId;
    if (ownerChanged) {
      oldWidget.owner.removeListener(_ownerChanged);
      _closeAll();
      if (!widget.owner.isClosed) widget.owner.addListener(_ownerChanged);
    }
    if (novelChanged && !ownerChanged) _closeAll();
    _applyActivity();
    final chapterChanged =
        oldWidget.semanticDocument.episodeId !=
        widget.semanticDocument.episodeId;
    if (chapterChanged ||
        !identical(
          oldWidget.readingAuthorityIdentity,
          widget.readingAuthorityIdentity,
        )) {
      _resetCollapses();
    }
    if (ownerChanged ||
        novelChanged ||
        chapterChanged ||
        (!oldWidget.startsAtBeginning && widget.startsAtBeginning)) {
      _beginningConsumed = false;
    }
    if (ownerChanged || novelChanged || chapterChanged) _finishedEntry = null;
    final oldEntry = oldWidget.chapterEntryRequest;
    final entry = widget.chapterEntryRequest;
    final oldEntryPending =
        oldEntry != null &&
        oldEntry.episodeId == oldWidget.semanticDocument.episodeId &&
        _finishedEntry != _entryKey(oldEntry);
    final entryChanged =
        _entryKey(oldEntry) != _entryKey(entry) &&
        (entry?.episodeId == widget.semanticDocument.episodeId ||
            oldEntryPending);
    if (entryChanged &&
        oldEntryPending &&
        !ownerChanged &&
        !novelChanged &&
        !chapterChanged) {
      _finishChapterEntry(
        oldEntry,
        applied: false,
        callback: oldWidget.onChapterEntryRetired,
      );
    }
    final retry = oldWidget.retryRevision != widget.retryRevision;
    if ((entryChanged || retry) &&
        !newPage &&
        !newAnchor &&
        !ownerChanged &&
        !novelChanged &&
        !chapterChanged) {
      _retireNavigationInput();
    }
    // The page drops its bootstrap hint after the first real position report.
    // A fulfilled intent is no longer a layout input; withdrawing it must not
    // invalidate the live paint or the position lease it just established.
    final hintChanged =
        oldWidget.conversionAnchor != widget.conversionAnchor &&
        (widget.conversionAnchor != null || _current?.confirmed == null);
    final beginningChanged =
        oldWidget.startsAtBeginning != widget.startsAtBeginning &&
        (!_beginningConsumed || widget.startsAtBeginning);
    final resourcesChanged =
        !identical(oldWidget.sessionLimits, widget.sessionLimits) ||
        !identical(oldWidget.performance, widget.performance) ||
        !identical(oldWidget.scheduler, widget.scheduler) ||
        oldWidget.idleScheduler != widget.idleScheduler;
    final imageBindingChanged =
        !identical(oldWidget.imageHost, widget.imageHost) ||
        !identical(oldWidget.imagePolicy, widget.imagePolicy) ||
        oldWidget.imageThreadId != widget.imageThreadId ||
        oldWidget.imageCacheOwnerId != widget.imageCacheOwnerId;
    if (retry ||
        entryChanged ||
        !identical(
          oldWidget.readingAuthorityIdentity,
          widget.readingAuthorityIdentity,
        ) ||
        oldWidget.rawHtml != widget.rawHtml ||
        !identical(oldWidget.semanticDocument, widget.semanticDocument) ||
        oldWidget.sourceId != widget.sourceId) {
      _stop(_current);
    }
    final inputsChanged =
        ownerChanged ||
        novelChanged ||
        chapterChanged ||
        entryChanged ||
        retry ||
        !identical(
          oldWidget.readingAuthorityIdentity,
          widget.readingAuthorityIdentity,
        ) ||
        oldWidget.sourceId != widget.sourceId ||
        oldWidget.rawHtml != widget.rawHtml ||
        !identical(oldWidget.semanticDocument, widget.semanticDocument) ||
        oldWidget.resolvedFont != widget.resolvedFont ||
        oldWidget.converter.id != widget.converter.id ||
        oldWidget.converter.mode != widget.converter.mode ||
        !identical(oldWidget.preparationService, widget.preparationService) ||
        !identical(oldWidget.stylePolicy, widget.stylePolicy) ||
        hintChanged ||
        resourcesChanged ||
        imageBindingChanged ||
        beginningChanged;
    if (inputsChanged || oldWidget.preferences != widget.preferences) {
      _selectionRevision++;
      // Only color requests may join the context paint check. The immutable
      // scope still rejects foreground/link changes before accepting a canvas.
      final colorOnly =
          !inputsChanged &&
          (!_needsLayout || _paintOnlyCandidate) &&
          oldWidget.preferences.copyWith(colors: widget.preferences.colors) ==
              widget.preferences;
      _paintOnlyCandidate = colorOnly;
      _needsLayout = true;
      if (!colorOnly) _busy = true;
      _force =
          _force ||
          retry ||
          entryChanged ||
          hintChanged ||
          resourcesChanged ||
          (!oldWidget.startsAtBeginning && widget.startsAtBeginning);
    }
    _scheduleNavigation();
    if (_busy ||
        !_active ||
        oldWidget.previousChapterTitle != widget.previousChapterTitle ||
        oldWidget.nextChapterTitle != widget.nextChapterTitle ||
        widget.chapterTurnIsInFlight) {
      _chapterHintChanged(null);
    }
  }

  void _ownerChanged() {
    if (_disposed) return;
    _pending?.cancel();
    _epoch++;
    if (widget.owner.isClosed) _closeAll();
    if (_current?.handle.isCurrent == false) _stop(_current);
    setState(() {
      _paintOnlyCandidate = false;
      _needsLayout = true;
      _busy = true;
    });
  }

  void _activityChanged() {
    if (_disposed || !mounted) return;
    if (_applyActivity()) setState(() {});
  }

  bool _applyActivity() {
    final active = _active;
    if (active == _lastActive) return false;
    _lastActive = active;
    _pending?.cancel();
    _epoch++;
    _paintOnlyCandidate = false;
    _needsLayout = true;
    _busy = active;
    if (!active) {
      _current?.controller.suspend();
      _retireNavigationInput();
      _chapterHintChanged(null);
    }
    _notifyStatus();
    final epoch = _epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed && epoch == _epoch) {
        widget.onScrollActivityChanged?.call(false);
      }
    });
    return true;
  }

  NovelReaderNativeHostStatus get _status {
    final request = _current;
    final live = request != null && _live(request);
    final visible =
        !_invalidBox &&
        (request?.confirmed != null ||
            _retired.any((r) => r.confirmed != null));
    final error = _error ?? (live ? request.controller.error : null);
    final phase = widget.owner.isClosed
        ? NovelReaderNativeHostPhase.closed
        : !_active
        ? NovelReaderNativeHostPhase.inactive
        : _busy
        ? NovelReaderNativeHostPhase.preparing
        : _empty ||
              request?.controller.phase == NovelReaderNativePagedPhase.empty
        ? NovelReaderNativeHostPhase.empty
        : error != null
        ? (visible
              ? NovelReaderNativeHostPhase.paused
              : NovelReaderNativeHostPhase.failed)
        : visible
        ? NovelReaderNativeHostPhase.reading
        : NovelReaderNativeHostPhase.preparing;
    return NovelReaderNativeHostStatus(
      phase: phase,
      hasVisiblePage: visible,
      isRetainingPreviousLayout:
          visible && (!live || request.confirmed == null),
      controller: live && !request.controller.isClosed
          ? request.controller
          : null,
      pageCount: live ? request.controller.snapshot?.length ?? 0 : 0,
      isPageCountFinal: live && request.controller.snapshot?.isComplete == true,
      visiblePageIndex: live ? request.controller.visiblePageIndex : null,
      error: error,
    );
  }

  bool _live(_LayoutRequest request) =>
      !_disposed &&
      _active &&
      !_busy &&
      !request.controller.isSuspended &&
      identical(request, _current) &&
      request.epoch == _epoch &&
      identical(request.owner, widget.owner) &&
      request.handle.isCurrent &&
      identical(request.authority, widget.readingAuthorityIdentity);

  void _tryCanvas(BuildContext context, Size box) {
    final request = _current;
    if (!_paintOnlyCandidate ||
        !_needsLayout ||
        _box != box ||
        _force ||
        _pending != null ||
        request == null ||
        !_live(request)) {
      return;
    }
    final epoch = _epoch;
    bool current() =>
        mounted &&
        _paintOnlyCandidate &&
        _needsLayout &&
        _epoch == epoch &&
        _live(request) &&
        !request.controller.isClosed;
    try {
      final environment = NovelReaderNativeRenderEnvironment.capture(
        context,
        preferences: widget.preferences,
        resolvedFont: widget.resolvedFont,
        policy: widget.stylePolicy,
      );
      final updated = request.scope.tryUpdateCanvas(
        environment: environment,
        width: box.width,
        height: box.height,
        fontCollectionGeneration: widget.owner.fontGeneration,
        isCurrent: current,
      );
      if (updated == null || !current()) return;
      request.scope = updated;
      _needsLayout = false;
      _paintOnlyCandidate = false;
    } catch (_) {
      // The normal configuration path owns errors and recovery. This check
      // never suppresses invalid input or creates a new reading generation.
    }
  }

  void _notifyStatus() {
    final request = _current;
    if (request == null || !_live(request)) _chapterHintChanged(null);
    final revision = ++_statusRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted || revision != _statusRevision) return;
      final status = _status;
      widget.onStatusChanged?.call(status);
      if (_disposed || !mounted || revision != _statusRevision) return;
      if ((status.phase == NovelReaderNativeHostPhase.empty ||
              status.phase == NovelReaderNativeHostPhase.failed) &&
          _terminalEpoch != _epoch) {
        _terminalEpoch = _epoch;
        widget.onContentTerminal?.call();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _chapterHintChanged(NovelReaderChapterTurnHint? hint) {
    if (hint == _chapterHint) return;
    _chapterHint = hint;
    final revision = ++_chapterHintRevision;
    final owner = widget.owner;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed ||
          !mounted ||
          revision != _chapterHintRevision ||
          !identical(owner, widget.owner)) {
        return;
      }
      final current = _current;
      if (_chapterHint != null && (current == null || !_live(current))) {
        _chapterHint = null;
      }
      widget.onChapterTurnHintChanged?.call(_chapterHint);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (boxContext, constraints) {
      final box = Size(constraints.maxWidth, constraints.maxHeight);
      final valid =
          constraints.hasBoundedWidth &&
          constraints.hasBoundedHeight &&
          box.width > 0 &&
          box.height > 0 &&
          box.width <= 16384 &&
          box.height <= 16384;
      if (!valid || widget.owner.isClosed) {
        _invalidBox = true;
        _pending?.cancel();
        if (_box != box || _needsLayout) {
          _epoch++;
          _box = box;
          _needsLayout = false;
          _paintOnlyCandidate = false;
          _busy = false;
          _error = const NovelReaderNativeLayoutInputException(
            NovelReaderNativeLayoutInputFailure.geometry,
          );
          _notifyStatus();
          final epoch = _epoch;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && epoch == _epoch) _closeAll();
          });
        }
        return widget.placeholderBuilder?.call(context, _status) ??
            const SizedBox.shrink();
      }
      _invalidBox = false;
      _tryCanvas(context, box);
      if (widget.owner.isClosed) {
        return widget.placeholderBuilder?.call(context, _status) ??
            const SizedBox.shrink();
      }
      if (!_active) {
        _pending?.cancel();
        _busy = false;
        _needsLayout = true;
        _paintOnlyCandidate = false;
      } else if (_needsLayout || _box != box) {
        _finishNavigation(NovelReaderNavigationOutcome.retired);
        _box = box;
        _needsLayout = false;
        _paintOnlyCandidate = false;
        _busy = true;
        _empty = false;
        _error = null;
        _pending?.cancel();
        final token = _pending = NovelReaderPaginationCancellationToken();
        final epoch = ++_epoch;
        final config = widget;
        final force = _force;
        _force = false;
        NovelReaderNativeRenderEnvironment? environment;
        Object? captureError;
        try {
          environment = NovelReaderNativeRenderEnvironment.capture(
            context,
            preferences: config.preferences,
            resolvedFont: config.resolvedFont,
            policy: config.stylePolicy,
          );
        } catch (error) {
          captureError = error;
        }
        _notifyStatus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || epoch != _epoch || token.isCancelled) return;
          widget.onScrollActivityChanged?.call(false);
          _current?.controller.cancelPendingNavigation();
          unawaited(
            _prepare(
              config,
              environment,
              captureError,
              box,
              epoch,
              token,
              force,
            ),
          );
        });
      }
      _scheduleNavigation();
      final request = _current;
      if (request == null ||
          _empty ||
          request.controller.phase == NovelReaderNativePagedPhase.empty) {
        return widget.placeholderBuilder?.call(context, _status) ??
            const SizedBox.shrink();
      }
      final imageHost =
          request.scope.chapter.identity.sourceId == widget.sourceId &&
              request.scope.chapter.episodeId ==
                  widget.semanticDocument.episodeId
          ? widget.imageHost
          : request.imageHost;
      final viewport = NovelReaderNativePagedViewport(
        key: ObjectKey(widget.owner),
        controller: request.controller,
        ownerIdentity: request.owner,
        readingAuthorityIdentity: request.authority,
        active: _live(request),
        reverse: request.reverse,
        backgroundColor: request.scope.backgroundColor,
        imageHost: imageHost,
        onCollapseToggle: request.scope.collapses == null
            ? null
            : (view, fragment) => _toggleCollapse(request, view, fragment),
        onImageLayoutResolved: (view, fragment, layout) =>
            _imageLayoutResolved(request, view, fragment, layout, imageHost),
        onInlineImageLayoutResolved: (view, fragment, binding, layout) =>
            _inlineImageLayoutResolved(
              request,
              view,
              fragment,
              binding,
              layout,
              imageHost,
            ),
        onImageTap: widget.onImageTap == null
            ? null
            : (fragment, binding, isCurrent) {
                final images = request.scope.images;
                if (!_live(request) ||
                    images == null ||
                    !identical(imageHost, widget.imageHost) ||
                    !isCurrent()) {
                  return;
                }
                final entry = switch (fragment) {
                  ForumBodyPreparedImageFragment(:final content)
                      when binding == null && images.owns(content.input) =>
                    content.input.entry,
                  ForumBodyPreparedInlineFragment()
                      when binding != null &&
                          images.ownsInline(binding.input) =>
                    binding.input.entry,
                  _ => null,
                };
                if (entry == null) return;
                final revision = _selectionRevision;
                widget.onImageTap!(
                  NovelReaderNativeImageTap(
                    entry,
                    images.sequence,
                    () =>
                        mounted &&
                        !_disposed &&
                        revision == _selectionRevision &&
                        identical(request, _current) &&
                        !request.closed &&
                        request.handle.isCurrent &&
                        identical(request.owner, widget.owner) &&
                        !widget.owner.isClosed &&
                        identical(
                          request.authority,
                          widget.readingAuthorityIdentity,
                        ) &&
                        identical(imageHost, widget.imageHost) &&
                        isCurrent(),
                  ),
                );
              },
        onPageUnmounted: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_disposed) _reap();
          });
          WidgetsBinding.instance.ensureVisualUpdate();
        },
        navigationController: widget.navigationController,
        chapterTurnIsInFlight: widget.chapterTurnIsInFlight,
        previousChapterTitle: widget.previousChapterTitle,
        nextChapterTitle: widget.nextChapterTitle,
        chapterTurnPolicy: widget.chapterTurnPolicy,
        onChapterTurnHintChanged: (hint) {
          if (identical(request, _current) &&
              (hint == null || _live(request))) {
            _chapterHintChanged(hint);
          }
        },
        onTurnToAdjacentChapter: widget.onTurnToAdjacentChapter == null
            ? null
            : (edge) => _live(request) && widget.onTurnToAdjacentChapter!(edge),
        placeholder:
            widget.placeholderBuilder?.call(context, _status) ??
            const SizedBox.shrink(),
        onPositionChanged: (position) => _confirmed(request, position),
        onLinkTap: widget.onLinkTap == null
            ? null
            : (url, isCurrent) {
                final revision = _selectionRevision;
                bool current() =>
                    mounted &&
                    revision == _selectionRevision &&
                    _live(request) &&
                    isCurrent();
                if (current()) widget.onLinkTap?.call(url, current);
              },
        onTextSelection: widget.onTextSelection == null
            ? null
            : (selection) {
                if (!_live(request)) return;
                final revision = _selectionRevision;
                widget.onTextSelection!(
                  NovelReaderNativeTextSelection(
                    selection.snapshot,
                    () =>
                        mounted &&
                        !_disposed &&
                        revision == _selectionRevision &&
                        identical(request, _current) &&
                        !request.closed &&
                        request.handle.isCurrent &&
                        !widget.owner.isClosed &&
                        identical(request.owner, widget.owner) &&
                        identical(
                          request.authority,
                          widget.readingAuthorityIdentity,
                        ) &&
                        selection.isCurrent,
                  ),
                );
              },
        onScrollActivityChanged: (scrolling) {
          if (_live(request)) widget.onScrollActivityChanged?.call(scrolling);
        },
      );
      final highlight = widget.textHighlight;
      return ForumBodyTextHighlight(
        ranges: highlight == null
            ? const []
            : request.scope.chapter.anchors.sourceRanges(highlight),
        color: Theme.of(context).colorScheme.tertiary.withValues(alpha: .26),
        child: viewport,
      );
    },
  );

  Future<void> _prepare(
    NovelReaderNativeLayoutHost config,
    NovelReaderNativeRenderEnvironment? environment,
    Object? captureError,
    Size box,
    int epoch,
    NovelReaderPaginationCancellationToken token,
    bool force,
  ) async {
    NovelReaderNativeCacheHandle? handle;
    ForumBodyTextPageSession? session;
    bool current() =>
        mounted &&
        !_disposed &&
        epoch == _epoch &&
        !token.isCancelled &&
        identical(config.owner, widget.owner) &&
        _active &&
        !config.owner.isClosed;
    try {
      if (captureError != null) throw captureError;
      if (config.preferences.flowMode == NovelReaderFlowMode.vertical) {
        throw ArgumentError('Native paged Host requires a paged flow mode');
      }
      if (config.progressSnapshot.episodeId !=
          config.semanticDocument.episodeId) {
        throw StateError('Native Host chapter snapshot changed');
      }
      final prepared = await config.owner.preparationCache.resolve(
        service: config.preparationService,
        episodeId: config.semanticDocument.episodeId,
        sourceId: config.sourceId,
        rawHtml: config.rawHtml,
        semanticDocument: config.semanticDocument,
        converter: config.converter,
        cancellation: token,
      );
      token.throwIfCancelled();
      if (!current()) return;
      if (prepared is NovelReaderNativeEmptyChapter) {
        _changes?.cancel();
        _changes = null;
        _retire(_current);
        _current = null;
        setState(() {
          _empty = true;
          _busy = false;
          _error = null;
        });
        _pending = null;
        token.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && epoch == _epoch) _closeRetired();
        });
        _notifyStatus();
        _scheduleNavigation();
        return;
      }
      final chapter = prepared as NovelReaderNativePreparedChapter;
      if (_collapseIdentity != chapter.identity) {
        _resetCollapses();
        _collapseIdentity = chapter.identity;
      }
      final collapses = chapter.document.collapseElements.isEmpty
          ? null
          : ForumBodyCollapseLayout(
              chapter.document,
              expansionOverrides: _collapseExpansion,
            );
      if (_imageGeometryIdentity != chapter.identity) {
        _imageGeometryIdentity = chapter.identity;
        _imageLayouts.clear();
        _inlineImageSizes.clear();
        _imageReflowRequest = null;
      }
      final images =
          await NovelReaderNativeImageResources(
            chapter: chapter,
            host: config.imageHost,
            policy: config.imagePolicy,
            threadId: config.imageThreadId,
            cacheOwnerId: config.imageCacheOwnerId,
          ).capture(
            cancellation: token,
            maxCodeUnits: config.sessionLimits.maxTextCodeUnits,
            collapses: collapses,
            resolvedLayouts: _imageLayouts,
            resolvedInlineSizes: _inlineImageSizes,
            scheduler: config.scheduler,
          );
      if (!current()) return;
      handle = config.owner.acquireCache();
      final scope = await NovelReaderNativeLayoutScope.prepare(
        chapter: chapter,
        images: images,
        collapses: collapses,
        environment: environment!,
        width: box.width,
        height: box.height,
        cancellation: token,
        fontCollectionGeneration: handle.fontGeneration,
        maxIssuedLeases: config.sessionLimits.maxIssuedLeases,
        maxParagraphCacheEntries: config.owner.maxParagraphEntries,
        maxParagraphCacheEstimatedBytes:
            config.owner.maxParagraphEstimatedBytes,
      );
      token.throwIfCancelled();
      if (!current() || !handle.isCurrent) return;
      final old = _current;
      final entry = config.chapterEntryRequest;
      final activeEntry =
          entry != null &&
              entry.episodeId == prepared.episodeId &&
              _finishedEntry != _entryKey(entry)
          ? entry
          : null;
      final beginning = config.startsAtBeginning && !_beginningConsumed;
      if (!force &&
          (activeEntry == null ||
              _entryKey(activeEntry) == _entryKey(old?.entry)) &&
          (!beginning || old?.beginning == true) &&
          old != null &&
          !old.controller.isClosed &&
          old.scope.paginationKey == scope.paginationKey &&
          identical(old.scope.chapter, prepared) &&
          identical(old.authority, config.readingAuthorityIdentity) &&
          identical(old.owner, config.owner) &&
          old.handle.isCurrent) {
        // A reused Session still delivers its original catalog objects. Only
        // update the canvas; replacing that catalog breaks resource ownership.
        final reused = old.scope.tryUpdateCanvas(
          environment: environment,
          width: box.width,
          height: box.height,
          fontCollectionGeneration: handle.fontGeneration,
          isCurrent: current,
        );
        if (reused != null) {
          old.epoch = epoch;
          old.scope = reused;
          old.reverse =
              config.preferences.flowMode == NovelReaderFlowMode.pagedRtl;
          old.controller.resume();
          setState(() {
            _busy = false;
            _empty = false;
          });
          _pending = null;
          token.cancel();
          _notifyStatus();
          _scheduleNavigation();
          return;
        }
      }
      var position = config.progressSnapshot;
      var hint = _collapseRestoreHint ?? config.conversionAnchor;
      final visibleRequest = old?.confirmed != null
          ? old
          : _retired.where((request) => request.confirmed != null).lastOrNull;
      final visible = visibleRequest?.confirmed;
      if (activeEntry == null &&
          !beginning &&
          visible != null &&
          identical(visibleRequest!.owner, config.owner) &&
          identical(
            visibleRequest.authority,
            config.readingAuthorityIdentity,
          ) &&
          visibleRequest.scope.chapter.identity == scope.chapter.identity &&
          visible.anchor.hasCanonicalTextOffset) {
        if (visible.isReadOnlyCompatibilityRestore) {
          hint ??= visible.anchor;
        } else {
          position = const NovelReaderProgressPolicy().pagedSnapshot(
            novelId: position.novelId,
            episodeId: visible.episodeId,
            flowMode: config.preferences.flowMode,
            pageIndex: visible.pageIndex,
            pageCount: visible.pageCount,
            isPageCountFinal: visible.isPageCountFinal,
            paginationKey: visible.paginationKey,
            anchorNodeId: visible.anchor.nodeId,
            anchorTextOffset: visible.anchor.textOffset,
            anchorFormatVersion: visible.anchor.formatVersion,
            anchorTextIdentity: visible.anchor.textIdentity,
          );
        }
      }
      final layoutHandle = config.owner.acquireCache(
        layoutKey: scope.paginationKey,
      );
      handle.release();
      handle = layoutHandle;
      session = scope.openSession(
        cache: handle.cache,
        layoutId: 'native-host-$epoch',
        limits: config.sessionLimits,
      );
      if (old != null) _rememberPrefix(old);
      final previous =
          force &&
              _prefixKey == scope.paginationKey &&
              identical(_prefixOwner, config.owner)
          ? _verifiedPrefix
          : null;
      final controller = NovelReaderNativePagedController(
        session: session,
        anchors: prepared.anchors,
        position: position,
        paginationKey: scope.paginationKey,
        parent: token,
        conversionAnchor: hint,
        entryEdge:
            activeEntry?.edge ??
            (beginning ? NovelReaderChapterEdge.start : null),
        previousPrefix: previous,
        previousPaginationKey: previous == null ? null : scope.paginationKey,
        scheduler: config.scheduler,
        performance: config.performance,
        idleScheduler: config.idleScheduler,
      );
      final request = _LayoutRequest(
        scope,
        session,
        controller,
        handle,
        token,
        config.owner,
        config.readingAuthorityIdentity,
        epoch,
        config.preferences.flowMode == NovelReaderFlowMode.pagedRtl,
        activeEntry,
        beginning,
        config.imageHost,
      );
      session = null;
      handle = null;
      final changes = _changes;
      if (changes != null) unawaited(changes.cancel());
      _retire(old);
      _current = request;
      _rememberPrefix(request);
      _pending = null;
      _changes = controller.changes.listen((_) {
        if (!_disposed && identical(_current, request)) {
          _reconcileNavigation();
          _rememberPrefix(request);
          setState(() {});
          _notifyStatus();
          if (controller.phase == NovelReaderNativePagedPhase.empty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _closeRetired();
            });
          }
        }
      });
      setState(() {
        _busy = false;
        _empty = false;
        _error = null;
      });
      _notifyStatus();
      _scheduleNavigation();
    } catch (error) {
      if (current()) {
        _stop(_current);
        setState(() {
          _busy = false;
          _error = error;
        });
        _notifyStatus();
      }
    } finally {
      session?.close();
      handle?.release();
      if (identical(_pending, token)) {
        _pending = null;
        token.cancel();
      }
    }
  }

  void _toggleCollapse(
    _LayoutRequest request,
    NovelReaderNativePageView view,
    ForumBodyTextPageFragment fragment,
  ) {
    if (!_live(request) ||
        !identical(request.controller.visibleView, view) ||
        _collapseIdentity != request.scope.chapter.identity) {
      return;
    }
    final header = fragment.collapseHeader;
    final fold = request.scope.collapses?.sections[header?.id];
    if (header == null ||
        fold == null ||
        header.titlePath != fold.title.path ||
        header.expanded != fold.expanded) {
      return;
    }
    final page = view.snapshot[view.pageIndex];
    final index = page.fragments.indexOf(fragment);
    final tablePath = page.table?.path;
    if (index < 0 &&
        (tablePath == null || !header.titlePath.startsWith('$tablePath/'))) {
      return;
    }

    final anchor = request.confirmed?.anchor;
    final location = anchor == null ? null : view.coverage.locate(anchor);
    final body = fold.body.source;
    final hidesLocation =
        fold.expanded &&
        switch (location) {
          NovelReaderNativeImageCoverage(:final path) => path.startsWith(
            '${fold.body.path}/',
          ),
          NovelReaderNativeCoveragePoint(:final sourceRune, :final affinity) =>
            affinity == HtmlProjectionAffinity.downstream
                ? sourceRune >= body.runeStart && sourceRune < body.runeEnd
                : sourceRune > body.runeStart && sourceRune <= body.runeEnd,
          null => false,
        };
    // A fold action changes the viewport only. If the old point disappears,
    // restore at actual coverage from the clicked title without saving it.
    _collapseRestoreHint = location != null && !hidesLocation
        ? location.anchor
        : view.coverage.locations
              .where((point) => point.fragmentIndex == index)
              .firstOrNull
              ?.anchor;
    final expanded = !fold.expanded;
    setState(() {
      if (expanded == fold.initiallyExpanded) {
        _collapseExpansion.remove(fold.id);
      } else {
        _collapseExpansion[fold.id] = expanded;
      }
      _selectionRevision++;
      _paintOnlyCandidate = false;
      _needsLayout = true;
      _busy = true;
    });
  }

  void _imageLayoutResolved(
    _LayoutRequest request,
    NovelReaderNativePageView view,
    ForumBodyPreparedImageFragment fragment,
    ForumHtmlImageLayout layout,
    ForumHtmlImageHost? host,
  ) {
    final input = fragment.content.input;
    if (!_live(request) ||
        !identical(host, widget.imageHost) ||
        !fragment.isActive ||
        request.scope.images?.owns(input) != true ||
        view.snapshot.layoutId != request.session.snapshot.layoutId ||
        _imageGeometryIdentity != input.identity) {
      return;
    }
    final path = input.element.path;
    final updated = updatedNovelReaderBlockImageLayout(
      input: input,
      resolved: layout,
      previous: _imageLayouts[path],
      isFloated: view.snapshot[view.pageIndex].fragments.any(
        (item) => item.isFloated && item.path == path,
      ),
    );
    if (updated == null) return;
    _imageLayouts[path] = updated;
    _imageReflowRequest = request;
    _scheduleImageReflow();
  }

  void _inlineImageLayoutResolved(
    _LayoutRequest request,
    NovelReaderNativePageView view,
    ForumBodyPreparedInlineFragment fragment,
    ForumBodyInlineImageBinding binding,
    ForumHtmlImageLayout layout,
    ForumHtmlImageHost? host,
  ) {
    final input = binding.input;
    final size = layout.displaySize;
    final catalog = request.scope.images;
    if (!_live(request) ||
        !identical(host, widget.imageHost) ||
        view.snapshot.layoutId != request.session.snapshot.layoutId ||
        !fragment.isActive ||
        !identical(fragment.view.images[binding.atomIndex], binding) ||
        catalog == null ||
        !catalog.ownsInline(input) ||
        _imageGeometryIdentity != input.identity ||
        !input.usesIntrinsicSize ||
        (input.image.isSticker && input.image.htmlSize != null) ||
        size == null ||
        !size.isFinite ||
        size.isEmpty) {
      return;
    }
    final key = input.image.cacheKey;
    final current =
        _inlineImageSizes[key] ??
        catalog.layoutFor(input.identity, input.element)?.displaySize;
    if (size == current) return;
    // Every occurrence can reuse the intrinsic size, but each page still owns
    // its own frozen frame and each occurrence keeps its own actual source.
    _inlineImageSizes[key] = size;
    _imageReflowRequest = request;
    _scheduleImageReflow();
  }

  void _scheduleImageReflow() {
    if (_imageReflowRequest == null || _imageReflowScheduled) return;
    _imageReflowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _imageReflowScheduled = false;
      final request = _imageReflowRequest;
      if (!mounted || _disposed || request == null) return;
      if (!_live(request)) {
        _imageReflowRequest = null;
        return;
      }
      // Reflow needs an actual visible anchor or a confirmed single-page body.
      // A decorative-only page in a longer chapter has no persisted position
      // to restore, so hold its sizes until a restorable page is confirmed.
      final position = request.confirmed;
      if (position == null ||
          (!position.anchor.hasCanonicalTextOffset &&
              (!position.isPageCountFinal || position.pageCount != 1))) {
        return;
      }
      _imageReflowRequest = null;
      setState(() {
        _selectionRevision++;
        _paintOnlyCandidate = false;
        _needsLayout = true;
        _busy = true;
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _confirmed(
    _LayoutRequest request,
    NovelReaderPaginationPosition position,
  ) {
    if (!_live(request)) return;
    _collapseRestoreHint = null;
    request.confirmed = position;
    _scheduleImageReflow();
    _closeRetired();
    if (_readyEpoch != _epoch) {
      _readyEpoch = _epoch;
      widget.onContentReady?.call();
    }
    if (!_live(request)) return;
    if (request.beginning) _beginningConsumed = true;
    final entry = request.entry;
    if (entry != null && _finishedEntry != _entryKey(entry)) {
      if (position.appliedChapterEntry == entry.edge) {
        _finishChapterEntry(
          entry,
          applied: true,
          callback: widget.onChapterEntryApplied,
        );
      } else if (position.hasUserNavigated) {
        _finishChapterEntry(
          entry,
          applied: false,
          callback: widget.onChapterEntryRetired,
        );
      }
    }
    if (!_live(request)) return;
    final intent = _navigationIntent;
    if (intent != null &&
        identical(intent.controller, request.controller) &&
        intent.revision == request.controller.navigationRevision) {
      if (intent.input.anchor != null &&
          request.controller.unavailableAnchorRevision == intent.revision) {
        _finishNavigation(NovelReaderNavigationOutcome.unavailable);
      } else if (position.hasUserNavigated && intent.input.matches(position)) {
        _finishNavigation(NovelReaderNavigationOutcome.arrived);
      }
    }
    widget.onPositionChanged?.call(position);
    _notifyStatus();
  }

  void _retire(_LayoutRequest? request) {
    if (request == null || request.closed) return;
    _stop(request);
    request.parent.cancel();
    _retired.add(request);
    if (request.tryClose()) {
      _retired.remove(request);
      return;
    }
    request.releaseEvents ??= request.session.layoutBudgetChanges.listen(
      (_) => _reap(),
      onDone: _reap,
    );
    _reap();
  }

  void _reap() {
    for (final request in _retired.toList(growable: false)) {
      if (request.tryClose()) _retired.remove(request);
    }
  }

  void _closeRetired() {
    for (final request in _retired) {
      request.close();
    }
    _retired.clear();
  }

  void _resetCollapses() {
    _collapseIdentity = null;
    _collapseExpansion.clear();
    _collapseRestoreHint = null;
  }

  void _closeAll() {
    _resetCollapses();
    _imageGeometryIdentity = null;
    _imageLayouts.clear();
    _inlineImageSizes.clear();
    _imageReflowRequest = null;
    _chapterHintChanged(null);
    _finishNavigation(NovelReaderNavigationOutcome.retired);
    _navigationFrameRevision++;
    final changes = _changes;
    _changes = null;
    if (changes != null) unawaited(changes.cancel());
    _pending?.cancel();
    _pending = null;
    _current?.close();
    _current = null;
    _closeRetired();
    _verifiedPrefix = null;
    _prefixKey = null;
    _prefixOwner = null;
  }

  void _rememberPrefix(_LayoutRequest request) {
    final prefix = request.controller.snapshot ?? request.prefix;
    if (prefix == null) return;
    if (_prefixKey != request.scope.paginationKey ||
        !identical(_prefixOwner, request.owner)) {
      _prefixKey = request.scope.paginationKey;
      _prefixOwner = request.owner;
      _verifiedPrefix = prefix;
    } else if (prefix.length > (_verifiedPrefix?.length ?? 0)) {
      _verifiedPrefix = prefix;
    }
  }

  void _stop(_LayoutRequest? request) {
    if (request == null) return;
    if (identical(request, _current)) _chapterHintChanged(null);
    if (identical(_navigationIntent?.controller, request.controller)) {
      _finishNavigation(NovelReaderNavigationOutcome.retired);
    }
    _rememberPrefix(request);
    request.stop();
  }

  static (int, String, NovelReaderChapterEdge)? _entryKey(
    NovelReaderChapterEntryRequest? entry,
  ) => entry == null ? null : (entry.requestId, entry.episodeId, entry.edge);

  void _finishChapterEntry(
    NovelReaderChapterEntryRequest entry, {
    required bool applied,
    required ValueChanged<NovelReaderChapterEntryRequest>? callback,
  }) {
    final key = _entryKey(entry);
    if (_finishedEntry == key) return;
    _finishedEntry = key;
    if (callback == null || _disposed) return;
    final owner = widget.owner;
    final episode = widget.semanticDocument.episodeId;
    final authority = widget.readingAuthorityIdentity;
    final novelId = widget.progressSnapshot.novelId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _disposed ||
          owner.isClosed ||
          !identical(owner, widget.owner) ||
          !identical(authority, widget.readingAuthorityIdentity) ||
          novelId != widget.progressSnapshot.novelId ||
          episode != widget.semanticDocument.episodeId ||
          (applied && _entryKey(widget.chapterEntryRequest) != key)) {
        return;
      }
      callback(entry);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  static (int, String, String, int)? _pageSeekKey(
    NovelReaderPageSeekRequest? request,
  ) => request == null
      ? null
      : (
          request.requestId,
          request.episodeId,
          request.paginationKey,
          request.pageIndex,
        );

  static Object? _anchorNavigationKey(
    NovelReaderAnchorNavigationRequest? request,
  ) => request == null
      ? null
      : (
          request.requestId,
          request.anchor.episodeId,
          request.anchor.nodeId,
          request.anchor.textOffset,
          request.anchor.formatVersion,
          request.anchor.textIdentity,
        );

  Object? get _navigationKey {
    final key = _selectAnchorNavigation
        ? _anchorNavigationKey(widget.navigationRequest)
        : _pageSeekKey(widget.pageSeekRequest);
    return key == null ? null : (_selectAnchorNavigation, key);
  }

  _NativeNavigationInput? _navigationInput() {
    if (_selectAnchorNavigation) {
      final request = widget.navigationRequest;
      if (request == null) return null;
      final callback = widget.onNavigationFinished;
      return _NativeNavigationInput(
        anchor: request,
        callback: callback == null
            ? null
            : (outcome) => callback(request, outcome),
      );
    }
    final request = widget.pageSeekRequest;
    if (request == null) return null;
    final callback = widget.onPageSeekFinished;
    return _NativeNavigationInput(
      page: request,
      callback: callback == null
          ? null
          : (outcome) => callback(request, outcome),
    );
  }

  void _scheduleNavigation() {
    final key = _navigationKey;
    if (_disposed ||
        !_active ||
        _busy ||
        key == null ||
        _seenNavigation == key) {
      return;
    }
    final frame = ++_navigationFrameRevision;
    final epoch = _epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _disposed ||
          !_active ||
          _busy ||
          frame != _navigationFrameRevision ||
          epoch != _epoch ||
          _navigationKey != key) {
        return;
      }
      final request = _current;
      if (request?.controller.phase == NovelReaderNativePagedPhase.created) {
        _scheduleNavigation();
        return;
      }
      final input = _navigationInput();
      if (input == null) return;
      _seenNavigation = key;
      final controller = request?.controller;
      final available =
          request != null &&
          _live(request) &&
          controller != null &&
          !controller.isClosed;
      if (!available || !input.issue(controller)) {
        _reportNavigation(
          NovelReaderNavigationOutcome.unavailable,
          input.callback,
        );
        return;
      }
      _navigationIntent = _NativeNavigationIntent(
        input,
        controller,
        controller.navigationRevision,
        widget.owner,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _reconcileNavigation() {
    final intent = _navigationIntent;
    if (intent == null) return;
    if (!identical(_current?.controller, intent.controller) ||
        intent.controller.isClosed ||
        intent.controller.isSuspended ||
        intent.controller.navigationRevision != intent.revision) {
      _finishNavigation(NovelReaderNavigationOutcome.retired);
    } else if (intent.input.anchor != null &&
        intent.controller.unavailableAnchorRevision == intent.revision) {
      _finishNavigation(NovelReaderNavigationOutcome.unavailable);
    } else if (!intent.controller.hasPendingNavigation &&
        intent.controller.readyTarget == null) {
      _finishNavigation(NovelReaderNavigationOutcome.unavailable);
    }
  }

  void _finishNavigation(NovelReaderNavigationOutcome outcome) {
    final intent = _navigationIntent;
    _navigationIntent = null;
    if (intent != null) {
      _reportNavigation(outcome, intent.input.callback, owner: intent.owner);
    }
  }

  void _retireNavigationInput() {
    final key = _navigationKey;
    if (_navigationIntent != null) {
      _finishNavigation(NovelReaderNavigationOutcome.retired);
    } else if (key != null && _seenNavigation != key) {
      // Preparation can still be waiting before any controller accepts this
      // input. Activity loss, entry/retry retire that intent without replay too.
      final input = _navigationInput();
      if (input != null) {
        _reportNavigation(NovelReaderNavigationOutcome.retired, input.callback);
      }
    }
    _seenNavigation = key;
    _navigationFrameRevision++;
  }

  void _reportNavigation(
    NovelReaderNavigationOutcome outcome,
    ValueChanged<NovelReaderNavigationOutcome>? callback, {
    NovelReaderNativeOwner? owner,
  }) {
    if (_disposed || callback == null) return;
    final callbackOwner = owner ?? widget.owner;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_disposed &&
          !callbackOwner.isClosed &&
          identical(callbackOwner, widget.owner)) {
        callback(outcome);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _statusRevision++;
    widget.activity?.removeListener(_activityChanged);
    widget.owner.removeListener(_ownerChanged);
    _closeAll();
    super.dispose();
  }
}

final class _NativeNavigationIntent {
  const _NativeNavigationIntent(
    this.input,
    this.controller,
    this.revision,
    this.owner,
  );
  final _NativeNavigationInput input;
  final NovelReaderNativePagedController controller;
  final int revision;
  final NovelReaderNativeOwner owner;
}

final class _NativeNavigationInput {
  const _NativeNavigationInput({required this.callback, this.page, this.anchor})
    : assert((page == null) != (anchor == null));
  final NovelReaderPageSeekRequest? page;
  final NovelReaderAnchorNavigationRequest? anchor;
  final ValueChanged<NovelReaderNavigationOutcome>? callback;

  bool issue(NovelReaderNativePagedController controller) {
    final request = page;
    if (request == null) return controller.requestAnchor(anchor!.anchor);
    return controller.episodeId == request.episodeId &&
        controller.paginationKey == request.paginationKey &&
        request.pageIndex >= 0 &&
        request.pageIndex < (controller.snapshot?.length ?? 0) &&
        controller.requestPage(request.pageIndex);
  }

  bool matches(NovelReaderPaginationPosition position) {
    final request = page;
    if (request == null) return position.episodeId == anchor!.anchor.episodeId;
    return position.paginationKey == request.paginationKey &&
        position.episodeId == request.episodeId &&
        position.pageIndex == request.pageIndex;
  }
}

class _LayoutRequest {
  _LayoutRequest(
    this.scope,
    this.session,
    this.controller,
    this.handle,
    this.parent,
    this.owner,
    this.authority,
    this.epoch,
    this.reverse,
    this.entry,
    this.beginning,
    this.imageHost,
  );
  NovelReaderNativeLayoutScope scope;
  final ForumBodyTextPageSession session;
  final NovelReaderNativePagedController controller;
  final NovelReaderNativeCacheHandle handle;
  final NovelReaderPaginationCancellationToken parent;
  final NovelReaderNativeOwner owner;
  final Object authority;
  int epoch;
  bool reverse;
  final NovelReaderChapterEntryRequest? entry;
  final bool beginning;
  final ForumHtmlImageHost? imageHost;
  NovelReaderPaginationPosition? confirmed;
  ForumBodyTextPageSnapshot? prefix;
  StreamSubscription<int>? releaseEvents;
  bool closed = false;
  void stop() {
    prefix = controller.snapshot ?? prefix;
    controller.close();
  }

  bool tryClose() {
    if (session.activeIssuedLeases != 0 ||
        session.reservedViewLeases != 0 ||
        session.activeIssuedFragments != 0 ||
        session.reservedViewFragments != 0 ||
        session.activeIssuedTablePages != 0) {
      return false;
    }
    close();
    return true;
  }

  void close() {
    if (closed) return;
    closed = true;
    final events = releaseEvents;
    releaseEvents = null;
    if (events != null) unawaited(events.cancel());
    stop();
    parent.cancel();
    session.close();
    handle.release();
  }
}
