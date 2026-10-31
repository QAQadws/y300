import 'dart:async';

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/widgets.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../controllers/novel_reader_native_paged_controller.dart';
import '../controllers/novel_reader_paged_navigation_controller.dart';
import '../models/novel_reader_chapter_turn.dart';
import '../models/novel_reader_native_page_view.dart';
import '../models/novel_reader_pagination_position.dart';

/// Native page mounting and gesture boundary. The Host owns controllers,
/// sessions and the paragraph cache, and supplies loading/recovery chrome.
///
/// A new layout/reading authority requires a new controller. Reflow within the
/// same owner retains the old mounted box until a replacement is ready. An
/// owner change removes it immediately, even while the new target is loading.
/// Merely preparing, jumping to, or completing a page never confirms reading.
class NovelReaderNativePagedViewport extends StatefulWidget {
  const NovelReaderNativePagedViewport({
    super.key,
    required this.controller,
    required this.ownerIdentity,
    required this.readingAuthorityIdentity,
    this.reverse = false,
    this.active = true,
    this.backgroundColor,
    this.navigationController,
    this.onTurnToAdjacentChapter,
    this.chapterTurnIsInFlight = false,
    this.placeholder = const SizedBox.shrink(),
    this.onPositionChanged,
    this.onScrollActivityChanged,
  });

  final NovelReaderNativePagedController controller;
  final Object ownerIdentity;
  final Object readingAuthorityIdentity;
  final bool reverse;
  final bool active;
  final Color? backgroundColor;
  final NovelReaderPagedNavigationController? navigationController;
  final bool Function(NovelReaderChapterEdge)? onTurnToAdjacentChapter;
  final bool chapterTurnIsInFlight;
  final Widget placeholder;
  final ValueChanged<NovelReaderPaginationPosition>? onPositionChanged;
  final ValueChanged<bool>? onScrollActivityChanged;

  @override
  State<NovelReaderNativePagedViewport> createState() =>
      _NovelReaderNativePagedViewportState();
}

class _NovelReaderNativePagedViewportState
    extends State<NovelReaderNativePagedViewport> {
  StreamSubscription<void>? _changes;
  ({
    NovelReaderNativePagedController controller,
    double width,
    double height,
    int page,
    Color? background,
  })?
  _displayed;
  int _binding = 0;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant NovelReaderNativePagedViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerChanged = !identical(
      oldWidget.ownerIdentity,
      widget.ownerIdentity,
    );
    final authorityChanged = !identical(
      oldWidget.readingAuthorityIdentity,
      widget.readingAuthorityIdentity,
    );
    final controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );
    if ((ownerChanged || authorityChanged) && !controllerChanged) {
      throw StateError('Native viewport scope requires a new controller');
    }
    if (ownerChanged) _displayed = null;
    if (controllerChanged) {
      _binding++;
      _unbind();
      _bind();
    }
  }

  void _bind() {
    final controller = widget.controller;
    final binding = _binding;
    void changed() {
      if (!mounted || binding != _binding) return;
      setState(_selectDisplay);
    }

    _changes = controller.changes.listen((_) => changed(), onDone: changed);
    if (controller.phase == NovelReaderNativePagedPhase.created) {
      controller.start();
    }
    _selectDisplay();
  }

  void _selectDisplay() {
    final controller = widget.controller;
    if (!controller.isClosed &&
        controller.readyTarget?.view.isReady == true &&
        !identical(_displayed?.controller, controller)) {
      final snapshot = controller.snapshot!;
      _displayed = (
        controller: controller,
        width: snapshot.width,
        height: snapshot.height,
        page: controller.readyTarget!.pageIndex,
        background: widget.backgroundColor,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _displayed;
    if (displayed == null) return widget.placeholder;
    // Capture the box and initial page when offered: source failure/retirement
    // can remove the proposal or snapshot before the next Widget build.
    final frozen =
        !widget.active ||
        widget.controller.isSuspended ||
        !identical(displayed.controller, widget.controller);
    return _NativeLayoutViewport(
      key: ObjectKey(displayed.controller),
      controller: displayed.controller,
      width: displayed.width,
      height: displayed.height,
      initialPage: displayed.page,
      backgroundColor: displayed.background,
      frozen: frozen,
      reverse: widget.reverse,
      navigationController: widget.navigationController,
      onTurnToAdjacentChapter: widget.onTurnToAdjacentChapter,
      chapterTurnIsInFlight: widget.chapterTurnIsInFlight,
      placeholder: widget.placeholder,
      onScrollActivityChanged: (scrolling) {
        if (identical(displayed.controller, widget.controller)) {
          widget.onScrollActivityChanged?.call(widget.active && scrolling);
        }
      },
      onPositionChanged: (position) {
        if (identical(displayed.controller, widget.controller) && !frozen) {
          widget.onPositionChanged?.call(position);
        }
      },
    );
  }

  void _unbind() {
    final changes = _changes;
    _changes = null;
    if (changes != null) unawaited(changes.cancel());
  }

  @override
  void dispose() {
    _binding++;
    _unbind();
    super.dispose();
  }
}

class _NativeLayoutViewport extends StatefulWidget {
  const _NativeLayoutViewport({
    super.key,
    required this.controller,
    required this.width,
    required this.height,
    required this.initialPage,
    required this.backgroundColor,
    required this.frozen,
    required this.reverse,
    required this.navigationController,
    required this.onTurnToAdjacentChapter,
    required this.chapterTurnIsInFlight,
    required this.placeholder,
    required this.onPositionChanged,
    required this.onScrollActivityChanged,
  });
  final NovelReaderNativePagedController controller;
  final double width;
  final double height;
  final int initialPage;
  final Color? backgroundColor;
  final bool frozen;
  final bool reverse;
  final NovelReaderPagedNavigationController? navigationController;
  final bool Function(NovelReaderChapterEdge)? onTurnToAdjacentChapter;
  final bool chapterTurnIsInFlight;
  final Widget placeholder;
  final ValueChanged<NovelReaderPaginationPosition> onPositionChanged;
  final ValueChanged<bool> onScrollActivityChanged;

  @override
  State<_NativeLayoutViewport> createState() => _NativeLayoutViewportState();
}

class _NativeLayoutViewportState extends State<_NativeLayoutViewport>
    implements NovelReaderPagedNavigationTarget {
  late final PageController _pages;
  late final double _width;
  late final double _height;
  StreamSubscription<void>? _changes;
  final _mountedPages =
      <NovelReaderNativePageView, List<ForumBodyParagraphLease>>{};
  int _page = 0;
  int _frame = 0;
  bool _scrolling = false;
  bool _userDrag = false;
  bool _edgeIntent = false;
  bool _fits = false;
  int _activityRevision = 0;
  ScrollHoldController? _hold;
  NovelReaderPagedNavigationBinding? _navigationBinding;
  bool _chapterTurnRequested = false;

  @override
  void initState() {
    super.initState();
    _width = widget.width;
    _height = widget.height;
    _page = widget.initialPage;
    _pages = PageController(initialPage: _page, keepPage: false);
    _navigationBinding = widget.navigationController?.bind(this);
    _changes = widget.controller.changes.listen(
      (_) {
        if (!mounted) return;
        setState(() {});
        _afterFrame();
      },
      onDone: () {
        if (mounted) setState(() {});
      },
    );
    _afterFrame();
  }

  @override
  void didUpdateWidget(covariant _NativeLayoutViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.navigationController,
      widget.navigationController,
    )) {
      _navigationBinding?.dispose();
      _navigationBinding = widget.navigationController?.bind(this);
    }
    if (oldWidget.chapterTurnIsInFlight && !widget.chapterTurnIsInFlight) {
      _chapterTurnRequested = false;
    }
    if (widget.frozen != oldWidget.frozen ||
        widget.reverse != oldWidget.reverse) {
      _frame++;
      _userDrag = false;
      _scrolling = false;
      _edgeIntent = false;
      _activity(false);
      if (_pages.hasClients && widget.frozen) {
        _hold ??= _pages.position.hold(() => _hold = null);
      } else if (!widget.frozen) {
        final hold = _hold;
        _hold = null;
        hold?.cancel();
      }
    }
    if (!widget.frozen) _afterFrame();
  }

  int? get _settledCommandPage {
    if (!mounted ||
        widget.frozen ||
        widget.controller.isClosed ||
        widget.controller.isSuspended ||
        !_fits ||
        _scrolling ||
        !_pages.hasClients ||
        _pages.position.isScrollingNotifier.value) {
      return null;
    }
    final page = _pages.page;
    if (page == null ||
        (page - page.round()).abs() > precisionErrorTolerance ||
        page.round() != widget.controller.visiblePageIndex) {
      return null;
    }
    return page.round();
  }

  @override
  bool turnPrevious() => _turnByCommand(-1);

  @override
  bool turnNext() => _turnByCommand(1);

  bool _turnByCommand(int delta) {
    final page = _settledCommandPage;
    if (page == null || widget.chapterTurnIsInFlight || _chapterTurnRequested) {
      return false;
    }
    final controller = widget.controller;
    if (delta < 0) controller.cancelPendingNavigation();
    final pending = controller.requestedPageIndex;
    if (delta > 0 && pending != null && pending != page) return false;
    final prefix = controller.snapshot!;
    final target = page + delta;
    if (target >= 0 && (target < prefix.length || !prefix.isComplete)) {
      return controller.requestPage(target);
    }
    if (!prefix.isComplete) return false;
    final accepted =
        widget.onTurnToAdjacentChapter?.call(
          delta < 0 ? NovelReaderChapterEdge.start : NovelReaderChapterEdge.end,
        ) ??
        false;
    if (mounted && accepted) _chapterTurnRequested = true;
    return accepted;
  }

  @override
  bool confirmChapterEndNavigation() {
    final page = _settledCommandPage;
    final prefix = widget.controller.snapshot;
    if (page == null ||
        prefix?.isComplete != true ||
        page != prefix!.length - 1) {
      return false;
    }
    for (final entry in _mountedPages.entries) {
      if (entry.key.pageIndex != page) continue;
      final position = widget.controller.confirmChapterEndNavigation(
        entry.key,
        entry.value,
      );
      if (position == null) continue;
      widget.onPositionChanged(position);
      return true;
    }
    return false;
  }

  @override
  void cancelChapterTurn() {
    _chapterTurnRequested = false;
  }

  void _afterFrame() {
    final frame = ++_frame;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          frame != _frame ||
          widget.frozen ||
          _scrolling ||
          !_fits) {
        return;
      }
      final controller = widget.controller;
      if (controller.isClosed || !_pages.hasClients) return;
      final actualPage = _pages.page;
      if (_pages.position.isScrollingNotifier.value ||
          actualPage == null ||
          (actualPage - actualPage.round()).abs() > precisionErrorTolerance) {
        return;
      }
      // Growing the fixed prefix can correct pixels without onPageChanged.
      // Settled physical position, rather than its threshold notification, is
      // the authority for mounting/acknowledging a programmatic arrival.
      _page = actualPage.round();
      final target = controller.readyTarget;
      final destination = target?.pageIndex ?? controller.visiblePageIndex;
      if (destination != null && destination != _page) {
        // Programmatic restore/arrival never enters the drag navigation path.
        // Jumping avoids keeping an obsolete automatic animation alive.
        _pages.jumpToPage(destination);
        _afterFrame();
        return;
      }
      if (target == null || target.pageIndex != _page) return;
      final leases = _mountedPages[target.view];
      if (leases == null) return;
      final position = controller.confirmVisible(target, leases);
      if (position != null) widget.onPositionChanged(position);
    });
    // A jump or scroll-end callback may run after this frame's painting. Merely
    // registering another post-frame callback would leave it waiting at idle.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || widget.frozen) return false;
    final controller = widget.controller;
    if (notification is ScrollStartNotification) {
      _scrolling = true;
      _activity(true);
      _frame++;
      if (notification.dragDetails != null) {
        _userDrag = true;
        _edgeIntent = false;
        controller.cancelPendingNavigation();
      }
    } else if (notification is ScrollUpdateNotification &&
        _userDrag &&
        _edgeIntent &&
        (notification.scrollDelta ?? 0) < 0) {
      controller.cancelPendingNavigation();
      _edgeIntent = false;
    } else if (notification is OverscrollNotification &&
        _userDrag &&
        !_edgeIntent &&
        notification.overscroll > 0) {
      final prefix = controller.snapshot;
      if (prefix != null && !prefix.isComplete && _page == prefix.length - 1) {
        _edgeIntent = controller.requestPage(_page + 1);
      }
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
      _activity(false);
      _userDrag = false;
      _afterFrame();
    }
    return false;
  }

  void _pageChanged(int page) {
    _page = page;
    if (_userDrag && !widget.frozen) widget.controller.requestPage(page);
    _afterFrame();
  }

  void _activity(bool scrolling) {
    final revision = ++_activityRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && revision == _activityRevision) {
        widget.onScrollActivityChanged(scrolling && !widget.frozen);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _mounted(
    NovelReaderNativePageView view,
    List<ForumBodyParagraphLease> leases,
  ) {
    _mountedPages[view] = leases;
    _afterFrame();
  }

  void _unmounted(NovelReaderNativePageView view) {
    _mountedPages.remove(view);
    widget.controller.forgetPage(view.pageIndex, view);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final prefix = controller.snapshot;
    // Old generations keep the original dimensions even under new constraints.
    return LayoutBuilder(
      builder: (context, constraints) {
        _fits =
            constraints.maxWidth >= _width && constraints.maxHeight >= _height;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: _width,
            maxWidth: _width,
            minHeight: _height,
            maxHeight: _height,
            child: SizedBox(
              width: _width,
              height: _height,
              child: ColoredBox(
                color: widget.backgroundColor ?? const Color(0x00000000),
                child: IgnorePointer(
                  ignoring: widget.frozen || controller.isClosed,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: PageView.builder(
                      controller: _pages,
                      reverse: widget.reverse,
                      allowImplicitScrolling: false,
                      physics: widget.frozen || controller.isClosed
                          ? const NeverScrollableScrollPhysics()
                          : const AlwaysScrollableScrollPhysics(
                              parent: ClampingScrollPhysics(),
                            ),
                      itemCount: prefix?.length ?? _lastPageCount,
                      onPageChanged: _pageChanged,
                      itemBuilder: (context, page) {
                        final mountedView = _mountedPages.keys
                            .where((view) => view.pageIndex == page)
                            .firstOrNull;
                        final target = controller.readyTarget;
                        // Cancelling a far-away request may reprepare this page
                        // after its window metadata was dropped. Keep its actual
                        // mounted leases until a new exact delivery replaces it.
                        final view =
                            (target?.pageIndex == page ? target!.view : null) ??
                            mountedView ??
                            controller.viewForPage(page);
                        if (view == null ||
                            (!view.isReady &&
                                !_mountedPages.containsKey(view))) {
                          return widget.placeholder;
                        }
                        return _NativeMountedPage(
                          key: ObjectKey(view),
                          view: view,
                          onMounted: _mounted,
                          onUnmounted: _unmounted,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int get _lastPageCount => _mountedPages.keys.fold(
    _page + 1,
    (count, view) => count > view.pageIndex ? count : view.pageIndex + 1,
  );

  @override
  void dispose() {
    _frame++;
    _activityRevision++;
    _navigationBinding?.dispose();
    final changes = _changes;
    if (changes != null) unawaited(changes.cancel());
    _pages.dispose();
    super.dispose();
  }
}

class _NativeMountedPage extends StatefulWidget {
  const _NativeMountedPage({
    super.key,
    required this.view,
    required this.onMounted,
    required this.onUnmounted,
  });
  final NovelReaderNativePageView view;
  final void Function(NovelReaderNativePageView, List<ForumBodyParagraphLease>)
  onMounted;
  final ValueChanged<NovelReaderNativePageView> onUnmounted;

  @override
  State<_NativeMountedPage> createState() => _NativeMountedPageState();
}

class _NativeMountedPageState extends State<_NativeMountedPage> {
  late final List<ForumBodyParagraphLease> _leases;

  @override
  void initState() {
    super.initState();
    _leases = widget.view.takeLeases();
    widget.onMounted(widget.view, _leases);
  }

  @override
  Widget build(BuildContext context) {
    if (_leases.any((lease) => !lease.isActive)) return const SizedBox.shrink();
    final view = widget.view;
    return ForumBodyTextPageSurface(
      snapshot: view.snapshot,
      pageIndex: view.pageIndex,
      layoutId: view.snapshot.layoutId,
      leases: _leases,
    );
  }

  @override
  void dispose() {
    widget.onUnmounted(widget.view);
    // Surface normally releases these; also handle an abandoned/unpainted cell.
    for (final lease in _leases) {
      lease.release();
    }
    super.dispose();
  }
}
