import 'package:flutter/painting.dart';

import '../inline/forum_body_text_band_content.dart';
import 'forum_body_native_request.dart';
import 'forum_body_paragraph_cache.dart';
import 'forum_body_paragraph_content.dart';

/// Immutable input for cooperative text preparation. Requests own no lease or
/// native resource. Cached acquisition never shapes or prepares child pictures.
sealed class ForumBodyTextRequest extends ForumBodyNativeRequest {
  const ForumBodyTextRequest._();
  factory ForumBodyTextRequest.paragraph(ForumBodyParagraphContent content) =
      ForumBodyParagraphTextRequest;
  factory ForumBodyTextRequest.bandChild({
    required ForumBodyTextBandContent band,
    required int childIndex,
    double? gutter,
  }) = ForumBodyTextBandChildRequest;
  ForumBodyParagraphContent get content;
  @override
  ForumBodyTextLease? acquire(
    ForumBodyParagraphCache cache, {
    required double width,
    required TextScaler textScaler,
    required bool cachedOnly,
  });
}

final class ForumBodyParagraphTextRequest extends ForumBodyTextRequest {
  const ForumBodyParagraphTextRequest(this.content) : super._();
  @override
  final ForumBodyParagraphContent content;
  @override
  ForumBodyParagraphLease? acquire(
    ForumBodyParagraphCache cache, {
    required double width,
    required TextScaler textScaler,
    required bool cachedOnly,
  }) => cachedOnly
      ? cache.tryAcquireCached(
          content: content,
          width: width,
          textScaler: textScaler,
        )
      : cache.acquire(content: content, width: width, textScaler: textScaler);
  @override
  void includeBudget(
    ForumBodyParagraphBudgetProbe probe, {
    required double width,
    required TextScaler textScaler,
    int minimumLineCount = 1,
  }) => probe.include(
    content: content,
    width: width,
    minimumLineCount: minimumLineCount,
    textScaler: textScaler,
  );
}

final class ForumBodyTextBandChildRequest extends ForumBodyTextRequest {
  ForumBodyTextBandChildRequest({
    required this.band,
    required this.childIndex,
    this.gutter,
  }) : super._() {
    RangeError.checkValidIndex(childIndex, band.contexts, 'childIndex');
  }
  final ForumBodyTextBandContent band;
  final int childIndex;
  final double? gutter;
  @override
  ForumBodyParagraphContent get content => band.contexts[childIndex];
  @override
  ForumBodyTextBandChildLease? acquire(
    ForumBodyParagraphCache cache, {
    required double width,
    required TextScaler textScaler,
    required bool cachedOnly,
  }) => cachedOnly
      ? cache.tryAcquireBandChildCached(
          content: band,
          childIndex: childIndex,
          textScaler: textScaler,
          gutter: gutter,
        )
      : cache.acquireBandChild(
          content: band,
          childIndex: childIndex,
          textScaler: textScaler,
          gutter: gutter,
        );
  @override
  void includeBudget(
    ForumBodyParagraphBudgetProbe probe, {
    required double width,
    required TextScaler textScaler,
    int minimumLineCount = 1,
  }) {
    // One intrinsic child cannot promise more than one line. The probe already
    // counts the complete shared band rather than undercounting this alias.
    RangeError.checkValueInInterval(minimumLineCount, 0, 1, 'minimumLineCount');
    probe.includeBandChild(
      content: band,
      childIndex: childIndex,
      textScaler: textScaler,
      gutter: gutter,
    );
  }
}
