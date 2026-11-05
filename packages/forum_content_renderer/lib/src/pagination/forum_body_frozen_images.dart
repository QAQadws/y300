import '../document/forum_body_document.dart';
import '../inline/forum_body_inline_image_input.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_image_frame.dart';

/// Share immutable source inputs between intrinsic measurement and layout.
final class ForumBodyFrozenImages {
  ForumBodyFrozenImages(this._blockResolver, this._inlineResolver);

  ForumBodyImageResolver? _blockResolver;
  ForumBodyInlineImageResolver? _inlineResolver;
  final _blocks = <ForumBodyElement, ForumBodyImageInput?>{};
  final _inlines = <ForumBodyElement, ForumBodyInlineImageInput?>{};
  bool _closed = false;

  ForumBodyImageInput? block(
    ForumBodyIdentity identity,
    ForumBodyElement image,
  ) => _capture(_blocks, image, () => _blockResolver?.call(identity, image));

  ForumBodyInlineImageInput? inline(
    ForumBodyIdentity identity,
    ForumBodyElement image,
    ForumBodyResolvedStyle style,
  ) => _capture(
    _inlines,
    image,
    () => _inlineResolver?.call(identity, image, style),
  );

  T? _capture<T>(
    Map<ForumBodyElement, T?> values,
    ForumBodyElement image,
    T? Function() read,
  ) {
    if (_closed) throw StateError('Scoped image inputs are retired');
    if (values.containsKey(image)) return values[image];
    final value = read();
    if (_closed) throw StateError('Scoped image inputs are retired');
    return values[image] = value;
  }

  void close() {
    _closed = true;
    _blockResolver = null;
    _inlineResolver = null;
    _blocks.clear();
    _inlines.clear();
  }
}
