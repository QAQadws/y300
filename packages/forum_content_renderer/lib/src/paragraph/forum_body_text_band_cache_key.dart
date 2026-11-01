import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../inline/forum_body_text_band_content.dart';
import '../inline/forum_body_text_band_layout.dart';
import 'forum_body_paragraph_layout.dart';

/// Internal complete native input. Source-bound children never reuse a band's
/// glyphs using equal text alone. The public cache retains current lease metadata.
final class ForumBodyTextBandCacheKey {
  ForumBodyTextBandCacheKey(
    ForumBodyTextBandContent content,
    Map<double, double> effectiveScales,
    this.gutter,
  ) : identity = content.contexts.first.identity,
      fontRevision = content.contexts.first.fontRevision,
      styleRevision = content.contexts.first.styleRevision,
      direction = content.contexts.first.style.textDirection,
      alignment = content.contexts.first.style.textAlign,
      locale = content.contexts.first.style.textStyle.locale,
      paths = List.unmodifiable(content.contexts.map((item) => item.path)),
      spans = List.unmodifiable(content.contexts.map((item) => item.textSpan)),
      projections = List.unmodifiable(
        content.projection.children.map((item) => item.display),
      ),
      scales = List.unmodifiable(
        (effectiveScales.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
            .map((item) => (item.key, item.value)),
      ),
      backendRevision = ForumBodyParagraphLayout.backendRevision,
      layoutRevision = ForumBodyTextBandLayout.revision,
      inputRevision = ForumBodyTextBandContent.revision,
      displayRevision = HtmlDisplayTextProjection.revision,
      bandRevision = HtmlTextBandProjection.revision;

  final ForumBodyIdentity identity;
  final String fontRevision;
  final int styleRevision;
  final TextDirection direction;
  final TextAlign alignment;
  final Locale? locale;
  final List<String?> paths;
  final List<TextSpan> spans;
  final List<HtmlDisplayTextProjection> projections;
  final List<(double, double)> scales;
  final double gutter;
  final int backendRevision;
  final int layoutRevision;
  final int inputRevision;
  final int displayRevision;
  final int bandRevision;
  int get pictureReserve => projections.length * 4096;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ForumBodyTextBandCacheKey ||
        identity != other.identity ||
        fontRevision != other.fontRevision ||
        styleRevision != other.styleRevision ||
        direction != other.direction ||
        alignment != other.alignment ||
        locale != other.locale ||
        gutter != other.gutter ||
        backendRevision != other.backendRevision ||
        layoutRevision != other.layoutRevision ||
        inputRevision != other.inputRevision ||
        displayRevision != other.displayRevision ||
        bandRevision != other.bandRevision ||
        !listEquals(paths, other.paths) ||
        !listEquals(spans, other.spans) ||
        !listEquals(scales, other.scales) ||
        projections.length != other.projections.length) {
      return false;
    }
    for (var i = 0; i < projections.length; i++) {
      if (!projections[i].hasSameSourceMapping(other.projections[i])) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => _hashCode;
  late final int _hashCode = Object.hash(
    identity,
    fontRevision,
    styleRevision,
    direction,
    alignment,
    locale,
    gutter,
    backendRevision,
    layoutRevision,
    inputRevision,
    displayRevision,
    bandRevision,
    Object.hashAll(paths),
    Object.hashAll(spans),
    Object.hashAll(scales),
    Object.hashAll(projections.map((item) => item.sourceMappingHash)),
  );
}

int forumBodyTextBandMinimumBytes(ForumBodyTextBandContent content) =>
    4096 +
    content.textCodeUnits * 96 +
    content.runCount * 256 +
    content.contexts.length * (256 + 4096);
