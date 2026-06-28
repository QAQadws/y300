import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

/// Pass-through converter — returns input unchanged.
final class IdentityTextConverter implements TextConverter {
  const IdentityTextConverter();

  @override
  String get id => 'conv:none';

  @override
  TextConversionMode get mode => TextConversionMode.none;

  @override
  Future<String> convertHtml(String html) async => html;
}
