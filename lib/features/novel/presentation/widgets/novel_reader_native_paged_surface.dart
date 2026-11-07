import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:y300/features/fonts/fonts.dart' show ResolvedFont;
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_tap_zones.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../controllers/novel_reader_paged_navigation_controller.dart';
import '../models/novel_reader_anchor_navigation_request.dart';
import '../models/novel_reader_chapter_turn.dart';
import '../models/novel_reader_logical_selection_source.dart';
import '../models/novel_reader_native_host_status.dart';
import '../models/novel_reader_paged_indicator_layout.dart';
import '../models/novel_reader_pagination_exception.dart';
import '../models/novel_reader_pagination_position.dart';
import '../models/novel_reader_native_text_selection.dart';
import '../models/novel_reader_native_image_tap.dart';
import '../models/novel_reader_native_link_handler.dart';
import '../novel_text_resolver.dart';
import '../services/novel_reader_display_resolvers.dart';
import '../services/novel_reader_native_owner.dart';
import '../services/novel_reader_native_layout_scope.dart';
import '../services/novel_reader_native_preparation_service.dart';
import '../services/novel_reader_native_viewport_adapter.dart';
import '../services/novel_reader_pagination_performance_policy.dart';
import '../services/novel_reader_pagination_demand.dart';
import 'novel_reader_native_layout_host.dart';

/// Native paged reading shell. Its fixed footer never covers measured text or
/// changes body geometry when a hint, target wait or recovery action appears.
/// The reading page owns visibility, the cache owner and persistence callbacks.
class NovelReaderNativePagedSurface extends StatefulWidget {
  const NovelReaderNativePagedSurface({
    super.key,
    required this.owner,
    required this.episode,
    required this.rawHtml,
    required this.semanticDocument,
    required this.preferences,
    required this.resolvedFont,
    required this.progressSnapshot,
    required this.readingAuthorityIdentity,
    required this.preparationService,
    this.converter = const IdentityTextConverter(),
    this.imageHost,
    this.imagePolicy = defaultForumHtmlPreparationImagePolicy,
    this.imageCacheOwnerId,
    this.chromeInsets = const ReaderChromeInsets.zero(),
    this.active = true,
    this.activity,
    this.startsAtBeginning = false,
    this.conversionAnchor,
    this.navigationController,
    this.pageSeekRequest,
    this.onPageSeekFinished,
    this.navigationRequest,
    this.textHighlight,
    this.onNavigationFinished,
    this.chapterEntryRequest,
    this.onChapterEntryApplied,
    this.onChapterEntryRetired,
    this.previousChapterTitle,
    this.nextChapterTitle,
    this.onTurnToAdjacentChapter,
    this.chapterTurnIsInFlight = false,
    this.onPositionChanged,
    this.onContentReady,
    this.onContentTerminal,
    this.onScrollActivityChanged,
    this.onTextSelection,
    this.buildTextSelection,
    this.onLinkTap,
    this.onImageTap,
    this.onStatusChanged,
    this.onChooseScrollMode,
    this.performance = const NovelReaderPaginationPerformancePolicy(),
    this.idleScheduler,
  });

  final NovelReaderNativeOwner owner;
  final NovelEpisodeItem episode;
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
  final String? imageCacheOwnerId;
  final ReaderChromeInsets chromeInsets;
  final bool active;
  final ValueListenable<bool>? activity;
  final bool startsAtBeginning;
  final NovelReaderTextAnchor? conversionAnchor;
  final NovelReaderPagedNavigationController? navigationController;
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
  final NovelReaderChapterEntryRequest? chapterEntryRequest;
  final ValueChanged<NovelReaderChapterEntryRequest>? onChapterEntryApplied;
  final ValueChanged<NovelReaderChapterEntryRequest>? onChapterEntryRetired;
  final String? previousChapterTitle;
  final String? nextChapterTitle;
  final NovelReaderChapterTurnHandler? onTurnToAdjacentChapter;
  final bool chapterTurnIsInFlight;
  final ValueChanged<NovelReaderPaginationPosition>? onPositionChanged;
  final VoidCallback? onContentReady;
  final VoidCallback? onContentTerminal;
  final ValueChanged<bool>? onScrollActivityChanged;
  final ValueChanged<NovelReaderNativeTextSelection>? onTextSelection;
  final Widget Function(
    Object identity,
    NovelReaderLogicalSelectionSource? Function() readSource,
    Widget child,
  )?
  buildTextSelection;
  final NovelReaderNativeLinkHandler? onLinkTap;
  final ValueChanged<NovelReaderNativeImageTap>? onImageTap;
  final ValueChanged<NovelReaderNativeHostStatus>? onStatusChanged;
  final VoidCallback? onChooseScrollMode;
  final NovelReaderPaginationPerformancePolicy performance;
  final NovelReaderPaginationIdleScheduler? idleScheduler;

  @override
  State<NovelReaderNativePagedSurface> createState() =>
      _NativePagedSurfaceState();
}

class _NativePagedSurfaceState extends State<NovelReaderNativePagedSurface> {
  final _localNavigation = NovelReaderPagedNavigationController();
  NovelReaderNativeHostStatus? _status;
  NovelReaderPaginationPosition? _position;
  NovelReaderChapterTurnHint? _hint;
  int _retry = 0;
  bool _invalidWindow = false;
  int _windowRevision = 0;

  NovelReaderPagedNavigationController get _navigation =>
      widget.navigationController ?? _localNavigation;

  bool get _active => widget.active && (widget.activity?.value ?? true);

  @override
  void initState() {
    super.initState();
    widget.activity?.addListener(_activityChanged);
  }

  void _activityChanged() {
    if (!mounted) return;
    setState(() {
      if (!_active) _hint = null;
    });
  }

  @override
  void didUpdateWidget(covariant NovelReaderNativePagedSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.activity, widget.activity)) {
      oldWidget.activity?.removeListener(_activityChanged);
      widget.activity?.addListener(_activityChanged);
    }
    if (!identical(oldWidget.owner, widget.owner) ||
        oldWidget.episode.episodeId != widget.episode.episodeId ||
        oldWidget.rawHtml != widget.rawHtml ||
        !identical(
          oldWidget.readingAuthorityIdentity,
          widget.readingAuthorityIdentity,
        )) {
      _position = null;
      _status = null;
      _hint = null;
      _retry = 0;
      _invalidWindow = false;
      _windowRevision++;
    }
    if (!_active) _hint = null;
  }

  void _reportInvalidWindow() {
    if (_invalidWindow) return;
    _invalidWindow = true;
    final revision = ++_windowRevision;
    final owner = widget.owner;
    final authority = widget.readingAuthorityIdentity;
    final episode = widget.episode.episodeId;
    bool current() =>
        mounted &&
        _invalidWindow &&
        revision == _windowRevision &&
        identical(owner, widget.owner) &&
        !owner.isClosed &&
        identical(authority, widget.readingAuthorityIdentity) &&
        episode == widget.episode.episodeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!current()) return;
      const status = NovelReaderNativeHostStatus(
        phase: NovelReaderNativeHostPhase.failed,
        hasVisiblePage: false,
        isRetainingPreviousLayout: false,
        pageCount: 0,
        isPageCountFinal: false,
        error: NovelReaderNativeLayoutInputException(
          NovelReaderNativeLayoutInputFailure.geometry,
        ),
      );
      setState(() => _status = status);
      widget.onStatusChanged?.call(status);
      if (current()) widget.onContentTerminal?.call();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: widget.preferences,
      theme: theme,
    );
    final label = theme.textTheme.labelMedium ?? const TextStyle(fontSize: 12);
    final scaler = MediaQuery.textScalerOf(context);
    final footerHeight = math.max(
      kMinInteractiveDimension,
      math.max(
        scaler.scale(label.fontSize ?? 12) * (label.height ?? 1.2) +
            NovelReaderChapterTurnHintLayout.verticalPadding * 2,
        widget.preferences.showProgressIndicator
            ? math.max(
                widget.chromeInsets.pageIndicatorReservedHeight,
                NovelReaderPagedIndicatorLayout.reservedHeight(scaler),
              )
            : 0,
      ),
    );
    if (!widget.preferences.viewport.isValid) {
      _reportInvalidWindow();
      return ColoredBox(
        color: palette.background,
        child: Center(
          child: Text(
            l10n.novelPagedWindowUnavailable,
            style: TextStyle(color: palette.foreground),
          ),
        ),
      );
    }
    final viewport = resolveNovelReaderNativeViewport(widget.preferences);
    final position = _position;
    final page = position?.pageIndex;
    final count = _status?.pageCount ?? _position?.pageCount ?? 0;
    final isFinal =
        _status?.isPageCountFinal ?? _position?.isPageCountFinal ?? false;
    final total = isFinal ? l10n.novelPages(count) : l10n.novelPageCountPending;
    final canNavigate =
        _active &&
        _status?.hasVisiblePage == true &&
        _status?.controller != null &&
        _status?.isRetainingPreviousLayout == false;
    final owner = widget.owner;
    final authority = widget.readingAuthorityIdentity;
    final episode = widget.episode.episodeId;
    final document = widget.semanticDocument;
    final rawHtml = widget.rawHtml;
    final controller = _status?.controller;
    final view = controller?.visibleView;
    final showTableNavigation =
        page != null &&
        view != null &&
        view.pageIndex == page &&
        view.snapshot[view.pageIndex].table != null;
    bool currentContent() =>
        mounted &&
        _active &&
        identical(owner, widget.owner) &&
        identical(authority, widget.readingAuthorityIdentity) &&
        episode == widget.episode.episodeId &&
        identical(document, widget.semanticDocument) &&
        rawHtml == widget.rawHtml;
    void turnCurrentPage(bool forward) {
      // A late accessibility action must not follow a shared command port into
      // a new owner/layout or a different actually confirmed page.
      if (!currentContent() ||
          !identical(position, _position) ||
          !identical(controller, _status?.controller) ||
          _status?.isRetainingPreviousLayout != false) {
        return;
      }
      if (forward) {
        _navigation.turnNext();
      } else {
        _navigation.turnPrevious();
      }
    }

    final error = _status?.error;
    final retry = _retry;
    void recover(bool retryLayout) {
      if (!currentContent() ||
          error == null ||
          !identical(error, _status?.error) ||
          retry != _retry) {
        return;
      }
      if (retryLayout) {
        setState(() => _retry++);
      } else {
        widget.onChooseScrollMode?.call();
      }
    }

    final title = NovelTextResolver.chapterTitle(
      l10n,
      widget.episode.episodeTitle,
      widget.episode.sourceTid,
    );
    return ColoredBox(
      color: palette.background,
      child: Semantics(
        key: const Key('novel-reader-native-paged-semantics'),
        container: true,
        explicitChildNodes: true,
        label: page == null
            ? null
            : l10n.novelPageSemantics(title, page + 1, total),
        value: page == null ? null : l10n.novelPageValue(page + 1, total),
        increasedValue:
            canNavigate && page != null && (page + 1 < count || !isFinal)
            ? l10n.novelNextPageSemantics(page + 2)
            : null,
        decreasedValue: canNavigate && page != null && page > 0
            ? l10n.novelPreviousPageSemantics(page)
            : null,
        onIncrease:
            canNavigate && page != null && (page + 1 < count || !isFinal)
            ? () => turnCurrentPage(true)
            : null,
        onDecrease: canNavigate && page != null && page > 0
            ? () => turnCurrentPage(false)
            : null,
        child: Padding(
          key: const Key('novel-reader-native-paged-surface'),
          padding: EdgeInsets.fromLTRB(
            viewport.left,
            viewport.top + widget.chromeInsets.topInset,
            viewport.right,
            viewport.bottom + widget.chromeInsets.persistentBottomInset,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (!constraints.hasBoundedWidth ||
                  !constraints.hasBoundedHeight) {
                _reportInvalidWindow();
                return Text(
                  l10n.novelPagedWindowUnavailable,
                  style: TextStyle(color: palette.foreground),
                );
              }
              if (_invalidWindow) {
                _invalidWindow = false;
                _windowRevision++;
              }
              final box = resolveNovelReaderNativePageBox(
                widget.preferences,
                availableWidth: constraints.maxWidth,
                maximumWidth: viewport.maximumWidth,
                scaledBodyFontSize: scaler.scale(widget.preferences.fontSize),
              );
              final footer = math.min(footerHeight, constraints.maxHeight);
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: box.width,
                  height: constraints.maxHeight,
                  child: Column(
                    children: [
                      Expanded(
                        child: _withTextSelection(
                          NovelReaderNativeLayoutHost(
                            columns: box.columns,
                            owner: widget.owner,
                            sourceId: widget.episode.episodeId,
                            rawHtml: widget.rawHtml,
                            semanticDocument: widget.semanticDocument,
                            preferences: widget.preferences,
                            resolvedFont: widget.resolvedFont,
                            progressSnapshot: widget.progressSnapshot,
                            readingAuthorityIdentity:
                                widget.readingAuthorityIdentity,
                            preparationService: widget.preparationService,
                            converter: widget.converter,
                            imageHost: widget.imageHost,
                            imagePolicy: widget.imagePolicy,
                            imageThreadId: widget.episode.sourceTid,
                            imageCacheOwnerId:
                                widget.imageCacheOwnerId ??
                                widget.episode.sourceTid,
                            active: widget.active,
                            activity: widget.activity,
                            onTextSelection: widget.onTextSelection,
                            onLinkTap: widget.onLinkTap,
                            onImageTap: widget.onImageTap,
                            startsAtBeginning: widget.startsAtBeginning,
                            conversionAnchor: widget.conversionAnchor,
                            navigationController: _navigation,
                            pageSeekRequest: widget.pageSeekRequest,
                            onPageSeekFinished: widget.onPageSeekFinished,
                            navigationRequest: widget.navigationRequest,
                            textHighlight: widget.textHighlight,
                            onNavigationFinished: widget.onNavigationFinished,
                            chapterEntryRequest: widget.chapterEntryRequest,
                            onChapterEntryApplied: widget.onChapterEntryApplied,
                            onChapterEntryRetired: widget.onChapterEntryRetired,
                            previousChapterTitle: widget.previousChapterTitle,
                            nextChapterTitle: widget.nextChapterTitle,
                            onTurnToAdjacentChapter:
                                widget.onTurnToAdjacentChapter,
                            chapterTurnIsInFlight: widget.chapterTurnIsInFlight,
                            onChapterTurnHintChanged: (hint) {
                              if (_hint != hint) setState(() => _hint = hint);
                            },
                            onPositionChanged: (position) {
                              setState(() => _position = position);
                              widget.onPositionChanged?.call(position);
                            },
                            onStatusChanged: (status) {
                              setState(() => _status = status);
                              widget.onStatusChanged?.call(status);
                            },
                            onContentReady: widget.onContentReady,
                            onContentTerminal: widget.onContentTerminal,
                            onScrollActivityChanged:
                                widget.onScrollActivityChanged,
                            retryRevision: _retry,
                            performance: widget.performance,
                            idleScheduler: widget.idleScheduler,
                            placeholderBuilder: (context, status) => Center(
                              child:
                                  status.phase ==
                                      NovelReaderNativeHostPhase.empty
                                  ? Text(
                                      l10n.novelPagedNoContent,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: palette.foreground,
                                      ),
                                    )
                                  : Icon(
                                      status.error != null
                                          ? Icons.warning_amber_outlined
                                          : Icons.hourglass_empty,
                                      color: palette.muted,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: footer.toDouble(),
                        child: _NativePagedFooter(
                          palette: palette,
                          status: _status,
                          hint: _hint,
                          page: page,
                          count: count,
                          isFinal: isFinal,
                          showIndicator:
                              widget.preferences.showProgressIndicator,
                          showTableNavigation: showTableNavigation,
                          reverse:
                              widget.preferences.flowMode ==
                              NovelReaderFlowMode.pagedRtl,
                          onTablePrevious:
                              showTableNavigation &&
                                  canNavigate &&
                                  (page > 0 ||
                                      widget.previousChapterTitle != null)
                              ? () => turnCurrentPage(false)
                              : null,
                          onTableNext:
                              showTableNavigation &&
                                  canNavigate &&
                                  (page + 1 < count ||
                                      !isFinal ||
                                      widget.nextChapterTitle != null)
                              ? () => turnCurrentPage(true)
                              : null,
                          active: _active,
                          onRetry: () => recover(true),
                          onChooseScrollMode: widget.onChooseScrollMode == null
                              ? null
                              : () => recover(false),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  NovelReaderLogicalSelectionSource? _readSelectionSource() {
    final status = _status;
    return status?.isRetainingPreviousLayout == false
        ? status?.controller?.logicalSelectionSource
        : null;
  }

  Widget _withTextSelection(Widget child) =>
      widget.buildTextSelection?.call(
        (
          widget.readingAuthorityIdentity,
          _status?.controller,
          _position?.pageIndex,
        ),
        _readSelectionSource,
        child,
      ) ??
      child;

  @override
  void dispose() {
    widget.activity?.removeListener(_activityChanged);
    _localNavigation.dispose();
    super.dispose();
  }
}

String _statusMessage(
  AppLocalizations l10n,
  NovelReaderNativeHostStatus status,
) => switch (status.error) {
  NovelReaderPaginationException(code: 'backgroundPaginationIdle') =>
    l10n.novelPagedBackgroundPaused,
  NovelReaderPaginationException(code: 'targetPageWaitExceeded') =>
    l10n.novelPagedWaitTimedOut,
  null => l10n.novelPagedWaitingForPage,
  _ => l10n.novelPagedLayoutFailed,
};

class _NativePagedFooter extends StatelessWidget {
  const _NativePagedFooter({
    required this.palette,
    required this.status,
    required this.hint,
    required this.page,
    required this.count,
    required this.isFinal,
    required this.showIndicator,
    required this.showTableNavigation,
    required this.reverse,
    required this.onTablePrevious,
    required this.onTableNext,
    required this.active,
    required this.onRetry,
    required this.onChooseScrollMode,
  });
  final NovelReaderNativeHostStatus? status;
  final NovelReaderPalette palette;
  final NovelReaderChapterTurnHint? hint;
  final int? page;
  final int count;
  final bool isFinal;
  final bool showIndicator;
  final bool showTableNavigation;
  final bool reverse;
  final VoidCallback? onTablePrevious;
  final VoidCallback? onTableNext;
  final bool active;
  final VoidCallback onRetry;
  final VoidCallback? onChooseScrollMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = status?.error != null;
    final waiting =
        status == null ||
        status!.phase == NovelReaderNativeHostPhase.preparing ||
        status!.controller?.hasPendingNavigation == true;
    final message = hint != null && !error
        ? NovelTextResolver.chapterTurnHint(l10n, hint!)
        : error || waiting
        ? _statusMessage(
            l10n,
            status ??
                const NovelReaderNativeHostStatus(
                  phase: NovelReaderNativeHostPhase.preparing,
                  hasVisiblePage: false,
                  isRetainingPreviousLayout: false,
                  pageCount: 0,
                  isPageCountFinal: false,
                ),
          )
        : '';
    final actions = <Widget>[
      IconButton(
        key: const Key('novel-reader-pagination-retry'),
        tooltip: l10n.commonRetry,
        onPressed: active ? onRetry : null,
        icon: const Icon(Icons.refresh),
        color: palette.foreground,
        disabledColor: palette.muted,
      ),
      if (onChooseScrollMode != null)
        IconButton(
          key: const Key('novel-reader-pagination-fallback'),
          tooltip: l10n.novelReturnToScroll,
          onPressed: active ? onChooseScrollMode : null,
          icon: const Icon(Icons.view_agenda_outlined),
          color: palette.foreground,
          disabledColor: palette.muted,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: Row(
          key: const Key('novel-reader-native-footer'),
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  message,
                  key: Key(
                    error
                        ? 'novel-reader-pagination-paused'
                        : hint != null
                        ? 'novel-reader-chapter-turn-hint-text'
                        : 'novel-reader-native-status',
                  ),
                  style:
                      (Theme.of(context).textTheme.labelMedium ??
                              const TextStyle(fontSize: 12))
                          .copyWith(color: palette.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (showTableNavigation)
              SizedBox(
                width: math.min(
                  kMinInteractiveDimension * 2,
                  constraints.maxWidth,
                ),
                child: ReaderOwnedTapRegion(
                  child: Row(
                    textDirection: reverse
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      Expanded(
                        child: IconButton(
                          key: const Key('novel-reader-table-previous'),
                          tooltip: l10n.novelTablePreviousPage,
                          onPressed: onTablePrevious,
                          icon: Icon(
                            reverse ? Icons.chevron_right : Icons.chevron_left,
                          ),
                          color: palette.foreground,
                          disabledColor: palette.muted,
                        ),
                      ),
                      Expanded(
                        child: IconButton(
                          key: const Key('novel-reader-table-next'),
                          tooltip: l10n.novelTableNextPage,
                          onPressed: onTableNext,
                          icon: Icon(
                            reverse ? Icons.chevron_left : Icons.chevron_right,
                          ),
                          color: palette.foreground,
                          disabledColor: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (error)
              SizedBox(
                width: math.min(
                  kMinInteractiveDimension * actions.length,
                  showTableNavigation
                      ? math.max(
                          0,
                          constraints.maxWidth - 2 * kMinInteractiveDimension,
                        )
                      : constraints.maxWidth,
                ),
                child: Row(
                  children: [
                    for (final action in actions) Expanded(child: action),
                  ],
                ),
              )
            else if (showIndicator && page != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .45,
                ),
                child: Align(
                  alignment: Alignment.bottomRight,
                  widthFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: NovelReaderPagedIndicatorLayout.rightInset,
                      bottom: NovelReaderPagedIndicatorLayout.bottomInset,
                    ),
                    child: Text(
                      l10n.novelPageIndicator(
                        page! + 1,
                        isFinal ? '$count' : l10n.novelPageCountPending,
                      ),
                      key: const Key('novel-reader-page-indicator-text'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (Theme.of(context).textTheme.labelSmall ??
                                  const TextStyle())
                              .copyWith(
                                fontSize:
                                    NovelReaderPagedIndicatorLayout.fontSize,
                                height:
                                    NovelReaderPagedIndicatorLayout.lineHeight,
                                letterSpacing: 0,
                                color: palette.muted,
                              ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
