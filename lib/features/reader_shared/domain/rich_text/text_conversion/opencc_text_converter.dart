import 'package:flutter_open_chinese_convert/flutter_open_chinese_convert.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

/// OpenCC-backed converter via flutter_open_chinese_convert.
///
/// [convertHtml] delegates to [ChineseConverter.convert] which runs on the
/// platform channel (main isolate only). Pre-convert the HTML string before
/// passing to the synchronous thread/novel planner.
///
/// [id] encodes the package version and direction so that a dictionary or
/// direction change automatically invalidates the render cache.
final class OpenccTextConverter implements TextConverter {
  const OpenccTextConverter({required this.mode});

  @override
  final TextConversionMode mode;

  /// Package version baked into the id so a dependency bump busts the cache.
  static const String _packageVersion = '0.9';

  @override
  String get id {
    final direction = mode == TextConversionMode.toTraditional ? 's2t' : 't2s';
    return 'opencc:$_packageVersion:$direction';
  }

  @override
  Future<String> convertHtml(String html) async {
    if (html.isEmpty) return html;
    final option = mode == TextConversionMode.toTraditional ? S2T() : T2S();
    return ChineseConverter.convert(html, option);
  }
}
