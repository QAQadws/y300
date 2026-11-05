part of 'novel_reader_native_flow_host.dart';

final class _FlowTextNavigation {
  _FlowTextNavigation(this.request);

  final NovelReaderAnchorNavigationRequest request;
  final token = NovelReaderPaginationCancellationToken();
  late final Timer deadline;
  _FlowRun? run;
  bool scheduled = false;
  bool needsPrefix = true;
  bool applyingOffset = false;
  _FlowTableKey? table;
  ForumBodyTableVisibleWindow? window;
  Completer<void>? _publication;

  Future<void> waitForPrefix(ForumBodyTextPageSnapshot seen) =>
      identical(run!.prefix, seen)
      ? token.waitFor((_publication ??= Completer<void>()).future)
      : Future.value();

  void published() {
    _publication?.complete();
    _publication = null;
  }

  void close() {
    deadline.cancel();
    token.cancel();
    window = null;
    published();
  }
}

extension on NovelReaderNativeFlowHostState {
  bool get _navigationActive => widget.activity?.value ?? true;

  void _replaceNavigation() {
    _retireNavigation();
    final request = widget.navigationRequest;
    if (request == null) return;
    final navigation = _navigation = _FlowTextNavigation(request);
    navigation.deadline = Timer(
      const NovelReaderPaginationPerformancePolicy().targetPageWait,
      () {
        if (identical(_navigation, navigation)) {
          _finishNavigation(NovelReaderNavigationOutcome.unavailable);
        }
      },
    );
    _scheduleNavigation();
  }

  void _navigationActivityChanged() {
    if (_navigationActive) {
      _scheduleNavigation();
    } else if (_navigation?.run != null) {
      _retireNavigation();
    }
  }

  void _scheduleNavigation() {
    final navigation = _navigation;
    if (navigation == null ||
        navigation.run != null ||
        navigation.scheduled ||
        !_navigationActive) {
      return;
    }
    navigation.scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigation.scheduled = false;
      if (!mounted ||
          !identical(_navigation, navigation) ||
          !_navigationActive) {
        return;
      }
      final run = _displayed;
      final scroll = widget.scrollController;
      if (_error != null || _emptyBody || widget.restoreReflowOffset == null) {
        _finishNavigation(NovelReaderNavigationOutcome.unavailable);
      } else if (run != null &&
          _interactive(run) &&
          run.reflow == null &&
          scroll.hasClients) {
        if (scroll.position.isScrollingNotifier.value) {
          _retireNavigation();
          return;
        }
        navigation.run = run;
        run.demand.update(targetPending: true, pageIndex: 0);
        unawaited(_runNavigation(navigation, run, scroll));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _retireNavigation() =>
      _finishNavigation(NovelReaderNavigationOutcome.retired);

  void _finishNavigation(NovelReaderNavigationOutcome outcome) {
    final navigation = _navigation;
    if (navigation == null) return;
    _navigation = null;
    navigation.close();
    final run = navigation.run;
    if (run != null && _current(run)) {
      run.demand.update(targetPending: !run.ready, pageIndex: 0);
    }
    final request = navigation.request;
    void report() {
      if (mounted && identical(widget.navigationRequest, request)) {
        widget.onNavigationFinished?.call(request, outcome);
      }
    }

    if (outcome == NovelReaderNavigationOutcome.arrived) {
      // Verification completed after layout. Publish the position before any
      // subsequent user input can change the viewport that supplied the proof.
      report();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => report());
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  Future<void> _runNavigation(
    _FlowTextNavigation navigation,
    _FlowRun run,
    ScrollController scroll,
  ) async {
    final position = scroll.position;
    var pixels = position.pixels;
    bool current() =>
        _current(run) &&
        identical(_displayed, run) &&
        identical(_navigation, navigation) &&
        _navigationActive &&
        scroll.hasClients &&
        identical(scroll.position, position) &&
        !position.isScrollingNotifier.value &&
        (navigation.applyingOffset || position.pixels == pixels);

    var outcome = NovelReaderNavigationOutcome.unavailable;
    try {
      final anchor = navigation.request.anchor;
      final chapter = run.scope!.chapter;
      final source = chapter.anchors
          .sourceRanges(NovelReaderTextRange(anchor, anchor.textOffset + 1))
          .firstOrNull;
      if (source == null) return;

      // Use the outer table's source range for both dedicated and floated
      // deliveries. A table envelope only admits a probe, never a jump.
      String? tablePath;
      for (final table in chapter.document.tableElements) {
        if (table.source.runeStart <= source.startRune &&
            source.startRune < table.source.runeEnd &&
            (tablePath == null || table.path.length < tablePath.length)) {
          tablePath = table.path;
        }
      }
      final token = navigation.token;
      const scheduler = NovelReaderNativeWorkScheduler();
      var start = 0;
      NovelReaderNativeFlowPoint? point;
      while (current()) {
        final prefix = run.prefix!;
        point ??= await _probeFlowAnchor(run, anchor, tablePath, start, token);
        if (!current()) return;
        start = prefix.length;
        final match = point;
        if (match == null) {
          if (prefix.isComplete) return;
          await navigation.waitForPrefix(prefix);
          continue;
        }

        final frame = tablePath == null
            ? null
            : prefix[match.slice].tableFrames.firstWhere(
                (frame) => frame.path == tablePath,
              );
        final height = _readableHeight(position);
        if (height <= 0 || match.bounds.height > height) return;
        final topInTable = frame?.bounds.top ?? 0.0;
        final bodyOffset =
            run.extentBefore(match.slice) +
            topInTable +
            match.bounds.top -
            widget.viewportInsets.top;
        if (!prefix.isComplete &&
            run.extent < bodyOffset + position.viewportDimension) {
          await navigation.waitForPrefix(prefix);
          continue;
        }
        navigation.needsPrefix = false;
        run.demand.update(targetPending: !run.ready, pageIndex: match.slice);

        // Apply the offset only after the new prefix is laid out by the same
        // sliver. The source driver can continue on the same layout session.
        await scheduler.nextFrame(token);
        if (!current()) return;
        if (frame != null) {
          final key = navigation.table = (slice: match.slice, path: frame.path);
          navigation.window =
              run.pendingTables[key]?.window ?? run.tablePositions[key]?.window;
          final offset = match.bounds.left
              .clamp(
                0.0,
                math.max(0.0, frame.contentSize.width - frame.bounds.width),
              )
              .toDouble();
          if (!ForumBodyFlowSliver.setTableOffset(
            run.bodyKey,
            session: run.session!,
            slice: match.slice,
            path: frame.path,
            offset: offset,
          )) {
            return;
          }
        }
        navigation.applyingOffset = true;
        final restored = await token.waitFor(
          widget.restoreReflowOffset!(() {
            final top = _bodyTop(run);
            return top == null ? null : top + bodyOffset;
          }, current),
        );
        pixels = position.pixels;
        navigation.applyingOffset = false;
        if (!restored || !current()) return;
        if (await _verifyNavigation(
              navigation,
              run,
              position,
              match.slice,
              frame,
              current,
            ) &&
            current()) {
          outcome = NovelReaderNavigationOutcome.arrived;
        }
        return;
      }
    } on Object {
      // Retired or unreadable deliveries cannot confirm navigation.
    } finally {
      if (identical(_navigation, navigation)) {
        _finishNavigation(
          current() ? outcome : NovelReaderNavigationOutcome.retired,
        );
      }
    }
  }

  Future<bool> _verifyNavigation(
    _FlowTextNavigation navigation,
    _FlowRun run,
    ScrollPosition position,
    int slice,
    ForumBodyTextPageTable? table,
    bool Function() current,
  ) async {
    const scheduler = NovelReaderNativeWorkScheduler();
    final anchor = navigation.request.anchor;
    final token = navigation.token;
    while (current()) {
      if (table == null) {
        final window = _bodyBoundary(run)?.borrowTextWindow();
        if (window != null &&
            window.slices.any((item) => item.index == slice)) {
          final point = await _sampleSource(
            run,
            position,
            token,
            preferred: anchor,
            slice: slice,
          );
          if (window.isCurrent) return point != null;
        }
      } else {
        final key = navigation.table!;
        final reported = navigation.window;
        final window = reported?.isCurrent == true
            ? reported
            : run.pendingTables[key]?.window ?? run.tablePositions[key]?.window;
        final top = _bodyTop(run);
        if (window?.isCurrent == true && top != null) {
          final tableTop = top + run.extentBefore(slice) + table.bounds.top;
          final proof = await NovelReaderNativeTableWindowProof.prepare(
            window: window!,
            anchors: run.scope!.chapter.anchors,
            scheduler: scheduler,
            token: token,
            preferred: anchor,
            viewportClip: Rect.fromLTWH(
              window.bounds.left,
              position.pixels + widget.viewportInsets.top - tableTop,
              window.bounds.width,
              _readableHeight(position),
            ),
          );
          if (proof?.isCurrent == true) return proof!.matchesPreferred;
        }
      }
      await scheduler.nextFrame(token);
    }
    return false;
  }
}
