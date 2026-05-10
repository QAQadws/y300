import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

class ThreadPostHtml extends StatelessWidget {
  const ThreadPostHtml({
    super.key,
    required this.data,
    this.imageHeaderBuilder,
  });

  final String data;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    return Html(
      data: data,
      extensions: [
        _ThreadPostImageExtension(headerBuilder: imageHeaderBuilder),
      ],
    );
  }
}

class _ThreadPostImageExtension extends HtmlExtension {
  _ThreadPostImageExtension({
    required this.headerBuilder,
    ForumPostDomExtractor? extractor,
  }) : _extractor = extractor ?? const ForumPostDomExtractor();

  final ImageRequestHeaderBuilder? headerBuilder;
  final ForumPostDomExtractor _extractor;

  @override
  Set<String> get supportedTags => const <String>{'img'};

  @override
  bool matches(ExtensionContext context) {
    return context.elementName == 'img' &&
        _normalizedSource(context.attributes) != null;
  }

  @override
  InlineSpan build(ExtensionContext context) {
    final src = _normalizedSource(context.attributes);
    if (src == null) {
      return const TextSpan(text: '');
    }

    final imageStyle = Style(
      width: _parseDimension(context.attributes['width']),
      height: _parseHeight(context.attributes['height']),
    ).merge(context.styledElement!.style);

    // flutter_html 的默认网络图片渲染只能接收固定 headers。这里改为逐图
    // 交给 LibraryCachedImage，让 Cookie 继续按图片 URL host 隔离。
    return WidgetSpan(
      alignment: context.style!.verticalAlign.toPlaceholderAlignment(context.style!.display),
      baseline: TextBaseline.alphabetic,
      child: CssBoxWidget(
        style: imageStyle,
        childIsReplaced: true,
        child: LibraryCachedImage(
          imageUrl: src,
          fit: BoxFit.contain,
          width: imageStyle.width?.value,
          height: imageStyle.height?.value,
          placeholder: const SizedBox.shrink(),
          headerBuilder: headerBuilder,
        ),
      ),
    );
  }

  String? _normalizedSource(Map<String, String> attributes) {
    const sourceAttributes = <String>[
      'src',
      'data-src',
      'data-original',
      'file',
    ];
    for (final attribute in sourceAttributes) {
      final raw = attributes[attribute]?.trim();
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final normalized = _extractor.normalizeImageSource(raw);
      final uri = normalized == null ? null : Uri.tryParse(normalized);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return normalized;
      }
    }
    return null;
  }

  Width? _parseDimension(String? raw) {
    final value = double.tryParse(raw?.trim() ?? '');
    return value == null ? null : Width(value);
  }

  Height? _parseHeight(String? raw) {
    final value = double.tryParse(raw?.trim() ?? '');
    return value == null ? null : Height(value);
  }
}
