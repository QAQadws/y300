import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

/// Document-level text conversion strategy.
///
/// Implementations must be safe to use as a cache-key discriminator: two
/// converters with the same [id] must produce identical output for the same
/// input. [convertHtml] is async (OpenCC uses a MethodChannel) — callers must
/// await it before preparing the display HTML or parsing semantic documents.
///
/// Conversion runs once at the HTML input boundary so rendered content,
/// copied text and reader semantics consume the same display source.
abstract interface class TextConverter {
  /// Stable identifier that enters the render cache key.
  /// Must differ when the output would differ (different mode or dictionary).
  String get id;

  TextConversionMode get mode;

  /// Convert a full HTML string and return the result.
  /// For the identity converter this is a no-op returning the same string.
  Future<String> convertHtml(String html);
}
