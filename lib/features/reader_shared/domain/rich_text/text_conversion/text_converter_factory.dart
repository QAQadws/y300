import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/opencc_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

/// Returns a [TextConverter] for the given [mode].
///
/// [TextConversionMode.none] → [IdentityTextConverter] (const, zero deps).
/// Other modes → [OpenccTextConverter] (MethodChannel, main isolate only).
TextConverter resolveTextConverter(TextConversionMode mode) {
  return switch (mode) {
    TextConversionMode.none => const IdentityTextConverter(),
    TextConversionMode.toSimplified => const OpenccTextConverter(
      mode: TextConversionMode.toSimplified,
    ),
    TextConversionMode.toTraditional => const OpenccTextConverter(
      mode: TextConversionMode.toTraditional,
    ),
  };
}

/// Riverpod provider exposing the converter for the current conversion mode.
/// Callers watch this and await [TextConverter.convertHtml] before planning.
final textConverterProvider =
    Provider.family<TextConverter, TextConversionMode>(
      (ref, mode) => resolveTextConverter(mode),
    );
