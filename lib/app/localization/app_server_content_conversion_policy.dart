import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

/// Resolves the explicit application language preference into the conversion
/// direction used by native server-content surfaces.
///
/// [AppLanguage.system] intentionally maps to [TextConversionMode.none]. The
/// device locale controls application-owned copy, but must not implicitly
/// transform server content.
final class AppServerContentConversionPolicy {
  const AppServerContentConversionPolicy();

  TextConversionMode resolve(AppLanguage language) {
    return switch (language) {
      AppLanguage.system => TextConversionMode.none,
      AppLanguage.simplifiedChinese => TextConversionMode.toSimplified,
      AppLanguage.traditionalChinese => TextConversionMode.toTraditional,
    };
  }
}
