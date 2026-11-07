import 'package:flutter/painting.dart';

import '../inline/forum_body_paragraph_frame.dart';
import '../inline/forum_body_emphasis_paragraph_metrics.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_content.dart';

/// Format-local state borrowed by the sole page transaction. Its pure scene
/// plan is built during aggregate admission; current source/fonts are bound
/// afterwards. Delivery transfers the view, not this temporary worker's guard.
final class ForumBodyEmphasisPagePreparation {
  ForumBodyEmphasisPagePreparation({
    required ForumBodyEmphasisPageContent input,
    required this.fragment,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
    required void Function() ensureVisibleOwner,
    required Iterable<ForumBodyNativeParagraphLease> Function() ownedPageLeases,
  }) : _input = input,
       _cache = cache,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner,
       _ownedPageLeases = ownedPageLeases;
  final ForumBodyTextPageFragment fragment;
  ForumBodyEmphasisPageContent? _input;
  ForumBodyParagraphCache? _cache;
  TextScaler? _textScaler;
  void Function()? _ensureOwner, _ensureVisibleOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _ownedPageLeases;
  ForumBodyEmphasisFragmentInputPreparation? _plan;
  ForumBodyEmphasisFragmentInput? _scene;
  ForumBodyEmphasisFragmentPreparation? _visible;
  bool _closed = false, _delivered = false;
  int _workCount = 0;
  int get workCount => _workCount;
  bool get isInputReady => _scene != null;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _visible?.nativeLeases ?? const [];

  void advanceInput() {
    _guard();
    if (isInputReady) return;
    _plan ??= _input!.openFragmentInput(
      fragment: fragment,
      ensureOwner: _guard,
    );
    _plan!.advance(maxParts: 1);
    if (_plan!.isReady) {
      _scene = _plan!.takeInput();
      _plan = null;
    }
    _guard();
  }

  void includeSceneBudget(ForumBodyParagraphBudgetProbe probe) {
    _guard();
    if (!isInputReady) {
      throw StateError('Emphasis page scene input is incomplete');
    }
    probe.includeTextPicture(_scene!.pictureInput);
    _guard();
  }

  ({bool cacheMiss, bool waiting, ForumBodyEmphasisFragmentLayout? view})
  advance({required bool cachedOnly, required int maxParts}) {
    _guard();
    if (!isInputReady || _delivered) {
      throw StateError('Emphasis page input is not available for binding');
    }
    final work = _visible ??= ForumBodyEmphasisFragmentPreparation(
      input: _scene!,
      cache: _cache!,
      ensureOwner: _guard,
      ensureVisibleOwner: _ensureVisibleOwner!,
      width: _scene!.width,
      expectedTextScaler: _textScaler!,
      additionalOwnedLeases: _ownedPageLeases,
    );
    final step = work.advance(maxParts: maxParts, cachedOnly: cachedOnly);
    _workCount += step.partsPrepared;
    _guard();
    if (!work.isReady) {
      return (
        cacheMiss: work.cacheMiss,
        waiting: step.waitingForLayoutBudget,
        view: null,
      );
    }
    final view = work.takeLayout();
    _visible = null;
    _delivered = true;
    try {
      view.ensureActive();
      _guard();
      return (cacheMiss: false, waiting: false, view: view);
    } catch (_) {
      view.close();
      rethrow;
    }
  }

  void _guard() {
    if (_closed) throw StateError('Emphasis page preparation is retired');
    _ensureOwner!();
    if (_closed || _cache?.isClosed != false) {
      throw StateError('Emphasis page owner is retired');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _plan?.close();
    _plan = null;
    _visible?.close();
    _visible = null;
    _scene = null;
    _input = null;
    _cache = null;
    _textScaler = null;
    _ensureOwner = null;
    _ensureVisibleOwner = null;
    _ownedPageLeases = null;
  }
}
