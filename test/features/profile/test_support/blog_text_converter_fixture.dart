import 'dart:async';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

/// Deterministic replacement dictionary, including a deliberately convertible
/// author name so tests can prove identity labels are excluded from conversion.
final class BlogTextConverterFixture implements TextConverter {
  BlogTextConverterFixture({
    this.mode = TextConversionMode.toTraditional,
    this.gate,
  });
  @override
  final TextConversionMode mode;
  final Completer<void>? gate;
  final inputs = <String>[];
  bool fail = false;
  @override
  String get id => 'blog-fixture:${mode.name}';
  @override
  Future<String> convertHtml(String html) async {
    inputs.add(html);
    await gate?.future;
    if (fail) throw StateError('fixture conversion failure');
    const replacements = {
      '标题': '標題',
      '正文': '內文',
      '评论': '評論',
      '分类': '分類',
      '摘要': '摘錄',
      '分钟前': '分鐘前',
      '作者': '作者變換',
    };
    var result = html;
    for (final entry in replacements.entries) {
      result = mode == TextConversionMode.toSimplified
          ? result.replaceAll(entry.value, entry.key)
          : result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}
