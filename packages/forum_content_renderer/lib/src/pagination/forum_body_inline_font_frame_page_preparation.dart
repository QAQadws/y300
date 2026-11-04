import 'package:flutter/painting.dart';

import '../inline/forum_body_inline_font_frame_plan.dart';
import '../inline/forum_body_inline_paragraph_view.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import 'forum_body_text_page_binding.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_content.dart';

enum _FramePagePhase { measure, rows, children, visible, delivered }

/// Format-local state under the sole page transaction. Pure saved scene input
/// is prepared/probed first. Current source/resources are then reconstructed
/// and compared, so eviction never turns a numeric key into readable authority.
final class ForumBodyInlineFontFramePagePreparation {
  ForumBodyInlineFontFramePagePreparation({
    required ForumBodyInlinePageContent input,
    required this.fragment,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    required void Function() ensureVisibleOwner,
    required Iterable<ForumBodyNativeParagraphLease> Function() ownedPageLeases,
  }) : _hasParentPaint = input.fontFrames!.hasParentPaint(
         fragment.startLine,
         fragment.endLine,
       ),
       _input = input,
       _cache = cache,
       _scaler = textScaler,
       _ensureOwner = ensureOwner,
       _visibleOwner = ensureVisibleOwner,
       _owned = ownedPageLeases {
    try {
      _guard();
      input.nativeHandleCountFor(fragment);
    } catch (_) {
      close();
      rethrow;
    }
  }
  final ForumBodyTextPageFragment fragment;
  final bool _hasParentPaint;
  ForumBodyInlinePageContent? _input;
  ForumBodyParagraphCache? _cache;
  TextScaler? _scaler;
  void Function()? _ensureOwner, _visibleOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _owned;
  ForumBodyTextPictureInputComposition? _sceneWork;
  ForumBodyTextPictureInput? _scene;
  ForumBodyInlineFontFramePreparation? _measure;
  ForumBodyInlineFontFrameMeasurement? _measurement;
  ForumBodyInlineFontFrameViewPreparation? _visible;
  bool _closed = false;
  var _phase = _FramePagePhase.measure;
  int _row = 0, _atom = 0, _workCount = 0;
  int get workCount => _workCount;
  bool get isInputReady => !_closed && (_scene != null || !_hasParentPaint);
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (_measure != null) yield* _measure!.nativeLeases;
    if (_measurement != null) yield* _measurement!.nativeLeases;
    if (_visible != null) yield* _visible!.nativeLeases;
  }

  void advanceInput() {
    _guard();
    if (isInputReady) return;
    _sceneWork ??= ForumBodyTextPictureInputComposition.commandSteps(
      steps: _input!.fontFrames!.parentPictureSteps(
        fragment.startLine,
        fragment.endLine,
      ),
      ensureOwner: _guard,
      maxCommands: ForumBodyTextPictureInput.maximumCommands,
    );
    _sceneWork!.advance(maxParts: 1);
    if (_sceneWork!.isReady) {
      _scene = _sceneWork!.takeInput();
      _sceneWork = null;
    }
    _guard();
  }

  void includeSceneBudget(ForumBodyParagraphBudgetProbe probe) {
    _guard();
    if (!isInputReady) throw StateError('Font-frame page input is incomplete');
    if (_hasParentPaint) probe.includeTextPicture(_scene!);
    _guard();
  }

  ({bool cacheMiss, bool waiting, ForumBodyInlineParagraphView? view}) advance({
    required bool cachedOnly,
    required int maxParts,
  }) {
    _guard();
    if (!isInputReady || _phase == _FramePagePhase.delivered || maxParts <= 0) {
      throw StateError('Font-frame page is unavailable');
    }
    final cache = _cache!,
        builds = cache.layoutBuildCount,
        pictures = cache.pictureBuildCount;
    var used = 0;
    while (used < maxParts &&
        cache.layoutBuildCount == builds &&
        cache.pictureBuildCount == pictures) {
      final saved = _input!.fontFrames!;
      switch (_phase) {
        case _FramePagePhase.measure:
          _measure ??= ForumBodyInlineFontFramePreparation(
            input: saved.source,
            cache: cache,
            textScaler: _scaler!,
            ensureOwner: _guard,
            additionalOwnedLeases: _owned,
          );
          final step = _measure!.advance(
            maxParts: maxParts - used,
            cachedOnly: cachedOnly,
          );
          used += step.partsPrepared;
          _workCount += step.partsPrepared;
          if (_measure!.cacheMiss || step.waitingForLayoutBudget) {
            return (
              cacheMiss: _measure!.cacheMiss,
              waiting: step.waitingForLayoutBudget,
              view: null,
            );
          }
          if (!_measure!.isReady) break;
          _measurement = _measure!.takeMeasurement();
          _measure = null;
          final current = _measurement!.plan;
          if (!identical(saved.source, current.source) ||
              saved.width != current.width ||
              saved.height != current.height ||
              saved.lines.length != current.lines.length ||
              saved.allocation.input.reference.naturalInputIdentity !=
                  current.allocation.input.reference.naturalInputIdentity ||
              saved.paintReference.sourceInputIdentity !=
                  current.paintReference.sourceInputIdentity ||
              saved.hasParentPaint(fragment.startLine, fragment.endLine) !=
                  current.hasParentPaint(
                    fragment.startLine,
                    fragment.endLine,
                  ) ||
              saved.allocation.children.length !=
                  current.allocation.children.length) {
            _geometry();
          }
          _row = fragment.startLine;
          _phase = _FramePagePhase.rows;
        case _FramePagePhase.rows:
          if (_row < fragment.endLine) {
            final index = _row++,
                a = saved.lines[index],
                b = _measurement!.plan.lines[index];
            if (!forumBodyHaveSameParagraphLineInputs(a, b) ||
                a.top != b.top ||
                a.bottom != b.bottom ||
                a.baseline != b.baseline) {
              _geometry();
            }
          } else {
            _phase = _FramePagePhase.children;
          }
          used++;
          _workCount++;
        case _FramePagePhase.children:
          if (_atom < saved.allocation.children.length) {
            final index = _atom++,
                a = saved.allocation.children[index],
                b = _measurement!.plan.allocation.children[index];
            if (a != b) _geometry();
          } else {
            _visible = ForumBodyInlineFontFrameViewPreparation(
              measurement: _measurement!,
              cache: cache,
              textScaler: _scaler!,
              ensureOwner: _guard,
              ensureVisibleOwner: _visibleOwner,
              additionalOwnedLeases: _owned,
              startLine: fragment.startLine,
              endLine: fragment.endLine,
              expectedParentInput: _scene,
            );
            _measurement = null;
            _phase = _FramePagePhase.visible;
          }
          used++;
          _workCount++;
        case _FramePagePhase.visible:
          final step = _visible!.advance(
            maxParts: maxParts - used,
            cachedOnly: cachedOnly,
          );
          used += step.partsPrepared;
          _workCount += step.partsPrepared;
          if (_visible!.cacheMiss || step.waitingForLayoutBudget) {
            return (
              cacheMiss: _visible!.cacheMiss,
              waiting: step.waitingForLayoutBudget,
              view: null,
            );
          }
          if (!_visible!.isReady) break;
          final view = _visible!.takeView();
          _visible = null;
          _phase = _FramePagePhase.delivered;
          try {
            _guard();
            return (cacheMiss: false, waiting: false, view: view);
          } catch (_) {
            view.close();
            rethrow;
          }
        case _FramePagePhase.delivered:
          throw StateError('Font-frame page was delivered');
      }
      _guard();
    }
    return (cacheMiss: false, waiting: false, view: null);
  }

  static Never _geometry() => throw const ForumBodyTextPageSurfaceException(
    ForumBodyTextPageSurfaceFailure.geometry,
  );
  void _guard() {
    if (_closed) throw StateError('Font-frame page is retired');
    _ensureOwner!();
    if (_closed || _cache?.isClosed != false) {
      throw StateError('Font-frame page owner is retired');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _sceneWork?.close();
    _measure?.close();
    _measurement?.close();
    _visible?.close();
    _sceneWork = null;
    _scene = null;
    _measure = null;
    _measurement = null;
    _visible = null;
    _input = null;
    _cache = null;
    _scaler = null;
    _ensureOwner = null;
    _visibleOwner = null;
    _owned = null;
  }
}
