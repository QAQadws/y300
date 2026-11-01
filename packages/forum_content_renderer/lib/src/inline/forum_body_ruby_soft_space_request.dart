import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_request.dart';
import '../style/forum_body_style_options.dart' show ForumBodyRubySide;
import 'forum_body_ruby_group_contract.dart';
import 'forum_body_ruby_container_background.dart';

typedef ForumBodyRubySoftSpaceMemberRequest = ({
  ForumBodyTextRequest request,
  int? annotationIndex,
  double gap,
});

/// Real whitespace at one original column edge, in base then annotation-rank
/// order. A null rank means actual base whitespace, not a synthetic base column.
/// An absent side has no request, empty text, font strut or native handle.
final class ForumBodyRubySoftSpaceRequest {
  ForumBodyRubySoftSpaceRequest({
    required this.beforeColumn,
    required List<ForumBodyRubySoftSpaceMemberRequest> members,
    required List<ForumBodyRubySide> sides,
    this.direction = TextDirection.ltr,
    this.maxWidth = 16384,
    this.background,
  }) : members = List.unmodifiable(members),
       sides = List.unmodifiable(sides),
       nativeRequests = List.unmodifiable(members.map((m) => m.request)) {
    if (beforeColumn <= 0 ||
        sides.isEmpty ||
        !maxWidth.isFinite ||
        maxWidth <= 0 ||
        maxWidth > 16384) {
      _invalid(ForumBodyRubyGroupFailure.geometry);
    }
    if (members.isEmpty) _invalid(ForumBodyRubyGroupFailure.content);
    final scope = members.first.request.content;
    background?.validateScope(scope);
    final seen = Set<ForumBodyParagraphContent>.identity();
    var previousRank = -1;
    for (final member in this.members) {
      final rank = member.annotationIndex ?? -1;
      if (rank < previousRank ||
          (member.annotationIndex != null && rank < 0) ||
          rank >= sides.length) {
        _invalid(ForumBodyRubyGroupFailure.geometry);
      }
      previousRank = rank;
      if (!member.gap.isFinite ||
          member.gap < 0 ||
          member.gap > 16384 ||
          (member.annotationIndex == null && member.gap != 0)) {
        _invalid(ForumBodyRubyGroupFailure.geometry);
      }
      final content = member.request.content;
      if (content.identity != scope.identity ||
          content.fontRevision != scope.fontRevision ||
          content.styleRevision != scope.styleRevision) {
        _invalid(ForumBodyRubyGroupFailure.scope);
      }
      if (content.isSourceFree ||
          !seen.add(content) ||
          content.layoutMode !=
              ForumBodyParagraphLayoutMode.intrinsicSingleLine ||
          content.projection.text.isEmpty ||
          !content.projection.text.runes.every((r) => r == 9 || r == 32)) {
        _invalid(ForumBodyRubyGroupFailure.content);
      }
    }
  }

  final int beforeColumn;
  final ForumBodyRubyContainerBackground? background;
  final List<ForumBodyRubySoftSpaceMemberRequest> members;
  final List<ForumBodyRubySide> sides;
  final TextDirection direction;
  final double maxWidth;
  final List<ForumBodyTextRequest> nativeRequests;
  int get nativeHandleCount => nativeRequests.length;

  ForumBodyRubySoftSpaceRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => ForumBodyRubySoftSpaceRequest(
    background: background,
    beforeColumn: beforeColumn,
    members: [
      for (final member in members)
        (
          request: map(member.request),
          annotationIndex: member.annotationIndex,
          gap: member.gap,
        ),
    ],
    sides: sides,
    direction: direction,
    maxWidth: maxWidth,
  );

  static Never _invalid(ForumBodyRubyGroupFailure failure) =>
      throw ForumBodyRubyGroupException(failure);
}
