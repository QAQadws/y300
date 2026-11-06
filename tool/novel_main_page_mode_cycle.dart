import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_sheet_widgets.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';

import 'novel_main_page_profile_observation.dart';

/// Drives the mounted reader toolbar and display sheet. Observations use the
/// actual settled view and the synthetic persistence boundary.
final class NovelProfileModeCycle {
  NovelProfileModeCycle({
    required this.readerRoute,
    required this.waitForReader,
    required this.nextFrame,
    required this.loadProgress,
    required this.recordStep,
  });

  final ModalRoute<void> readerRoute;
  final Future<ProfileReaderObservation> Function(
    bool Function(ProfileReaderObservation),
  )
  waitForReader;
  final Future<void> Function() nextFrame;
  final Future<NovelReadingProgress?> Function() loadProgress;
  final void Function(String) recordStep;
  late final NovelReadingProgress _saved;
  late final NovelReaderTextAnchor _anchor;
  late ProfileReaderObservation _vertical;

  Future<void> seed(ProfileReaderObservation initial) async {
    recordStep('seed_turn');
    final turn = initial.overlay?.onRightTap;
    if (turn == null || initial.count < 3) {
      throw StateError('The mode fixture requires an interior page');
    }
    turn();
    final paged = await waitForReader(
      (value) => value.ready && value.businessConfirmed && value.page == 1,
    );
    final clock = Stopwatch()..start();
    while (true) {
      final saved = await loadProgress();
      if (saved != null && saved.pageIndex == 1) {
        _saved = saved;
        break;
      }
      if (clock.elapsed > const Duration(seconds: 5)) {
        throw TimeoutException('Initial page turn was not saved');
      }
      await nextFrame();
    }

    final seedView = paged.nativeController!.visibleView!;
    _vertical = await _toVertical(paged);
    recordStep('seed_anchor');
    _anchor = await _visibleFlowAnchor(_vertical);
    if (seedView.coverage.locate(_anchor) == null) {
      throw StateError('Initial scroll source is outside the seed page');
    }
    await _checkSavedPosition();
  }

  Future<ProfileReaderObservation> roundTrip() async {
    final previousFlow = _vertical.nativeFlow!;
    final previousSession = _vertical.flowSession!;
    final source = previousFlow.logicalSelectionSource!;
    var flowRetired = false;
    final remove = source.onRetired(() => flowRetired = true);
    final ProfileReaderObservation paged;
    try {
      recordStep('page_settings');
      await _selectMode(_vertical, NovelReaderFlowMode.pagedLtr);
      recordStep('paged_handoff');
      paged = await waitForReader(
        (value) =>
            value.ready &&
            value.complete &&
            value.frontmost &&
            value.persistedFlowMode == NovelReaderFlowMode.pagedLtr &&
            identical(value.businessController, _vertical.businessController) &&
            _stableOwner(value, _vertical) &&
            !previousFlow.mounted &&
            previousSession.isClosed &&
            flowRetired,
      );
    } finally {
      remove();
    }
    recordStep('paged_anchor');
    final coverage = paged.nativeController!.visibleView!.coverage;
    if (coverage.hasClippedGlyphs || coverage.locate(_anchor) == null) {
      throw StateError('Returned page does not cover the actual scroll source');
    }
    _vertical = await _toVertical(paged);
    recordStep('flow_anchor');
    final anchor = await _visibleFlowAnchor(_vertical);
    if (anchor.episodeId != _anchor.episodeId ||
        anchor.nodeId != _anchor.nodeId ||
        anchor.textOffset != _anchor.textOffset ||
        anchor.formatVersion != _anchor.formatVersion ||
        anchor.textIdentity != _anchor.textIdentity) {
      throw StateError('The settled scroll anchor drifted across modes');
    }
    await _checkSavedPosition();
    return _vertical;
  }

  Future<ProfileReaderObservation> _toVertical(
    ProfileReaderObservation paged,
  ) async {
    final previous = paged.nativeController!;
    recordStep('flow_settings');
    await _selectMode(paged, NovelReaderFlowMode.vertical);
    recordStep('flow_handoff');
    return waitForReader((value) {
      final scroll = value.nativeFlow?.widget.scrollController;
      return value.flowReady &&
          value.persistedFlowMode == NovelReaderFlowMode.vertical &&
          identical(value.businessController, paged.businessController) &&
          _stableOwner(value, paged) &&
          profilePagedControllerRetired(previous) &&
          scroll != null &&
          scroll.hasClients &&
          scroll.offset > 0 &&
          !scroll.position.isScrollingNotifier.value;
    });
  }

  bool _stableOwner(
    ProfileReaderObservation current,
    ProfileReaderObservation previous,
  ) {
    final owner = current.nativeOwner;
    return owner != null &&
        identical(owner, previous.nativeOwner) &&
        !owner.isClosed &&
        owner.activeCacheHandles == 1 &&
        owner.retainedCacheGenerations == 1 &&
        owner.preparationCache.inFlightCount == 0;
  }

  Future<NovelReaderTextAnchor> _visibleFlowAnchor(
    ProfileReaderObservation observation,
  ) async {
    final token = NovelReaderPaginationCancellationToken();
    try {
      final source = await observation.nativeFlow!
          .captureVisibleSource(token)
          .timeout(const Duration(seconds: 5));
      if (source == null || !source.anchor.hasCanonicalTextOffset) {
        throw StateError(
          'The settled scroll body did not expose a canonical source',
        );
      }
      return source.anchor;
    } finally {
      token.cancel();
    }
  }

  Future<void> _checkSavedPosition() async {
    recordStep('saved_progress');
    if (!identical(await loadProgress(), _saved)) {
      throw StateError(
        'Passive mode switching rewrote the saved reading position',
      );
    }
  }

  Future<void> _selectMode(
    ProfileReaderObservation from,
    NovelReaderFlowMode target,
  ) async {
    final overlay = from.overlay!;
    final display = overlay.bottomBar.actions.singleWhere(
      (action) => action.id == 'display',
    );
    final navigator = readerRoute.navigator!;
    overlay.controller!.showMenu();
    try {
      await nextFrame();
      display.onPressed();
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 5)) {
        await nextFrame();
        final control = _mountedControl(navigator);
        if (control == null) continue;
        final sheet = ModalRoute.of(control);
        if (sheet == null ||
            !sheet.isCurrent ||
            sheet.animation?.status != AnimationStatus.completed) {
          continue;
        }
        final segment =
            control.widget as ReaderSegmentControl<NovelReaderFlowMode>;
        if (!segment.enabled ||
            !segment.values.contains(target) ||
            segment.value == target) {
          throw StateError(
            'Requested mode is unavailable in the display sheet',
          );
        }
        segment.onChanged(target);
        navigator.pop();
        await sheet.completed.timeout(const Duration(seconds: 5));
        return;
      }
      throw TimeoutException('Display settings did not mount');
    } finally {
      if (readerRoute.isActive && !readerRoute.isCurrent) {
        navigator.popUntil((route) => identical(route, readerRoute));
      }
    }
  }

  Element? _mountedControl(NavigatorState navigator) {
    Element? result;
    void visit(Element element) {
      if (result != null) return;
      if (element.widget case Offstage(offstage: true)) return;
      if (element.widget case ReaderSegmentControl<NovelReaderFlowMode>(
        key: ValueKey<String>(value: 'novel-reader-flow-mode-control'),
      )) {
        result = element;
        return;
      }
      element.visitChildElements(visit);
    }

    navigator.overlay!.context.visitChildElements(visit);
    return result;
  }
}
