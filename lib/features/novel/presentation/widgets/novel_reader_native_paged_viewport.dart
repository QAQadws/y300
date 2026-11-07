import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_tap_zones.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_paged_turn_motion.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../controllers/novel_reader_native_paged_controller.dart';
import '../controllers/novel_reader_chapter_drag_controller.dart';
import '../controllers/novel_reader_paged_navigation_controller.dart';
import '../models/novel_reader_chapter_turn.dart';
import '../models/novel_reader_native_page_delivery.dart';
import '../models/novel_reader_native_page_view.dart';
import '../models/novel_reader_pagination_position.dart';
import '../models/novel_reader_native_text_selection.dart';
import '../models/novel_reader_native_link_handler.dart';
import '../services/novel_reader_native_table_window_proof.dart';
import '../services/novel_reader_pagination_cancellation.dart';

typedef NovelReaderNativeImageLayoutResolved = void Function(
  NovelReaderNativePageView,
  ForumBodyPreparedImageFragment,
  ForumHtmlImageLayout,
);
typedef NovelReaderNativeInlineImageLayoutResolved = void Function(
  NovelReaderNativePageView,
  ForumBodyPreparedInlineFragment,
  ForumBodyInlineImageBinding,
  ForumHtmlImageLayout,
);
typedef NovelReaderNativeImageTapHandler = void Function(
  ForumBodyPreparedTextFragment,
  ForumBodyInlineImageBinding?,
  bool Function(),
);
typedef NovelReaderNativeCollapseToggle = void Function(
  NovelReaderNativePageView,
  ForumBodyTextPageFragment,
);

typedef _DisplayedLayout = ({
  NovelReaderNativePagedController controller,
  double width,
  double height,
  int page,
  Color? background,
  ForumHtmlImageHost? imageHost,
});

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
    this.previousChapterTitle,
    this.nextChapterTitle,
    this.chapterTurnPolicy = const NovelReaderChapterTurnPolicy(),
    this.onChapterTurnHintChanged,
    this.placeholder = const SizedBox.shrink(),
    this.onPositionChanged,
    this.onScrollActivityChanged,
    this.onTextSelection,
    this.onLinkTap,
    this.imageHost,
    this.onPageUnmounted,
    this.onImageLayoutResolved,
    this.onInlineImageLayoutResolved,
    this.onImageTap,
    this.onCollapseToggle,
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
  final String? previousChapterTitle;
  final String? nextChapterTitle;
  final NovelReaderChapterTurnPolicy chapterTurnPolicy;

  /// Shell paints localized hints outside the measured body. Null clears it.
  final ValueChanged<NovelReaderChapterTurnHint?>? onChapterTurnHintChanged;
  final Widget placeholder;
  final ValueChanged<NovelReaderPaginationPosition>? onPositionChanged;
  final ValueChanged<bool>? onScrollActivityChanged;
  final ValueChanged<NovelReaderNativeTextSelection>? onTextSelection;
  final NovelReaderNativeLinkHandler? onLinkTap;
  final ForumHtmlImageHost? imageHost;
  final VoidCallback? onPageUnmounted;
  final NovelReaderNativeImageLayoutResolved? onImageLayoutResolved;
  final NovelReaderNativeInlineImageLayoutResolved? onInlineImageLayoutResolved;
  final NovelReaderNativeImageTapHandler? onImageTap;
  final NovelReaderNativeCollapseToggle? onCollapseToggle;

  @override
  State<NovelReaderNativePagedViewport> createState() =>
      _NovelReaderNativePagedViewportState();
}

class _NovelReaderNativePagedViewportState
    extends State<NovelReaderNativePagedViewport> {
  StreamSubscription<void>? _changes;
  _DisplayedLayout? _displayed;
  _DisplayedLayout? _stagedTable;
  int _binding = 0;
  int _hintRevision = 0;
  NovelReaderChapterTurnHint? _hint;

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
      _stagedTable = null;
      _unbind();
      _bind();
    }
    final displayed = _displayed;
    if (!controllerChanged &&
        !widget.controller.isClosed &&
        displayed != null &&
        identical(displayed.controller, widget.controller) &&
        (oldWidget.backgroundColor != widget.backgroundColor ||
            !identical(oldWidget.imageHost, widget.imageHost))) {
      // Only repaint the accepted current delivery. A pending/failed replacement
      // must retain the previous controller's canvas with its painted content.
      _displayed = (
        controller: displayed.controller,
        width: displayed.width,
        height: displayed.height,
        page: displayed.page,
        background: widget.backgroundColor,
        imageHost: widget.imageHost,
      );
    }
    _startIfActive();
    if (controllerChanged || ownerChanged || !widget.active) {
      _publishHint(null);
    }
  }

  void _publishHint(NovelReaderChapterTurnHint? hint) {
    if (hint == _hint) return;
    _hint = hint;
    final revision = ++_hintRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && revision == _hintRevision) {
        widget.onChapterTurnHintChanged?.call(_hint);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _bind() {
    final controller = widget.controller;
    final binding = _binding;
    void changed() {
      if (!mounted || binding != _binding) return;
      setState(_selectDisplay);
    }

    _changes = controller.changes.listen((_) => changed(), onDone: changed);
    _startIfActive();
    _selectDisplay();
  }

  void _startIfActive() {
    if (widget.active &&
        widget.controller.phase == NovelReaderNativePagedPhase.created) {
      widget.controller.start();
    }
  }

  void _selectDisplay() {
    final controller = widget.controller;
    final target = controller.readyTarget;
    if (_stagedTable != null && (controller.isClosed || target == null)) {
      _stagedTable = null;
    }
    if (target?.view.isReady == true &&
        !identical(_displayed?.controller, controller)) {
      final snapshot = controller.snapshot!;
      final replacement = (
        controller: controller,
        width: snapshot.width,
        height: snapshot.height,
        page: target!.pageIndex,
        background: widget.backgroundColor,
        imageHost: widget.imageHost,
      );
      if (_displayed != null && snapshot[target.pageIndex].table != null) {
        _stagedTable = replacement;
      } else {
        _stagedTable = null;
        _displayed = replacement;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _displayed;
    if (displayed == null) return widget.placeholder;
    final staged = _stagedTable;
    return Stack(
      fit: StackFit.expand,
      children: [
        _layout(displayed, staged: false),
        if (staged != null) _layout(staged, staged: true),
      ],
    );
  }

  Widget _layout(_DisplayedLayout displayed, {required bool staged}) {
    // Capture the box and initial page when offered: source failure/retirement
    // can remove the proposal or snapshot before the next Widget build.
    final frozen =
        staged ||
        !widget.active ||
        widget.controller.isSuspended ||
        !identical(displayed.controller, widget.controller);
    return Offstage(
      key: ObjectKey(displayed.controller),
      offstage: staged,
      child: _NativeLayoutViewport(
        controller: displayed.controller,
        width: displayed.width,
        height: displayed.height,
        initialPage: displayed.page,
        backgroundColor: displayed.background,
        imageHost: displayed.imageHost,
        onPageUnmounted: widget.onPageUnmounted,
        onImageLayoutResolved: widget.onImageLayoutResolved,
        onInlineImageLayoutResolved: widget.onInlineImageLayoutResolved,
        onImageTap: widget.onImageTap == null
            ? null
            : (fragment, binding, isCurrent) {
                if (frozen ||
                    !widget.active ||
                    !identical(displayed.controller, widget.controller)) {
                  return;
                }
                final displayRevision = _binding;
                widget.onImageTap!(
                  fragment,
                  binding,
                  () =>
                      mounted &&
                      displayRevision == _binding &&
                      identical(displayed.controller, widget.controller) &&
                      identical(displayed.imageHost, widget.imageHost) &&
                      isCurrent(),
                );
              },
        frozen: frozen,
        onCollapseToggle: frozen || widget.onCollapseToggle == null
            ? null
            : (view, fragment) {
                if (mounted &&
                    widget.active &&
                    identical(displayed.controller, widget.controller)) {
                  widget.onCollapseToggle?.call(view, fragment);
                }
              },
        reverse: widget.reverse,
        navigationController: staged ? null : widget.navigationController,
        onTablePresented: staged
            ? (view) {
                if (!mounted ||
                    !widget.active ||
                    displayed.controller.isSuspended ||
                    !identical(
                      _stagedTable?.controller,
                      displayed.controller,
                    ) ||
                    !identical(displayed.controller, widget.controller) ||
                    !identical(displayed.controller.readyTarget?.view, view)) {
                  return;
                }
                setState(() {
                  _displayed = _stagedTable;
                  _stagedTable = null;
                });
              }
            : null,
        onTurnToAdjacentChapter: widget.onTurnToAdjacentChapter,
        chapterTurnIsInFlight: widget.chapterTurnIsInFlight,
        previousChapterTitle: widget.previousChapterTitle,
        nextChapterTitle: widget.nextChapterTitle,
        chapterTurnPolicy: widget.chapterTurnPolicy,
        onChapterTurnHintChanged: (hint) {
          if (identical(displayed.controller, widget.controller) &&
              (hint == null || !frozen)) {
            _publishHint(hint);
          }
        },
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
        onLinkTap: frozen || widget.onLinkTap == null
            ? null
            : (url, isCurrent) {
                final binding = _binding;
                bool current() =>
                    mounted &&
                    widget.active &&
                    binding == _binding &&
                    identical(displayed.controller, widget.controller) &&
                    isCurrent();
                if (current()) widget.onLinkTap?.call(url, current);
              },
        onTextSelection: widget.onTextSelection == null
            ? null
            : (selection) {
                if (frozen ||
                    !identical(displayed.controller, widget.controller)) {
                  return;
                }
                widget.onTextSelection!(
                  NovelReaderNativeTextSelection(
                    selection.snapshot,
                    () =>
                        mounted &&
                        identical(displayed.controller, widget.controller) &&
                        selection.isCurrent,
                  ),
                );
              },
      ),
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
    required this.previousChapterTitle,
    required this.nextChapterTitle,
    required this.chapterTurnPolicy,
    required this.onChapterTurnHintChanged,
    required this.placeholder,
    required this.onPositionChanged,
    required this.onScrollActivityChanged,
    required this.onTextSelection,
    required this.onLinkTap,
    required this.imageHost,
    required this.onPageUnmounted,
    required this.onImageLayoutResolved,
    required this.onInlineImageLayoutResolved,
    required this.onImageTap,
    required this.onCollapseToggle,
    required this.onTablePresented,
  });
  final NovelReaderNativePagedController controller;
  final ForumHtmlImageHost? imageHost;
  final VoidCallback? onPageUnmounted;
  final NovelReaderNativeImageLayoutResolved? onImageLayoutResolved;
  final NovelReaderNativeInlineImageLayoutResolved? onInlineImageLayoutResolved;
  final NovelReaderNativeImageTapHandler? onImageTap;
  final NovelReaderNativeCollapseToggle? onCollapseToggle;
  final ValueChanged<NovelReaderNativePageView>? onTablePresented;
  final double width;
  final double height;
  final int initialPage;
  final Color? backgroundColor;
  final bool frozen;
  final bool reverse;
  final NovelReaderPagedNavigationController? navigationController;
  final bool Function(NovelReaderChapterEdge)? onTurnToAdjacentChapter;
  final bool chapterTurnIsInFlight;
  final String? previousChapterTitle;
  final String? nextChapterTitle;
  final NovelReaderChapterTurnPolicy chapterTurnPolicy;
  final ValueChanged<NovelReaderChapterTurnHint?> onChapterTurnHintChanged;
  final Widget placeholder;
  final ValueChanged<NovelReaderPaginationPosition> onPositionChanged;
  final ValueChanged<bool> onScrollActivityChanged;
  final ValueChanged<NovelReaderNativeTextSelection>? onTextSelection;
  final NovelReaderNativeLinkHandler? onLinkTap;

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
      <NovelReaderNativePageView, List<ForumBodyPreparedTextFragment>>{};
  final _tableMounts = <NovelReaderNativePageView, ForumBodyTablePageLease>{};
  final _readyTables = <NovelReaderNativePageView>{};
  final _tableWindows =
      <NovelReaderNativePageView, ForumBodyTableVisibleWindow>{};
  ({
    ForumBodyTableVisibleWindow window,
    NovelReaderTextAnchor? preferred,
    int revision,
    NovelReaderPaginationCancellationToken token,
  })?
  _tableWork;
  ({NovelReaderNativeTableWindowProof proof, NovelReaderTextAnchor? preferred})?
  _tableProof;
  ForumBodyTableVisibleWindow? _consumedTableWindow;
  final _tableOffsets = <int, Offset>{};
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
  _NativeTapTurn? _tapTurn;
  int? _tapResetPage;
  ({int revision, int page, NovelReaderChapterDragController drag})?
  _chapterDrag;
  ({int revision, int page, NovelReaderChapterEdge edge})? _chapterRelease;

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
        final work = _tableWork;
        if (work != null &&
            work.revision != widget.controller.navigationRevision) {
          _cancelTableProof();
        }
        _reconcileTapTurn();
        _reconcileChapterDrag();
        setState(() {});
        _afterFrame();
      },
      onDone: () {
        if (mounted) {
          _cancelTableProof();
          _resetChapterDrag();
          setState(() {});
        }
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
      _retireTapTurn(cancelNavigation: true);
      _navigationBinding?.dispose();
      _navigationBinding = widget.navigationController?.bind(this);
    }
    if (oldWidget.chapterTurnIsInFlight && !widget.chapterTurnIsInFlight) {
      _chapterTurnRequested = false;
    }
    if (widget.frozen != oldWidget.frozen ||
        widget.reverse != oldWidget.reverse ||
        widget.chapterTurnIsInFlight != oldWidget.chapterTurnIsInFlight ||
        widget.previousChapterTitle != oldWidget.previousChapterTitle ||
        widget.nextChapterTitle != oldWidget.nextChapterTitle ||
        _policyKey(widget.chapterTurnPolicy) !=
            _policyKey(oldWidget.chapterTurnPolicy) ||
        (widget.onTurnToAdjacentChapter == null) !=
            (oldWidget.onTurnToAdjacentChapter == null) ||
        !identical(
          widget.navigationController,
          oldWidget.navigationController,
        )) {
      _resetChapterDrag();
    }
    if (widget.frozen != oldWidget.frozen ||
        widget.reverse != oldWidget.reverse) {
      _cancelTableProof();
      _retireTapTurn(cancelNavigation: true);
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
    if (!widget.frozen || widget.onTablePresented != null) _afterFrame();
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
    _resetChapterDrag();
    _reconcileTapTurn();
    final previous = _tapTurn;
    if (previous != null) {
      if (delta == previous.to - previous.from) return false;
      // Opposite input starts from the last confirmed page, even when the old
      // animation has crossed PageView's onPageChanged threshold.
      _retireTapTurn(cancelNavigation: true);
      _resetTapPosition();
    }
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
      if (!controller.requestPage(target)) return false;
      _tapTurn = _NativeTapTurn(page, target, controller.navigationRevision);
      _startReadyTapTurn();
      return true;
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
      final position = widget.controller.confirmPreparedChapterEndNavigation(
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
    _resetChapterDrag();
  }

  static (double, double, double) _policyKey(
    NovelReaderChapterTurnPolicy value,
  ) => (
    value.minCommitDistance,
    value.viewportCommitFraction,
    value.hintRevealFraction,
  );

  bool get _chapterTurnContextAllowed =>
      !widget.frozen &&
      _fits &&
      !widget.controller.isClosed &&
      !widget.controller.isSuspended &&
      widget.controller.snapshot?.isComplete == true &&
      widget.onTurnToAdjacentChapter != null &&
      !widget.chapterTurnIsInFlight &&
      !_chapterTurnRequested;

  void _beginChapterDrag() {
    _resetChapterDrag();
    if (!_chapterTurnContextAllowed ||
        widget.controller.hasPendingNavigation ||
        !_pages.hasClients) {
      return;
    }
    final actual = _pages.page;
    if (actual == null ||
        (actual - actual.round()).abs() > precisionErrorTolerance ||
        actual.round() != widget.controller.visiblePageIndex) {
      return;
    }
    final page = actual.round();
    _chapterDrag = (
      revision: widget.controller.navigationRevision,
      page: page,
      drag: NovelReaderChapterDragController(
        // A known complete chapter also permits dragging from an interior page
        // to an edge and deliberately continuing past it, as the old reader did.
        previousChapterTitle: widget.previousChapterTitle,
        nextChapterTitle: widget.nextChapterTitle,
        viewportDimension: _width,
        policy: widget.chapterTurnPolicy,
      ),
    );
  }

  void _resetChapterDrag() {
    _chapterDrag = null;
    _chapterRelease = null;
    widget.onChapterTurnHintChanged(null);
  }

  void _reconcileChapterDrag() {
    final intent = _chapterDrag;
    if (intent != null &&
        (!_chapterTurnContextAllowed ||
            intent.revision != widget.controller.navigationRevision ||
            (widget.controller.hasPendingNavigation
                ? widget.controller.requestedPageIndex != intent.page
                : widget.controller.visiblePageIndex != intent.page))) {
      _resetChapterDrag();
    }
    final release = _chapterRelease;
    if (release != null &&
        (!_chapterTurnContextAllowed ||
            release.revision != widget.controller.navigationRevision ||
            (!widget.controller.hasPendingNavigation &&
                widget.controller.visiblePageIndex != release.page))) {
      _resetChapterDrag();
    }
  }

  void _commitChapterDrag() {
    _reconcileChapterDrag();
    final intent = _chapterDrag;
    final edge = intent?.drag.edgeToCommit;
    _resetChapterDrag();
    if (edge == null) return;
    _chapterRelease = (
      revision: intent!.revision,
      page: intent.page,
      edge: edge,
    );
  }

  void _confirmChapterRelease() {
    _reconcileChapterDrag();
    final release = _chapterRelease;
    if (release == null ||
        widget.controller.hasPendingNavigation ||
        _settledCommandPage != release.page) {
      return;
    }
    final boundary = release.edge == NovelReaderChapterEdge.start
        ? 0
        : widget.controller.snapshot!.length - 1;
    _chapterRelease = null;
    if (release.page != boundary) return;
    final accepted =
        widget.onTurnToAdjacentChapter?.call(release.edge) ?? false;
    if (mounted && accepted) _chapterTurnRequested = true;
  }

  void _reconcileTapTurn() {
    final turn = _tapTurn;
    if (turn == null) return;
    final controller = widget.controller;
    if (controller.isClosed ||
        controller.isSuspended ||
        controller.navigationRevision != turn.revision ||
        !controller.hasPendingNavigation ||
        !_fits) {
      // A newer controller request owns its own lifetime. Retire only motion;
      // never cancel that newer seek while stopping an older tap animation.
      _retireTapTurn(cancelNavigation: !_fits);
    }
  }

  void _retireTapTurn({bool cancelNavigation = false, bool snap = true}) {
    final turn = _tapTurn;
    if (turn == null) return;
    _tapTurn = null;
    _frame++;
    if (snap && turn.started) {
      _tapResetPage = widget.controller.visiblePageIndex ?? turn.from;
    }
    if (cancelNavigation &&
        widget.controller.navigationRevision == turn.revision) {
      widget.controller.cancelPendingNavigation();
    }
  }

  void _resetTapPosition() {
    final page = _tapResetPage;
    if (page == null || !_pages.hasClients || widget.frozen) return;
    _tapResetPage = null;
    _scrolling = false;
    _activity(false);
    // jumpToPage also disposes the old DrivenScrollActivity; invalidating its
    // Future alone would leave pixels moving towards the obsolete destination.
    _pages.jumpToPage(page);
    _page = page;
    _afterFrame();
  }

  Future<void> _animateTap(_NativeTapTurn turn) async {
    turn.started = true;
    await _pages.animateToPage(
      turn.to,
      duration: ReaderPagedTurnMotion.animationDuration,
      curve: ReaderPagedTurnMotion.animationCurve,
    );
    if (mounted && identical(_tapTurn, turn)) _afterFrame();
  }

  bool _startReadyTapTurn() {
    _reconcileTapTurn();
    final turn = _tapTurn;
    final target = widget.controller.readyTarget;
    if (turn == null ||
        turn.started ||
        target?.requestId != turn.revision ||
        target?.pageIndex != turn.to ||
        _settledCommandPage != turn.from) {
      return false;
    }
    // A fully prepared neighbor can mount during the first animation frame.
    // Starting here never confirms a position; arrival still needs the actual
    // mounted fragments and the existing stable post-frame validation below.
    unawaited(_animateTap(turn));
    return true;
  }

  void _afterFrame() {
    final frame = ++_frame;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || frame != _frame) return;
      final presented = widget.onTablePresented;
      if (presented != null) {
        final target = widget.controller.readyTarget;
        if (target == null || !_fits || !_pages.hasClients) return;
        if (_pages.page != target.pageIndex) {
          _pages.jumpToPage(target.pageIndex);
          _afterFrame();
        } else if (_readyTables.contains(target.view) &&
            _tableFocusVisible(target)) {
          presented(target.view);
        }
        return;
      }
      if (widget.frozen) return;
      _reconcileTapTurn();
      _reconcileChapterDrag();
      _resetTapPosition();
      if (_scrolling || !_fits) return;
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
        if (_startReadyTapTurn()) return;
        // Restore/search/seek have no tap motion intent.
        _pages.jumpToPage(destination);
        _afterFrame();
        return;
      }
      if (target == null || target.pageIndex != _page) {
        final view = controller.visibleView;
        final fragments = view == null ? null : _mountedPages[view];
        if (view != null && fragments != null && view.pageIndex == _page) {
          final table = _tableMounts[view];
          final position = table == null
              ? controller.refreshPreparedVisible(view, fragments)
              : _refreshTable(view, table);
          if (position != null) widget.onPositionChanged(position);
        }
        _confirmChapterRelease();
        return;
      }
      final fragments = _mountedPages[target.view];
      final table = _tableMounts[target.view];
      if (fragments == null ||
          (table != null &&
              (!_readyTables.contains(target.view) ||
                  !_tableFocusVisible(target)))) {
        return;
      }
      final proof = table == null
          ? null
          : _proveTableWindow(
              target.view,
              table,
              preferred: target.restoredAnchor,
            );
      if (table != null && proof == null) return;
      final position = controller.confirmPreparedVisible(
        target,
        fragments,
        table: table,
        tableProof: proof,
      );
      if (position != null) {
        _consumedTableWindow = proof?.window;
        _tapTurn = null;
        widget.onPositionChanged(position);
      }
      _confirmChapterRelease();
    });
    // A jump or scroll-end callback may run after this frame's painting. Merely
    // registering another post-frame callback would leave it waiting at idle.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || widget.frozen) return false;
    final controller = widget.controller;
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) _beginChapterDrag();
      _scrolling = true;
      _activity(true);
      _frame++;
      if (notification.dragDetails != null) {
        _retireTapTurn(snap: false);
        _tapResetPage = null;
        _userDrag = true;
        _edgeIntent = false;
        controller.cancelPendingNavigation();
      }
    } else if (notification is ScrollUpdateNotification && _userDrag) {
      // Real movement away from an edge discards its accumulated peak. The
      // same known-complete gesture may still reach another actual boundary.
      if ((notification.scrollDelta ?? 0) != 0) {
        _chapterDrag?.drag.resetPull();
        widget.onChapterTurnHintChanged(null);
      }
      if (_userDrag && _edgeIntent && (notification.scrollDelta ?? 0) < 0) {
        controller.cancelPendingNavigation();
        _edgeIntent = false;
      }
    } else if (notification is OverscrollNotification &&
        _userDrag &&
        notification.dragDetails != null) {
      _reconcileChapterDrag();
      final drag = _chapterDrag?.drag;
      if (drag != null) {
        drag.observeOverscroll(notification.overscroll);
        widget.onChapterTurnHintChanged(drag.hint);
      }
      final prefix = controller.snapshot;
      if (!_edgeIntent &&
          notification.overscroll > 0 &&
          prefix != null &&
          !prefix.isComplete &&
          _page == prefix.length - 1) {
        _edgeIntent = controller.requestPage(_page + 1);
      }
    } else if (notification is ScrollEndNotification) {
      final userDrag = _userDrag;
      _scrolling = false;
      _activity(false);
      _userDrag = false;
      if (userDrag) _commitChapterDrag();
      _afterFrame();
    }
    return false;
  }

  void _pageChanged(int page) {
    _page = page;
    if (_userDrag && !widget.frozen) {
      // Observe an intervening external seek before this gesture issues its
      // own new revision; otherwise that page request could resurrect old intent.
      _reconcileChapterDrag();
      final intent = _chapterDrag;
      if (widget.controller.requestPage(page) && intent != null) {
        // Only this physical gesture may advance its intent revision. A seek,
        // tap, retry or other external navigation still retires the whole pull.
        _chapterDrag = (
          revision: widget.controller.navigationRevision,
          page: page,
          drag: intent.drag,
        );
      }
    }
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
    List<ForumBodyPreparedTextFragment> fragments,
    ForumBodyTablePageLease? table,
  ) {
    _mountedPages[view] = fragments;
    if (table == null) {
      _afterFrame();
    } else {
      _tableMounts[view] = table;
    }
  }

  void _tableReady(NovelReaderNativePageView view, bool ready) {
    if (!_tableMounts.containsKey(view)) return;
    if (ready) {
      _readyTables.add(view);
      _afterFrame();
    } else {
      _readyTables.remove(view);
    }
  }

  void _tableWindowChanged(
    NovelReaderNativePageView view,
    ForumBodyTableVisibleWindow? window,
  ) {
    if (!_tableMounts.containsKey(view)) return;
    if (window == null) {
      _tableWindows.remove(view);
    } else {
      _tableWindows[view] = window;
      _tableOffsets[view.pageIndex] = window.bounds.topLeft;
    }
    if (_tableWork?.window.isCurrent == false) _cancelTableProof();
    if (_tableProof?.proof.isCurrent == false) _tableProof = null;
    if (_consumedTableWindow?.isCurrent == false) _consumedTableWindow = null;
    _afterFrame();
  }

  NovelReaderPaginationPosition? _refreshTable(
    NovelReaderNativePageView view,
    ForumBodyTablePageLease table,
  ) {
    final window = _tableWindows[view];
    if (window == null ||
        !window.hasUserScrolled ||
        identical(window, _consumedTableWindow)) {
      return null;
    }
    final proof = _proveTableWindow(view, table);
    if (proof == null) return null;
    _consumedTableWindow = window;
    return widget.controller.refreshTableVisible(view, table, proof);
  }

  NovelReaderNativeTableWindowProof? _proveTableWindow(
    NovelReaderNativePageView view,
    ForumBodyTablePageLease table, {
    NovelReaderTextAnchor? preferred,
  }) {
    final window = _tableWindows[view];
    if (window == null || !window.isCurrent) return null;
    final checked = _tableProof;
    if (checked != null &&
        identical(checked.proof.window, window) &&
        identical(checked.preferred, preferred)) {
      return checked.proof;
    }
    final pending = _tableWork;
    if (pending != null &&
        identical(pending.window, window) &&
        identical(pending.preferred, preferred)) {
      return null;
    }
    _cancelTableProof();
    final token = NovelReaderPaginationCancellationToken();
    _tableWork = (
      window: window,
      preferred: preferred,
      revision: widget.controller.navigationRevision,
      token: token,
    );
    unawaited(_prepareTableWindow(view, table, window, token, preferred));
    // This starts in a settled post-frame callback. The first frame yield
    // needs another frame even when the table's last slice already painted.
    WidgetsBinding.instance.ensureVisualUpdate();
    return null;
  }

  Future<void> _prepareTableWindow(
    NovelReaderNativePageView view,
    ForumBodyTablePageLease table,
    ForumBodyTableVisibleWindow window,
    NovelReaderPaginationCancellationToken token,
    NovelReaderTextAnchor? preferred,
  ) async {
    bool current() =>
        mounted &&
        !widget.frozen &&
        !token.isCancelled &&
        identical(_tableWork?.token, token) &&
        identical(_tableWindows[view], window) &&
        _tableWork!.revision == widget.controller.navigationRevision &&
        window.isCurrent;
    try {
      final proof = await widget.controller.prepareTableWindow(
        table,
        window,
        token,
        preferred: preferred,
      );
      if (proof != null && current()) {
        _tableProof = (proof: proof, preferred: preferred);
        _afterFrame();
      }
    } catch (error) {
      if (current()) _tableFailed(view, error);
    } finally {
      if (identical(_tableWork?.token, token)) _tableWork = null;
      token.cancel();
    }
  }

  void _cancelTableProof() {
    _tableWork?.token.cancel();
    _tableWork = null;
    _tableProof = null;
  }

  bool _tableFocusVisible(NovelReaderNativePageDelivery delivery) {
    final focus = delivery.tableFocus;
    if (focus == null) return true;
    final window = _tableWindows[delivery.view];
    if (window == null || !window.isCurrent) return false;
    final clip = window.bounds;
    return focus.left >= clip.left - precisionErrorTolerance &&
        focus.top >= clip.top - precisionErrorTolerance &&
        focus.right <= clip.right + precisionErrorTolerance &&
        focus.bottom <= clip.bottom + precisionErrorTolerance;
  }

  ({int request, Offset offset})? _tableFocusFor(
    NovelReaderNativePageView view,
    NovelReaderNativePageDelivery? target,
  ) {
    final focus = target?.tableFocus;
    if (focus == null || !identical(target!.view, view)) return null;
    final page = view.snapshot[view.pageIndex].table!;
    double center(double target, double dimension, double extent) =>
        (target - dimension / 2).clamp(0.0, math.max(0.0, extent - dimension));
    return (
      request: target.requestId,
      offset: Offset(
        center(focus.center.dx, page.bounds.width, page.contentSize.width),
        center(focus.center.dy, page.bounds.height, page.contentSize.height),
      ),
    );
  }

  void _tableFailed(NovelReaderNativePageView view, Object error) {
    final table = _tableMounts[view];
    if (table != null) {
      widget.controller.reportTablePresentationFailure(view, table, error);
    }
  }

  void _unmounted(NovelReaderNativePageView view) {
    final window = _tableWindows.remove(view);
    if (window != null) {
      if (identical(_tableWork?.window, window) ||
          identical(_tableProof?.proof.window, window)) {
        _cancelTableProof();
      }
      if (identical(_consumedTableWindow, window)) _consumedTableWindow = null;
    }
    _mountedPages.remove(view);
    _tableMounts.remove(view);
    _readyTables.remove(view);
    widget.controller.forgetPage(view.pageIndex, view);
    widget.onPageUnmounted?.call();
  }

  bool _isSettledPage(NovelReaderNativePageView view) {
    final controller = widget.controller;
    final page = view.pageIndex;
    return mounted &&
        _fits &&
        !_scrolling &&
        !controller.isClosed &&
        !controller.hasPendingNavigation &&
        identical(controller.visibleView, view) &&
        _page == page &&
        _pages.hasClients &&
        !_pages.position.isScrollingNotifier.value &&
        ((_pages.page ?? -1) - page).abs() <= precisionErrorTolerance;
  }

  void _toggleCollapse(
    NovelReaderNativePageView view,
    ForumBodyTextPageFragment fragment,
  ) {
    if (!widget.frozen &&
        _isSettledPage(view) &&
        _mountedPages.containsKey(view)) {
      widget.onCollapseToggle?.call(view, fragment);
    }
  }

  void _tapLink(
    NovelReaderNativePageView view,
    String url,
    bool Function() isCurrent,
  ) {
    final controller = widget.controller;
    final revision = controller.navigationRevision;
    bool current() =>
        mounted &&
        !widget.frozen &&
        !controller.isSuspended &&
        revision == controller.navigationRevision &&
        _isSettledPage(view) &&
        _mountedPages.containsKey(view) &&
        isCurrent();
    if (current()) widget.onLinkTap?.call(url, current);
  }

  void _tapImage(
    NovelReaderNativePageView view,
    ForumBodyPreparedTextFragment fragment,
    ForumBodyInlineImageBinding? binding,
  ) {
    final fragments = _mountedPages[view];
    final tap = widget.onImageTap;
    if (tap == null ||
        widget.frozen ||
        fragments == null ||
        (!_tableMounts.containsKey(view) &&
            !fragments.any(
              (mounted) =>
                  identical(mounted, fragment) ||
                  (mounted is ForumBodyPreparedListItemFragment &&
                      identical(mounted.body, fragment)),
            ))) {
      return;
    }
    final controller = widget.controller;
    final revision = controller.navigationRevision;
    // The reader suspends once after saving and before opening the viewer.
    // The tap can borrow the same mounted slot through that suspension only.
    bool current() =>
        controller.navigationRevision ==
            revision + (controller.isSuspended ? 1 : 0) &&
        _isSettledPage(view) &&
        fragment.isActive &&
        (binding == null ||
            (fragment is ForumBodyPreparedInlineFragment &&
                identical(fragment.view.images[binding.atomIndex], binding))) &&
        identical(_mountedPages[view], fragments);
    if (current()) tap(fragment, binding, current);
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
                      // Native window jobs prepare text/coverage independently.
                      // Mount the adjacent ready views too, so their image first
                      // frames and table cells are ready before a physical turn.
                      allowImplicitScrolling: true,
                      scrollCacheExtent: const ScrollCacheExtent.viewport(1),
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
                        final origin = controller.visiblePageIndex ?? _page;
                        final demand = controller.requestedPageIndex ?? origin;
                        final tablePending =
                            target != null &&
                            target.view.snapshot[target.pageIndex].table !=
                                null &&
                            !_readyTables.contains(target.view);
                        if (page != origin &&
                            ((page - demand).abs() > 1 ||
                                (tablePending && page != target.pageIndex))) {
                          // Retire distant warm mounts before the requested
                          // page reserves resources. The readable origin stays.
                          return widget.placeholder;
                        }
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
                          imageHost: widget.imageHost,
                          onImageDisplayChanged: _afterFrame,
                          onImageLayoutResolved: widget.onImageLayoutResolved,
                          onInlineImageLayoutResolved:
                              widget.onInlineImageLayoutResolved,
                          onImageTap: widget.onImageTap == null
                              ? null
                              : (fragment, binding) =>
                                    _tapImage(view, fragment, binding),
                          onCollapseToggle: widget.onCollapseToggle == null
                              ? null
                              : (fragment) => _toggleCollapse(view, fragment),
                          key: ObjectKey(view),
                          view: view,
                          active: page == _page && !widget.frozen,
                          // Freezing blocks input, but the confirmed delivery
                          // remains mounted. Keep its selection registration
                          // stable until the visible page actually changes.
                          selectionEnabled: controller.visiblePageIndex == page,
                          // Retain the confirmed origin through cancellation
                          // and this one pending tap destination. Rapid return
                          // reuses its live Element instead of retiring and
                          // re-transferring the same view's handles.
                          keepAlive:
                              page == controller.visiblePageIndex ||
                              page == _tapTurn?.to,
                          onMounted: _mounted,
                          onUnmounted: _unmounted,
                          onTableReadyChanged: (ready) =>
                              _tableReady(view, ready),
                          onTableWindowChanged: (window) =>
                              _tableWindowChanged(view, window),
                          onTableFailure: (error) => _tableFailed(view, error),
                          initialTableOffset:
                              _tableOffsets[page] ?? Offset.zero,
                          tableFocus: _tableFocusFor(view, target),
                          isTableFocusCurrent: (revision) {
                            final delivery = controller.readyTarget;
                            return !controller.isSuspended &&
                                identical(delivery?.view, view) &&
                                delivery!.requestId == revision;
                          },
                          onTableUserDrag: () {
                            final delivery = controller.readyTarget;
                            if (identical(delivery?.view, view) &&
                                delivery?.tableFocus != null) {
                              controller.cancelPendingNavigation();
                            }
                          },
                          onTableOffsetChanged: (offset) =>
                              _tableOffsets[page] = offset,
                          onLinkTap: widget.frozen || widget.onLinkTap == null
                              ? null
                              : (url, isCurrent) =>
                                    _tapLink(view, url, isCurrent),
                          onTextSelection:
                              widget.frozen || widget.onTextSelection == null
                              ? null
                              : (snapshot, isCurrent) {
                                  if (widget.frozen ||
                                      _scrolling ||
                                      _page != page ||
                                      controller.isClosed) {
                                    return;
                                  }
                                  final fragments = _mountedPages[view];
                                  final delivery = controller.visibleDelivery;
                                  if (fragments == null ||
                                      !identical(delivery?.view, view)) {
                                    return;
                                  }
                                  widget.onTextSelection!(
                                    NovelReaderNativeTextSelection(
                                      snapshot,
                                      () =>
                                          mounted &&
                                          !controller.isClosed &&
                                          _page == page &&
                                          identical(
                                            controller.visibleDelivery,
                                            delivery,
                                          ) &&
                                          _mountedPages.containsKey(view) &&
                                          isCurrent() &&
                                          fragments.every(
                                            (fragment) => fragment.isActive,
                                          ),
                                    ),
                                  );
                                },
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
    _tapTurn = null;
    _cancelTableProof();
    _tapResetPage = null;
    _frame++;
    _activityRevision++;
    _navigationBinding?.dispose();
    final changes = _changes;
    if (changes != null) unawaited(changes.cancel());
    _pages.dispose();
    super.dispose();
  }
}

final class _NativeTapTurn {
  _NativeTapTurn(this.from, this.to, this.revision);
  final int from;
  final int to;
  final int revision;
  bool started = false;
}

class _NativeMountedPage extends StatefulWidget {
  const _NativeMountedPage({
    super.key,
    required this.view,
    required this.active,
    required this.keepAlive,
    required this.selectionEnabled,
    required this.onMounted,
    required this.onUnmounted,
    required this.onTextSelection,
    required this.onLinkTap,
    required this.imageHost,
    required this.onImageDisplayChanged,
    required this.onImageLayoutResolved,
    required this.onInlineImageLayoutResolved,
    required this.onImageTap,
    required this.onCollapseToggle,
    required this.onTableReadyChanged,
    required this.onTableWindowChanged,
    required this.onTableFailure,
    required this.initialTableOffset,
    required this.tableFocus,
    required this.isTableFocusCurrent,
    required this.onTableUserDrag,
    required this.onTableOffsetChanged,
  });
  final NovelReaderNativePageView view;
  final ForumHtmlImageHost? imageHost;
  final VoidCallback onImageDisplayChanged;
  final NovelReaderNativeImageLayoutResolved? onImageLayoutResolved;
  final NovelReaderNativeInlineImageLayoutResolved? onInlineImageLayoutResolved;
  final void Function(
    ForumBodyPreparedTextFragment,
    ForumBodyInlineImageBinding?,
  )?
  onImageTap;
  final ValueChanged<ForumBodyTextPageFragment>? onCollapseToggle;
  final bool active;
  final bool keepAlive;
  final bool selectionEnabled;
  final void Function(
    NovelReaderNativePageView,
    List<ForumBodyPreparedTextFragment>,
    ForumBodyTablePageLease?,
  )
  onMounted;
  final ValueChanged<NovelReaderNativePageView> onUnmounted;
  final void Function(ForumBodyTextSelectionSnapshot, bool Function())?
  onTextSelection;
  final NovelReaderNativeLinkHandler? onLinkTap;
  final ValueChanged<bool> onTableReadyChanged;
  final ValueChanged<ForumBodyTableVisibleWindow?> onTableWindowChanged;
  final ValueChanged<Object> onTableFailure;
  final Offset initialTableOffset;
  final ({int request, Offset offset})? tableFocus;
  final bool Function(int revision) isTableFocusCurrent;
  final VoidCallback onTableUserDrag;
  final ValueChanged<Offset> onTableOffsetChanged;

  @override
  State<_NativeMountedPage> createState() => _NativeMountedPageState();
}

class _NativeMountedPageState extends State<_NativeMountedPage>
    with AutomaticKeepAliveClientMixin {
  late final List<ForumBodyPreparedTextFragment> _fragments;
  ForumBodyTablePageLease? _table;
  ScrollController? _tableHorizontal, _tableVertical;
  ForumBodyTableVisibleWindow? _warmTableWindow;
  bool _warmRefreshScheduled = false;

  @override
  void initState() {
    super.initState();
    final mount = widget.view.takeMount();
    _fragments = mount.fragments;
    _table = mount.table;
    if (_table != null) {
      final offset = widget.tableFocus?.offset ?? widget.initialTableOffset;
      _tableHorizontal = ScrollController(
        initialScrollOffset: offset.dx,
        keepScrollOffset: false,
      )..addListener(_tableScrolled);
      _tableVertical = ScrollController(
        initialScrollOffset: offset.dy,
        keepScrollOffset: false,
      )..addListener(_tableScrolled);
    }
    widget.onMounted(widget.view, _fragments, _table);
  }

  void _tableScrolled() {
    final horizontal = _tableHorizontal!, vertical = _tableVertical!;
    if (horizontal.hasClients && vertical.hasClients) {
      widget.onTableOffsetChanged(Offset(horizontal.offset, vertical.offset));
    }
  }

  @override
  void didUpdateWidget(covariant _NativeMountedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.keepAlive != oldWidget.keepAlive) updateKeepAlive();
    final focus = widget.tableFocus;
    if (focus == null || focus == oldWidget.tableFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.tableFocus != focus ||
          _table?.isActive != true ||
          !widget.isTableFocusCurrent(focus.request)) {
        return;
      }
      final horizontal = _tableHorizontal!, vertical = _tableVertical!;
      if (!horizontal.hasClients || !vertical.hasClients) return;
      if (horizontal.offset != focus.offset.dx) {
        horizontal.jumpTo(focus.offset.dx);
      }
      if (vertical.offset != focus.offset.dy) vertical.jumpTo(focus.offset.dy);
    });
  }

  @override
  bool get wantKeepAlive => widget.keepAlive;

  bool get _warmImagesReady =>
      _fragments.every((fragment) => fragment.hasRenderedImages) &&
      (_table == null ||
          (_warmTableWindow?.isCurrent == true &&
              _warmTableWindow!.slices.every(
                (slice) => slice.fragments.every(
                  (fragment) => fragment.hasRenderedImages,
                ),
              )));

  void _imageDisplayChanged() {
    widget.onImageDisplayChanged();
    _refreshWarmDisplay();
  }

  void _refreshWarmDisplay() {
    if (widget.active || _warmRefreshScheduled || !mounted) return;
    _warmRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmRefreshScheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TickerMode(
      // Warm images need their first decoded frame before animation pauses.
      enabled: widget.active || !_warmImagesReady,
      child: ExcludeFocus(
        excluding: !widget.active,
        child: IgnorePointer(
          ignoring: !widget.active,
          child: ExcludeSemantics(
            excluding: !widget.active,
            child: _buildBody(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_fragments.any((fragment) => !fragment.isActive)) {
      return const SizedBox.shrink();
    }
    final view = widget.view;
    final table = _table;
    final surface = _buildSurface(view.snapshot, view.pageIndex, _fragments);
    if (table == null) return surface;
    if (!table.isActive) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        surface,
        Positioned.fromRect(
          rect: view.snapshot[view.pageIndex].table!.bounds,
          child: ReaderOwnedTapRegion(
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (notification) {
                if (notification.dragDetails != null) widget.onTableUserDrag();
                return false;
              },
              child: ForumBodyTableBookViewport(
                layout: table.layout,
                horizontalController: _tableHorizontal!,
                verticalController: _tableVertical!,
                onReadyChanged: widget.onTableReadyChanged,
                onWindowChanged: (window) {
                  _warmTableWindow = window;
                  widget.onTableWindowChanged(window);
                  _refreshWarmDisplay();
                },
                onFailure: (error, _) => widget.onTableFailure(error),
                buildSlice: (context, area, page, fragments) => _buildSurface(
                  area.snapshot,
                  page,
                  fragments,
                  compactHeight: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSurface(
    ForumBodyTextPageSnapshot snapshot,
    int page,
    List<ForumBodyPreparedTextFragment> fragments, {
    bool compactHeight = false,
  }) {
    final l10n = widget.onCollapseToggle == null
        ? null
        : Localizations.of<AppLocalizations>(context, AppLocalizations);
    return ForumBodyTextPageSurface.prepared(
      snapshot: snapshot,
      pageIndex: page,
      layoutId: snapshot.layoutId,
      fragments: fragments,
      compactHeight: compactHeight,
      selectionEnabled: widget.selectionEnabled,
      imageHost: widget.imageHost,
      collapseLabels: l10n == null
          ? null
          : ForumHtmlCollapseLabels(
              fallbackTitle: l10n.threadHtmlCollapseContent,
              expandedSemanticsLabel: l10n.threadHtmlCollapseExpanded,
              collapsedSemanticsLabel: l10n.threadHtmlCollapseCollapsed,
            ),
      onCollapseToggle: widget.onCollapseToggle,
      onImageDisplayChanged: (_, _) => _imageDisplayChanged(),
      onInlineImageDisplayChanged: (_, _, _) => _imageDisplayChanged(),
      onImageTap: widget.onImageTap == null
          ? null
          : (fragment) => widget.onImageTap?.call(fragment, null),
      onInlineImageTap: widget.onImageTap == null
          ? null
          : (fragment, binding) => widget.onImageTap?.call(fragment, binding),
      onImageLayoutResolved: (fragment, layout) =>
          widget.onImageLayoutResolved?.call(widget.view, fragment, layout),
      onInlineImageLayoutResolved: widget.onInlineImageLayoutResolved == null
          ? null
          : (fragment, binding, layout) => widget.onInlineImageLayoutResolved
                ?.call(widget.view, fragment, binding, layout),
      onLinkTap: widget.onLinkTap == null
          ? null
          : (url) => widget.onLinkTap?.call(
              url,
              () => mounted && fragments.every((fragment) => fragment.isActive),
            ),
      onSourceLongPress: widget.onTextSelection == null
          ? null
          : (_, selection) => widget.onTextSelection!(
              selection,
              () => mounted && fragments.every((fragment) => fragment.isActive),
            ),
    );
  }

  @override
  void dispose() {
    _tableHorizontal?.dispose();
    _tableVertical?.dispose();
    _table?.close();
    widget.onUnmounted(widget.view);
    // Surface normally releases these; also handle an abandoned/unpainted cell.
    for (final fragment in _fragments) {
      fragment.close();
    }
    super.dispose();
  }
}
