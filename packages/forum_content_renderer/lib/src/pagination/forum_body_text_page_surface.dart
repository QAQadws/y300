import 'package:flutter/widgets.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_surface.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_binding.dart';

export 'forum_body_text_page_binding.dart'
    show ForumBodyTextPageSurfaceFailure, ForumBodyTextPageSurfaceException;

/// Paint an already composed page using already prepared leases. No shaping,
/// cache acquisition, HTML preparation or settings resolution occurs in build.
/// The Host guards owner/catalog identity and supplies the original content box
/// while reflow is pending. This validates the generation and fragment geometry.
///
/// Each concurrently mounted fragment needs its own lease. Mounted paragraph
/// surfaces own those leases; construction failure or an abandoned, unmounted
/// widget leaves cleanup with the caller. Ordinary rebuilds may reuse leases.
final class ForumBodyTextPageSurface extends StatelessWidget {
  factory ForumBodyTextPageSurface({
    Key? key,
    required ForumBodyTextPageSnapshot snapshot,
    required int pageIndex,
    required String layoutId,
    required List<ForumBodyParagraphLease> leases,
    void Function(
      ForumBodyTextPageFragment fragment,
      HtmlProjectedSourcePosition position,
    )?
    onSourceTap,
  }) {
    final page = validateForumBodyTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      leases: leases,
    );
    return ForumBodyTextPageSurface._(
      key,
      page,
      layoutId,
      snapshot.width,
      snapshot.height,
      List.unmodifiable(leases),
      onSourceTap,
    );
  }

  const ForumBodyTextPageSurface._(
    Key? key,
    this._page,
    this._layoutId,
    this._width,
    this._height,
    this._leases,
    this._onSourceTap,
  ) : super(key: key);
  final ForumBodyTextPage _page;
  final String _layoutId;
  final double _width;
  final double _height;
  final List<ForumBodyParagraphLease> _leases;
  final void Function(ForumBodyTextPageFragment, HtmlProjectedSourcePosition)?
  _onSourceTap;

  static Never _fail(ForumBodyTextPageSurfaceFailure failure) =>
      throw ForumBodyTextPageSurfaceException(failure);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.constrain(Size(_width, _height)) !=
          Size(_width, _height)) {
        _fail(ForumBodyTextPageSurfaceFailure.geometry);
      }
      return SizedBox(
        width: _width,
        height: _height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final (index, fragment) in _page.fragments.indexed)
              Positioned(
                key: ObjectKey(_leases[index]),
                left: fragment.left,
                top: fragment.top,
                width: fragment.width,
                height: fragment.height,
                child: ForumBodyParagraphSurface(
                  lease: _leases[index],
                  startLine: fragment.startLine,
                  endLine: fragment.endLine,
                  interactionIdentity: (
                    _layoutId,
                    _page.index,
                    fragment.paragraphIndex,
                    fragment.startLine,
                    fragment.endLine,
                    fragment.left,
                    fragment.top,
                  ),
                  onSourceTap: _onSourceTap == null
                      ? null
                      : (position) => _onSourceTap(fragment, position),
                ),
              ),
          ],
        ),
      );
    },
  );
}
