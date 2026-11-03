import 'dart:collection';

import 'package:flutter/painting.dart';

import '../pagination/forum_body_text_page_content.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_emphasis_text_geometry.dart';
import 'forum_body_inline_emphasis_row_placement.dart';
import 'forum_body_ruby_atom_plan.dart';
import 'forum_body_ruby_tree_input.dart';

/// Complete replanned child formats and actual physical parent-slot inputs.
/// The page still has its original trim snapshot: the containing format must
/// acquire and verify the final actual parent before allocation or delivery.
/// No lease, cache, callback, scene readiness or source coverage is retained.
final class ForumBodyInlineEmphasisChildrenPlan {
  ForumBodyInlineEmphasisChildrenPlan._(
    this.placement,
    this.page,
    Set<int> changedAtoms,
  ) : changedAtoms = UnmodifiableSetView(changedAtoms);
  static const revision = 1;
  final ForumBodyInlineEmphasisRowPlacement placement;
  final ForumBodyInlinePageContent page;
  final Set<int> changedAtoms;
  bool get hasChanges => changedAtoms.isNotEmpty;
}

/// Reuses the one root-shift placement and marker-plan writers. Unshifted
/// opaque/glue children keep their exact original formats and dimensions.
/// Each part visits an atom, advances one existing pure writer, or publishes;
/// no font sampling, native request, image or caller handle is acquired here.
final class ForumBodyInlineEmphasisChildrenPlanPreparation {
  ForumBodyInlineEmphasisChildrenPlanPreparation({
    required ForumBodyInlineEmphasisRowPlacement placement,
    required void Function() ensureOwner,
    this.maxAtoms = 512,
  }) : _placement = placement,
       _ensureOwner = ensureOwner {
    if (maxAtoms < 0) throw ArgumentError.value(maxAtoms);
    try {
      _guard();
      final count = placement.input.page.rubyAtoms.length;
      if (count > maxAtoms) _fail(ForumBodyEmphasisGeometryFailure.limit);
      if (placement.childShifts.length != count ||
          placement.input.children.length != count) {
        _fail(ForumBodyEmphasisGeometryFailure.source);
      }
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxAtoms;
  ForumBodyInlineEmphasisRowPlacement? _placement;
  void Function()? _ensureOwner;
  ForumBodyRubyTreeEmphasisPlacementPreparation? _shift;
  ForumBodyRubyTreeEmphasisPlanPreparation? _plan;
  List<ForumBodyRubyAtomPlan>? _atoms = [];
  List<PlaceholderDimensions>? _dimensions = [];
  Set<int>? _changed = {};
  ForumBodyInlineEmphasisChildrenPlan? _result;
  int _index = 0;
  bool _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Mixed child replanning is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final placement = _placement!, page = placement.input.page;
        if (_shift case final work?) {
          used += work.advance(maxParts: maxParts - used);
          _guard();
          if (work.isReady) {
            final shifted = work.takePlacement();
            _shift = null;
            _plan = ForumBodyRubyTreeEmphasisPlanPreparation(
              placement: shifted,
              ensureOwner: _guard,
            );
          }
        } else if (_plan case final work?) {
          used += work.advance(maxParts: maxParts - used);
          _guard();
          if (work.isReady) {
            final plan = work.takePlan();
            _plan = null;
            final original =
                page.rubyAtoms[_index] as ForumBodyRubyTreeEmphasisAtomPlan;
            final dimensions =
                (page.rootFonts[_index]?.enclose(
                          childSize: plan.frame.size,
                          childBaseline: plan.frame.baseline,
                        ) ??
                        plan.frame)
                    .dimensions;
            // Vertical root decorations cannot change a parent's wrap input.
            // Do not round widths or manufacture a replacement placeholder.
            if (dimensions.size.width != page.dimensions[_index].size.width) {
              _fail(ForumBodyEmphasisGeometryFailure.boxes);
            }
            _atoms!.add(
              ForumBodyRubyAtomPlan.emphasisTree(
                request: original.request,
                format: plan,
              ),
            );
            _dimensions!.add(dimensions);
            _changed!.add(_index++);
          }
        } else if (_index < page.rubyAtoms.length) {
          final atom = page.rubyAtoms[_index],
              band = placement.input.children[_index],
              shift = placement.childShifts[_index];
          if (band == null) {
            if (!page.trimmedAtomIndices.contains(_index) || shift != null) {
              _fail(ForumBodyEmphasisGeometryFailure.source);
            }
          } else if (!identical(band.source, atom) ||
              band.atomIndex != _index) {
            _fail(ForumBodyEmphasisGeometryFailure.source);
          }
          if (shift == null) {
            _atoms!.add(atom);
            _dimensions!.add(page.dimensions[_index++]);
          } else {
            if (atom is! ForumBodyRubyTreeEmphasisAtomPlan ||
                !identical(shift.original, atom.format.placement)) {
              _fail(ForumBodyEmphasisGeometryFailure.source);
            }
            _shift = ForumBodyRubyTreeEmphasisPlacementPreparation(
              input: shift.original.input,
              rootShift: shift,
              ensureOwner: _guard,
            );
          }
          used++;
        } else {
          final children = ForumBodyInlinePageContent.atoms(
            content: page.content,
            dimensions: _dimensions!,
            rubyAtoms: _atoms!,
            trimmedAtomIndices: page.trimmedAtomIndices,
            containerBackgrounds: page.containerBackgrounds,
            rootFonts: page.rootFonts,
            layoutMode: page.layoutMode,
          );
          _result = ForumBodyInlineEmphasisChildrenPlan._(
            placement,
            children,
            _changed!,
          );
          _atoms = null;
          _dimensions = null;
          _changed = null;
          used++;
        }
        _guard();
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyInlineEmphasisChildrenPlan takePlan() {
    if (_operating) throw StateError('Mixed child replanning is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Mixed child replanning is incomplete');
      final result = _result!;
      close();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_closed) throw StateError('Mixed child replanning is retired');
    _ensureOwner!();
    if (_closed) throw StateError('Mixed child replan owner is retired');
  }

  void close() {
    _closed = true;
    _shift?.close();
    _shift = null;
    _plan?.close();
    _plan = null;
    _placement = null;
    _ensureOwner = null;
    _atoms = null;
    _dimensions = null;
    _changed = null;
    _result = null;
  }
}

Never _fail(ForumBodyEmphasisGeometryFailure failure) =>
    throw ForumBodyEmphasisGeometryException(failure);
