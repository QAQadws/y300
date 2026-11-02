import 'dart:collection';

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_text_request.dart';
import '../paragraph/forum_body_text_request_preparation.dart';
import 'forum_body_ruby_container_background.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_root_box.dart';
import 'forum_body_ruby_tree_input.dart';

/// Numeric postorder snapshot. It has no native handles, paint, source hit or
/// coverage authority; a readable binding must qualify actual current leaves.
final class ForumBodyRubyTreeMetrics {
  ForumBodyRubyTreeMetrics._(List<ForumBodyRubyTreeNodeMetrics> nodes)
    // The worker seals before transferring this append-only list.
    : nodes = UnmodifiableListView(nodes);
  final List<ForumBodyRubyTreeNodeMetrics> nodes;
  ForumBodyRubyChildMetrics get box => nodes.last.box!;
}

sealed class ForumBodyRubyTreeNodeMetrics {
  const ForumBodyRubyTreeNodeMetrics();
  ForumBodyRubyChildMetrics? get box;
}

final class ForumBodyRubyTreeTextMetrics extends ForumBodyRubyTreeNodeMetrics {
  const ForumBodyRubyTreeTextMetrics(this.box);
  @override
  final ForumBodyRubyChildMetrics? box;
}

final class ForumBodyRubyTreeContainerMetrics
    extends ForumBodyRubyTreeNodeMetrics {
  ForumBodyRubyTreeContainerMetrics({
    required this.font,
    required this.backgroundFont,
    required this.frame,
    this.group,
  }) : box = ForumBodyRubyChildMetrics(
         bounds: Offset.zero & frame.size,
         alphabeticBaseline: frame.baseline,
       );
  final ForumBodyRubyRootFontBox font;
  final ForumBodyRubyContainerFontBox? backgroundFont;
  final ForumBodyRubyAtomFrame frame;
  final ForumBodyRubyGroupMetrics? group;
  @override
  final ForumBodyRubyChildMetrics box;
}

enum _State { active, ready, transferred, failed, closed }

/// Original nested IR -> native leaf/font geometry -> the one shared numeric
/// stack. Temporary leases are released before the next child is acquired.
/// This is metric planning, not the visible tree's aggregate pin admission.
final class ForumBodyRubyTreeMetricsPreparation {
  ForumBodyRubyTreeMetricsPreparation({
    required ForumBodyRubyTreeInput input,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _input = input,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _scaler = textScaler,
       _additionalOwned = additionalOwnedLeases;
  ForumBodyRubyTreeInput? _input;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  TextScaler? _scaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyTextRequestPreparation? _member;
  ForumBodyRubyGroupGeometry? _geometry;
  ForumBodyRubyRootFontBox? _font;
  ForumBodyRubyContainerFontBox? _backgroundFont;
  List<ForumBodyRubyTreeNodeMetrics> _nodes = [];
  ForumBodyRubyTreeMetrics? _result;
  var _state = _State.active;
  bool _operating = false;
  bool _waiting = false;
  bool _cacheMiss = false;
  int _rank = -1;
  bool get isReady => _state == _State.ready;
  bool get cacheMiss => _cacheMiss;
  int get measuredNodeCount => _nodes.length;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    if (_member != null) ..._member!.nativeLeases,
  ];
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _member?.lastBudgetRejection;

  ForumBodyRubyGroupPreparationStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      final cache = _cache!;
      final builds = cache.layoutBuildCount;
      final pictures = cache.pictureBuildCount;
      var units = 0;
      var captured = 0;
      _waiting = false;
      _cacheMiss = false;
      while (!isReady && units < maxParts) {
        final beforeNodes = _nodes.length;
        final used = _advanceNode(cachedOnly);
        units += used;
        captured += _nodes.length - beforeNodes;
        _guard();
        if (_waiting ||
            _cacheMiss ||
            used == 0 ||
            cache.layoutBuildCount != builds ||
            cache.pictureBuildCount != pictures) {
          break;
        }
      }
      return ForumBodyRubyGroupPreparationStep(
        partsPrepared: captured,
        layoutsBuilt: cache.layoutBuildCount - builds,
        picturesBuilt: cache.pictureBuildCount - pictures,
        partsInspected: 0,
        formatUnitsPrepared: units,
        isReady: isReady,
        waitingForLayoutBudget: _waiting,
      );
    });
  }

  int _advanceNode(bool cachedOnly) {
    if (_nodes.length == _input!.nodes.length) {
      _result = ForumBodyRubyTreeMetrics._(_nodes);
      _state = _State.ready;
      return 1;
    }
    final node = _input!.nodes[_nodes.length];
    if (node is ForumBodyRubyTreeText) {
      if (!node.needsNative) {
        _nodes.add(const ForumBodyRubyTreeTextMetrics(null));
        return 1;
      }
      return _read(node.request, cachedOnly, (lease) {
        _nodes.add(
          ForumBodyRubyTreeTextMetrics(
            ForumBodyRubyChildMetrics.measure(
              cache: _cache!,
              lease: lease,
              content: node.content,
            ),
          ),
        );
      });
    }
    final container = node as ForumBodyRubyTreeContainer;
    if (_font == null) {
      return _read(
        ForumBodyTextRequest.paragraph(container.font.fontStrut),
        cachedOnly,
        (lease) {
          _font = ForumBodyRubyRootFontBox(
            input: container.font,
            height: lease.layout.height,
            alphabeticBaseline: lease.layout.alphabeticBaseline,
          );
        },
      );
    }
    final background = container.background;
    if (background != null && _backgroundFont == null) {
      return _read(
        ForumBodyTextRequest.paragraph(background.fontStrut),
        cachedOnly,
        (lease) {
          _backgroundFont = ForumBodyRubyContainerFontBox(
            background: background,
            height: lease.layout.height,
            alphabeticBaseline: lease.layout.alphabeticBaseline,
          );
        },
      );
    }
    switch (container) {
      case ForumBodyRubyTreeFrame(:final child):
        final box = _nodes[child].box!;
        _seal(
          _font!.enclose(
            childSize: box.bounds.size,
            childBaseline: box.alphabeticBaseline,
          ),
        );
      case ForumBodyRubyTreeGroup(:final base, :final annotations):
        if (_geometry == null) {
          _geometry = ForumBodyRubyGroupGeometry(
            annotations: [
              for (final annotation in annotations)
                (
                  hasAnnotation:
                      annotation.child != null &&
                      _nodes[annotation.child!].box != null,
                  gap: 0.0,
                  side: annotation.side,
                ),
            ],
            maxWidth: _input!.maxWidth,
          );
          return 1;
        }
        if (_rank == -1) {
          _geometry!.addBase(_nodes[base].box!);
          _rank = 0;
          return 1;
        }
        if (_rank < annotations.length) {
          final child = annotations[_rank++].child;
          _geometry!.addAnnotation(child == null ? null : _nodes[child].box);
          return 1;
        }
        if (!_geometry!.isReady) {
          return _geometry!.advance(maxParts: 1);
        }
        final measured = _geometry!.takeMetrics();
        _seal(
          _font!.enclose(
            childSize: measured.size,
            childBaseline: measured.baseline,
          ),
          group: measured,
        );
    }
    return 1;
  }

  void _seal(ForumBodyRubyAtomFrame frame, {ForumBodyRubyGroupMetrics? group}) {
    _nodes.add(
      ForumBodyRubyTreeContainerMetrics(
        font: _font!,
        backgroundFont: _backgroundFont,
        frame: frame,
        group: group,
      ),
    );
    _geometry?.close();
    _geometry = null;
    _font = null;
    _backgroundFont = null;
    _rank = -1;
  }

  int _read(
    ForumBodyTextRequest request,
    bool cachedOnly,
    void Function(ForumBodyTextLease) capture,
  ) {
    final member = _member ??= ForumBodyTextRequestPreparation(
      cache: _cache!,
      request: request,
      ensureOwner: _guard,
      preparePaint: false,
      textScaler: _scaler!,
      width: _input!.maxWidth,
      additionalOwnedLeases: _additionalOwned,
    );
    final step = member.advance(cachedOnly: cachedOnly);
    _waiting = step.waiting;
    _cacheMiss = step.cacheMiss;
    _guard();
    if (member.isReady) {
      final lease = member.takeLease();
      member.close();
      _member = null;
      try {
        _guard();
        capture(lease);
      } finally {
        lease.release();
      }
    }
    return step.units;
  }

  ForumBodyRubyTreeMetrics takeMetrics() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Ruby tree metrics are incomplete');
    final result = _result!;
    _state = _State.transferred;
    _dropOwner();
    return result;
  });
  void _guard() {
    if (_state != _State.active && !isReady) {
      throw StateError('Ruby tree metrics are retired');
    }
    _ensureOwner!();
    if ((_state != _State.active && !isReady) || _cache!.isClosed) {
      throw StateError('Ruby tree owner is retired');
    }
  }

  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Ruby tree preparation is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      _retire(_State.failed);
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _dropOwner() {
    _member?.close();
    _member = null;
    _geometry?.close();
    _geometry = null;
    _font = null;
    _backgroundFont = null;
    _result = null;
    _nodes = [];
    _input = null;
    _cache = null;
    _scaler = null;
    _ensureOwner = null;
    _additionalOwned = null;
  }

  void _retire(_State state) {
    if (_state != _State.active && !isReady) return;
    _state = state;
    _dropOwner();
  }

  void close() => _retire(_State.closed);
}
