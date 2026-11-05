import 'package:flutter/painting.dart';

import '../document/forum_body_document.dart';
import '../html_rendering/forum_html_prepared_render_document.dart';
import '../pagination/forum_body_prepared_text_fragment.dart';
import '../pagination/forum_body_text_page_binding.dart';
import '../pagination/forum_body_text_page_composer.dart';
import '../table/forum_body_table_viewport.dart';
import 'forum_body_flow_text_anchor.dart';

typedef _ImageOccurrence = ({String path, int index, String url, String key});

typedef _ImageFrame = ({_ImageOccurrence occurrence, Rect bounds, Rect clip});

/// An image occurrence and a fraction within its mounted layout frame.
/// This geometry does not establish decoded pixel readiness.
final class ForumBodyFlowImageAnchor implements ForumBodyFlowSourceAnchor {
  const ForumBodyFlowImageAnchor._(this._identity, this._image, this.fraction);

  final ForumBodyIdentity _identity;
  final _ImageOccurrence _image;
  final Offset fraction;
  int get index => _image.index;

  @override
  bool matchesHint(ForumBodyTextPageFragment fragment) =>
      fragment.imagePaths.contains(_image.path);

  @override
  Rect? locate({
    required ForumBodyTextPageSnapshot snapshot,
    required int page,
    required List<ForumBodyPreparedTextFragment> fragments,
  }) {
    if (snapshot.identity != _identity) return null;
    final layout = validateForumBodyPreparedTextPageBinding(
      snapshot: snapshot,
      pageIndex: page,
      layoutId: snapshot.layoutId,
      fragments: fragments,
    );
    for (final frame in _frames(layout, snapshot.width, fragments)) {
      if (frame.occurrence != _image) continue;
      final point =
          frame.bounds.topLeft +
          Offset(
            frame.bounds.width * fraction.dx,
            frame.bounds.height * fraction.dy,
          );
      if (frame.clip.contains(point)) return Rect.fromPoints(point, point);
    }
    return null;
  }

  /// Samples the leading visible point of a readable image in a settled
  /// table viewport. The immutable position does not borrow its delivery.
  static ({ForumBodyFlowImageAnchor anchor, Rect bounds, String areaPath})?
  firstVisibleInTable(ForumBodyTableVisibleWindow window) {
    if (!window.isCurrent) return null;
    for (final slice in window.slices) {
      final snapshot = slice.area.snapshot;
      final visible = window.bounds.intersect(slice.bounds);
      if (visible.isEmpty) continue;
      for (final frame in _frames(
        snapshot[slice.page],
        snapshot.width,
        slice.fragments,
      )) {
        final origin = slice.bounds.topLeft;
        final shown = frame.clip.shift(origin).intersect(visible);
        if (shown.isEmpty) continue;
        final bounds = frame.bounds.shift(origin);
        final point = shown.topLeft;
        return (
          anchor: ForumBodyFlowImageAnchor._(
            snapshot.identity,
            frame.occurrence,
            Offset(
              (point.dx - bounds.left) / bounds.width,
              (point.dy - bounds.top) / bounds.height,
            ),
          ),
          bounds: Rect.fromPoints(point, point),
          areaPath: slice.area.element.path,
        );
      }
    }
    return null;
  }
}

Iterable<_ImageFrame> _frames(
  ForumBodyTextPage page,
  double width,
  List<ForumBodyPreparedTextFragment> fragments,
) sync* {
  final pageClip = Rect.fromLTWH(0, 0, width, page.usedHeight);
  for (final (i, fragment) in page.fragments.indexed) {
    final delivery = fragments[i];
    if (fragment.imagePaths.isEmpty || !delivery.isActive) continue;
    final origin = Offset(fragment.left, fragment.top);
    final clip = pageClip.intersect(
      origin & Size(fragment.width, fragment.height),
    );
    final body = delivery is ForumBodyPreparedListItemFragment
        ? delivery.body
        : delivery;
    switch (body) {
      case ForumBodyPreparedImageFragment():
        final input = body.content.input;
        if (input.isSticker) continue;
        final bounds = body.content.frame.imageRect.shift(origin);
        yield _frame(input.element.path, input.entry, bounds, clip);
      case ForumBodyPreparedInlineFragment():
        for (final image in body.view.images.values) {
          final input = image.input;
          final entry = input.entry;
          if (!image.isActive || entry == null) continue;
          yield _frame(
            input.element.path,
            entry,
            image.rect.shift(origin),
            clip,
          );
        }
      default:
        break;
    }
  }
}

_ImageFrame _frame(
  String path,
  ForumHtmlReadableImageEntry entry,
  Rect bounds,
  Rect clip,
) => (
  occurrence: (
    path: path,
    index: entry.index,
    url: entry.url,
    key: entry.cacheKey,
  ),
  bounds: bounds,
  clip: bounds.intersect(clip),
);
