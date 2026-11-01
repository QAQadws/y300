import 'forum_body_ruby_group_contract.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_soft_space_request.dart';

void validateForumBodyRubySoftSpaceTarget(
  ForumBodyRubySoftSpaceRequest request,
  ForumBodyRubySoftSpaceMetrics metrics,
) {
  if (request.direction != metrics.direction ||
      metrics.size.width > request.maxWidth ||
      request.members.length != metrics.members.length ||
      request.sides.length != metrics.level.annotations.length) {
    _invalid();
  }
}

void validateForumBodyRubySoftSpaceRank(
  ForumBodyRubySoftSpaceRequest request,
  ForumBodyRubySoftSpaceMetrics metrics,
  int rank,
) {
  if (request.sides[rank] != metrics.level.annotations[rank].side) _invalid();
}

void validateForumBodyRubySoftSpaceMember(
  ForumBodyRubySoftSpaceRequest request,
  ForumBodyRubySoftSpaceMetrics metrics,
  int index,
) {
  final source = request.members[index];
  final target = metrics.members[index].input;
  if (source.annotationIndex != target.annotationIndex ||
      source.gap != target.font.gap ||
      !target.font.hasAnnotation ||
      (source.annotationIndex != null &&
          request.sides[source.annotationIndex!] != target.font.side)) {
    _invalid();
  }
}

Never _invalid() =>
    throw const ForumBodyRubyGroupException(ForumBodyRubyGroupFailure.geometry);
