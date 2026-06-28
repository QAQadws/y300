import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_layout_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_layout_request.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_document_view.dart';

class NovelReaderPagedSurfaceController extends ChangeNotifier {
  final NovelReaderProgressPolicy _progressPolicy =
      const NovelReaderProgressPolicy();

  _NovelReaderPagedSurfaceState? _state;
  NovelReaderPageLayout? _currentLayout;
  NovelReaderLayoutKey? _currentLayoutKey;
  int _currentPageIndex = 0;
  int _currentPageCount = 1;
  bool _isResolving = false;
  _PendingPagedAction? _pendingAction;

  NovelReaderPageLayout? get currentLayout => _currentLayout;

  NovelReaderLayoutKey? get currentLayoutKey => _currentLayoutKey;

  int get currentPageIndex => _currentPageIndex;

  int get currentPageCount => _currentPageCount;

  bool get isResolving => _isResolving;

  void _attach(_NovelReaderPagedSurfaceState state) {
    _state = state;
  }

  void _detach(_NovelReaderPagedSurfaceState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  void reset() {
    _pendingAction = null;
    _setPublicState(
      layout: null,
      layoutKey: null,
      pageIndex: 0,
      pageCount: 1,
      isResolving: false,
    );
  }

  Future<void> jumpToPage(int pageIndex) async {
    final state = _state;
    if (state == null || !_canDriveLayout(state)) {
      _pendingAction = _PendingPageIndexAction(pageIndex);
      return;
    }
    await state._jumpToPage(pageIndex);
  }

  Future<void> jumpToAnchor(NovelReaderTextAnchor anchor) async {
    final state = _state;
    if (state == null || !_canDriveLayout(state)) {
      _pendingAction = _PendingAnchorAction(anchor);
      return;
    }
    await state._jumpToAnchor(anchor);
  }

  Future<void> goPreviousOrEdge(
    Future<void> Function() onEpisodeEdge,
  ) async {
    final state = _state;
    if (state == null || !_canDriveLayout(state)) {
      return;
    }
    await state._goPreviousOrEdge(onEpisodeEdge);
  }

  Future<void> goNextOrEdge(
    Future<void> Function() onEpisodeEdge,
  ) async {
    final state = _state;
    if (state == null || !_canDriveLayout(state)) {
      return;
    }
    await state._goNextOrEdge(onEpisodeEdge);
  }

  NovelReaderProgressSnapshot? buildVisibleProgressSnapshot({
    required String novelId,
    required String episodeId,
    required NovelReaderFlowMode flowMode,
  }) {
    final layout = _currentLayout;
    if (layout == null) {
      return null;
    }
    return _progressPolicy.pagedSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: flowMode,
      pageIndex: _currentPageIndex,
      layout: layout,
    );
  }

  NovelReaderTextAnchor? currentAnchor({
    required String episodeId,
  }) {
    final layout = _currentLayout;
    if (layout == null) {
      return null;
    }
    final pageIndex = layout.clampPageIndex(_currentPageIndex);
    return NovelReaderTextAnchor(
      episodeId: episodeId,
      nodeId: layout.anchorForPage(pageIndex),
      pageIndex: pageIndex,
      progressPercent:
          layout.pageCount <= 1 ? 0 : pageIndex / (layout.pageCount - 1),
    );
  }

  bool _canDriveLayout(_NovelReaderPagedSurfaceState state) {
    return _currentLayout != null && !_isResolving && state._hasVisibleLayout;
  }

  void _setPublicState({
    required NovelReaderPageLayout? layout,
    required NovelReaderLayoutKey? layoutKey,
    required int pageIndex,
    required int pageCount,
    required bool isResolving,
  }) {
    final didChange = _currentLayout != layout ||
        _currentLayoutKey != layoutKey ||
        _currentPageIndex != pageIndex ||
        _currentPageCount != pageCount ||
        _isResolving != isResolving;
    _currentLayout = layout;
    _currentLayoutKey = layoutKey;
    _currentPageIndex = pageIndex;
    _currentPageCount = pageCount;
    _isResolving = isResolving;
    if (didChange) {
      notifyListeners();
    }
  }

  Future<void> _consumePendingAction(_NovelReaderPagedSurfaceState state) async {
    final pendingAction = _pendingAction;
    _pendingAction = null;
    if (pendingAction == null) {
      return;
    }
    await pendingAction.apply(state);
  }
}

abstract class _PendingPagedAction {
  Future<void> apply(_NovelReaderPagedSurfaceState state);
}

class _PendingPageIndexAction implements _PendingPagedAction {
  const _PendingPageIndexAction(this.pageIndex);

  final int pageIndex;

  @override
  Future<void> apply(_NovelReaderPagedSurfaceState state) {
    return state._jumpToPage(pageIndex);
  }
}

class _PendingAnchorAction implements _PendingPagedAction {
  const _PendingAnchorAction(this.anchor);

  final NovelReaderTextAnchor anchor;

  @override
  Future<void> apply(_NovelReaderPagedSurfaceState state) {
    return state._jumpToAnchor(anchor);
  }
}

class NovelReaderPagedSurface extends ConsumerStatefulWidget {
  const NovelReaderPagedSurface({
    super.key,
    required this.controller,
    required this.viewState,
    required this.typography,
    required this.backgroundColor,
    required this.imageHeaderBuilder,
    required this.onLinkTap,
    required this.onPageChanged,
    required this.onInteraction,
    required this.nodeKeyBuilder,
  });

  final NovelReaderPagedSurfaceController controller;
  final NovelReaderViewState viewState;
  final NovelReaderTypography typography;
  final Color backgroundColor;
  final ImageRequestHeaderBuilder imageHeaderBuilder;
  final ValueChanged<NovelReaderLink> onLinkTap;
  final Future<void> Function(int pageIndex, NovelReaderPageLayout layout) onPageChanged;
  final VoidCallback onInteraction;
  final Key Function(String nodeId) nodeKeyBuilder;

  @override
  ConsumerState<NovelReaderPagedSurface> createState() =>
      _NovelReaderPagedSurfaceState();
}

class _NovelReaderPagedSurfaceState extends ConsumerState<NovelReaderPagedSurface> {
  final NovelReaderProgressPolicy _progressPolicy =
      const NovelReaderProgressPolicy();
  final Set<PageController> _pendingPageControllerDisposals = <PageController>{};

  PageController? _pageController;
  NovelReaderLayoutRequest? _pendingRequest;
  NovelReaderLayoutKey? _activeRequestKey;
  NovelReaderPageLayout? _visibleLayout;
  NovelReaderLayoutKey? _visibleLayoutKey;
  int _requestSerial = 0;
  int _currentPageIndex = 0;
  int? _suppressedOnPageChangedIndex;

  bool get _hasVisibleLayout => _visibleLayout != null;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
  }

  @override
  void didUpdateWidget(covariant NovelReaderPagedSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final request = _buildRequest(constraints);
        _scheduleResolveIfNeeded(request);
        final activeKey = _activeRequestKey;
        final visibleKey = _visibleLayoutKey;
        final needsResolve = visibleKey != request.key;
        final sameContentIdentity = visibleKey != null &&
            visibleKey.hasSameContentIdentity(request.key);
        final visibleLayout = needsResolve
            ? (sameContentIdentity ? _visibleLayout : null)
            : _visibleLayout;
        final showLoading = visibleLayout == null;
        final showReflowMask = needsResolve && sameContentIdentity;
        final shouldShowProgressIndicator =
            activeKey == request.key || _pendingRequest?.key == request.key;
        return Stack(
          key: const Key('novel-reader-paged-surface'),
          children: [
            if (visibleLayout != null)
              Positioned.fill(
                child: _buildPagedView(visibleLayout),
              ),
            if (showLoading)
              Positioned.fill(
                child: ColoredBox(
                  key: const Key('novel-reader-paged-layout-loading'),
                  color: widget.backgroundColor,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            if (showReflowMask && shouldShowProgressIndicator)
              Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    key: const Key('novel-reader-paged-reflow-mask'),
                    color: widget.backgroundColor.withValues(alpha: 0.16),
                    child: const Center(
                      child: DecoratedBox(
                        key: Key('novel-reader-paged-reflow-indicator'),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  NovelReaderLayoutRequest _buildRequest(BoxConstraints constraints) {
    final preferences = widget.viewState.preferences;
    final contentMaxWidth = _safeContentMaxWidth(widget.typography.contentMaxWidth);
    final horizontalPadding = preferences.pagePadding * 2;
    final verticalPadding = preferences.pagePadding * 2;
    final availableWidth = (constraints.maxWidth - horizontalPadding)
        .clamp(160.0, contentMaxWidth)
        .toDouble();
    final availableHeight =
        (constraints.maxHeight - verticalPadding).clamp(160.0, 10000.0).toDouble();
    final bodyFontSize = widget.typography.body.fontSize ?? preferences.fontSize;
    final bodyLineHeight = widget.typography.body.height ?? preferences.lineHeight;
    final headingFontSize =
        widget.typography.chapterTitle.fontSize ?? preferences.fontSize + 4;
    final headingLineHeight =
        widget.typography.chapterTitle.height ?? preferences.lineHeight;
    final firstPageReservedHeight = preferences.showChapterTitle
        ? headingFontSize * headingLineHeight + preferences.paragraphSpacing * 1.6
        : 0.0;
    return NovelReaderLayoutRequest(
      episodeId: widget.viewState.currentEpisode.episodeId,
      rawHtmlHash: widget.viewState.document.rawHtmlHash,
      document: widget.viewState.document,
      viewport: NovelReaderViewport(
        width: availableWidth,
        height: availableHeight,
      ),
      metrics: NovelReaderPaginationMetrics(
        bodyFontSize: bodyFontSize,
        bodyLineHeight: bodyLineHeight,
        headingFontSize: headingFontSize,
        headingLineHeight: headingLineHeight,
        paragraphSpacing: preferences.paragraphSpacing,
        firstPageReservedHeight: firstPageReservedHeight,
      ),
      pagePadding: preferences.pagePadding,
      contentMaxWidth: contentMaxWidth,
      fontWeight: preferences.fontWeight,
      fontFamily: preferences.fontFamily,
      textAlign: preferences.textAlign.storageValue,
      firstLineIndent: preferences.firstLineIndent,
      showChapterTitle: preferences.showChapterTitle,
    );
  }

  void _scheduleResolveIfNeeded(NovelReaderLayoutRequest request) {
    final requestKey = request.key;
    if (_visibleLayoutKey == requestKey || _activeRequestKey == requestKey) {
      return;
    }
    if (_pendingRequest?.key == requestKey) {
      return;
    }
    _pendingRequest = request;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingRequest = _pendingRequest;
      if (!mounted || pendingRequest == null) {
        return;
      }
      if (_visibleLayoutKey == pendingRequest.key ||
          _activeRequestKey == pendingRequest.key) {
        _pendingRequest = null;
        return;
      }
      _pendingRequest = null;
      unawaited(_resolveLayout(pendingRequest));
    });
  }

  Future<void> _resolveLayout(NovelReaderLayoutRequest request) async {
    final requestKey = request.key;
    final isSameContentIdentity = _visibleLayoutKey != null &&
        _visibleLayoutKey!.hasSameContentIdentity(requestKey);
    final serial = ++_requestSerial;
    _activeRequestKey = requestKey;
    if (isSameContentIdentity && _visibleLayout != null) {
      widget.controller._setPublicState(
        layout: _visibleLayout,
        layoutKey: _visibleLayoutKey,
        pageIndex: _currentPageIndex,
        pageCount: _visibleLayout!.pageCount,
        isResolving: true,
      );
    } else {
      widget.controller._setPublicState(
        layout: null,
        layoutKey: null,
        pageIndex: 0,
        pageCount: 1,
        isResolving: true,
      );
    }
    setState(() {});
    try {
      final layout = await ref.read(novelReaderLayoutServiceProvider).resolve(request);
      if (!mounted || serial != _requestSerial || _activeRequestKey != requestKey) {
        return;
      }
      _applyResolvedLayout(request, layout);
    } catch (_) {
      if (!mounted || serial != _requestSerial || _activeRequestKey != requestKey) {
        return;
      }
      _activeRequestKey = null;
      widget.controller._setPublicState(
        layout: _visibleLayout,
        layoutKey: _visibleLayoutKey,
        pageIndex: _currentPageIndex,
        pageCount: _visibleLayout?.pageCount ?? 1,
        isResolving: false,
      );
      setState(() {});
    }
  }

  void _applyResolvedLayout(
    NovelReaderLayoutRequest request,
    NovelReaderPageLayout layout,
  ) {
    final targetPageIndex = _targetPageIndexForResolvedLayout(layout);
    final oldController = _pageController;
    _pageController = PageController(initialPage: targetPageIndex);
    _visibleLayout = layout;
    _visibleLayoutKey = request.key;
    _activeRequestKey = null;
    _currentPageIndex = targetPageIndex;
    if (oldController != null) {
      _disposePageControllerAfterFrame(oldController);
    }
    widget.controller._setPublicState(
      layout: layout,
      layoutKey: request.key,
      pageIndex: targetPageIndex,
      pageCount: layout.pageCount,
      isResolving: false,
    );
    if (mounted) {
      setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(widget.controller._consumePendingAction(this));
    });
  }

  int _targetPageIndexForResolvedLayout(NovelReaderPageLayout layout) {
    final pendingAction = widget.controller._pendingAction;
    if (pendingAction case _PendingPageIndexAction()) {
      return layout.clampPageIndex(pendingAction.pageIndex);
    }
    if (pendingAction case _PendingAnchorAction()) {
      final anchorIndex = layout.pageIndexForAnchor(pendingAction.anchor.nodeId);
      return layout.clampPageIndex(
        anchorIndex >= 0 ? anchorIndex : pendingAction.anchor.pageIndex,
      );
    }
    final visibleLayout = _visibleLayout;
    final visibleKey = _visibleLayoutKey;
    final nextKey = layout.document.rawHtmlHash;
    if (visibleLayout != null &&
        visibleKey != null &&
        visibleKey.rawHtmlHash == nextKey &&
        visibleKey.episodeId == layout.document.episodeId) {
      final snapshot = NovelReaderProgressSnapshot(
        novelId: widget.viewState.progressSnapshot.novelId,
        episodeId: widget.viewState.progressSnapshot.episodeId,
        flowMode: widget.viewState.preferences.flowMode,
        scrollOffset: 0,
        pageIndex: _currentPageIndex,
        anchorNodeId: visibleLayout.anchorForPage(_currentPageIndex),
        progressPercent: visibleLayout.pageCount <= 1
            ? 0
            : _currentPageIndex / (visibleLayout.pageCount - 1),
      );
      return _progressPolicy.restorePageIndex(snapshot, layout: layout);
    }
    return _progressPolicy.restorePageIndex(
      widget.viewState.progressSnapshot,
      layout: layout,
    );
  }

  Widget _buildPagedView(NovelReaderPageLayout layout) {
    return PageView.builder(
      key: const Key('novel-reader-paged-view'),
      controller: _pageController,
      reverse: widget.viewState.preferences.flowMode == NovelReaderFlowMode.pagedRtl,
      itemCount: layout.pageCount,
      onPageChanged: (index) {
        if (_suppressedOnPageChangedIndex == index) {
          _suppressedOnPageChangedIndex = null;
          return;
        }
        _handleVisiblePageChanged(index, shouldPersist: true);
      },
      itemBuilder: (context, index) {
        return SingleChildScrollView(
          key: Key('novel-reader-page-$index'),
          padding: EdgeInsets.all(widget.viewState.preferences.pagePadding),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _safeContentMaxWidth(widget.typography.contentMaxWidth),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (index == 0 && widget.viewState.preferences.showChapterTitle) ...[
                    Text(
                      widget.viewState.currentEpisode.episodeTitle,
                      key: const Key('novel-reader-inline-chapter-title'),
                      style: widget.typography.chapterTitle,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(
                      height: widget.viewState.preferences.paragraphSpacing * 1.6,
                    ),
                  ],
                  NovelReaderDocumentView(
                    document: layout.documentForPage(index),
                    typography: widget.typography,
                    paragraphSpacing: widget.viewState.preferences.paragraphSpacing,
                    imageHeaderBuilder: widget.imageHeaderBuilder,
                    onLinkTap: widget.onLinkTap,
                    highlightedResult: widget.viewState.currentSearchResult,
                    nodeKeyBuilder: widget.nodeKeyBuilder,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _jumpToPage(int pageIndex) async {
    final layout = _visibleLayout;
    final controller = _pageController;
    if (layout == null || controller == null || !controller.hasClients) {
      widget.controller._pendingAction = _PendingPageIndexAction(pageIndex);
      return;
    }
    final target = layout.clampPageIndex(pageIndex);
    _suppressedOnPageChangedIndex = target;
    controller.jumpToPage(target);
    await _handleVisiblePageChanged(target, shouldPersist: true);
  }

  Future<void> _jumpToAnchor(NovelReaderTextAnchor anchor) async {
    final layout = _visibleLayout;
    if (layout == null) {
      widget.controller._pendingAction = _PendingAnchorAction(anchor);
      return;
    }
    final anchorIndex = layout.pageIndexForAnchor(anchor.nodeId);
    await _jumpToPage(anchorIndex >= 0 ? anchorIndex : anchor.pageIndex);
  }

  Future<void> _goPreviousOrEdge(
    Future<void> Function() onEpisodeEdge,
  ) async {
    final layout = _visibleLayout;
    if (layout == null) {
      return;
    }
    final current = layout.clampPageIndex(_currentPageIndex);
    if (current > 0) {
      await _jumpToPage(current - 1);
      return;
    }
    await onEpisodeEdge();
  }

  Future<void> _goNextOrEdge(
    Future<void> Function() onEpisodeEdge,
  ) async {
    final layout = _visibleLayout;
    if (layout == null) {
      return;
    }
    final current = layout.clampPageIndex(_currentPageIndex);
    if (current < layout.pageCount - 1) {
      await _jumpToPage(current + 1);
      return;
    }
    await onEpisodeEdge();
  }

  Future<void> _handleVisiblePageChanged(
    int pageIndex, {
    required bool shouldPersist,
  }) async {
    final layout = _visibleLayout;
    if (layout == null) {
      return;
    }
    final clamped = layout.clampPageIndex(pageIndex);
    _currentPageIndex = clamped;
    widget.controller._setPublicState(
      layout: layout,
      layoutKey: _visibleLayoutKey,
      pageIndex: clamped,
      pageCount: layout.pageCount,
      isResolving: _activeRequestKey != null,
    );
    widget.onInteraction();
    if (!shouldPersist) {
      return;
    }
    await widget.onPageChanged(clamped, layout);
  }

  void _disposePageControllerAfterFrame(PageController controller) {
    if (!_pendingPageControllerDisposals.add(controller)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingPageControllerDisposals.remove(controller);
      controller.dispose();
    });
  }

  double _safeContentMaxWidth(double value) {
    return value < 160 ? 160 : value;
  }
}
