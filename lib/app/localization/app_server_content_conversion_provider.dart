import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/localization/app_server_content_conversion_policy.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

/// Provides the effective B-class conversion mode for native server content.
///
/// Loading and failure states deliberately fall back to raw content. A device
/// locale is only used to resolve A-class application UI in [Y300App]; it must
/// not implicitly enable server-content conversion here.
final appServerContentConversionModeProvider = Provider<TextConversionMode>((
  ref,
) {
  final settings = ref.watch(appAppearanceControllerProvider).asData?.value;
  if (settings == null) {
    return TextConversionMode.none;
  }
  return const AppServerContentConversionPolicy().resolve(
    settings.languagePreference,
  );
});
