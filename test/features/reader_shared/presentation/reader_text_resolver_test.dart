import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/features/reader_shared/presentation/reader_text_resolver.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  final simplified = AppLocalizationsZh();
  final traditional = AppLocalizationsZhTw();

  test('localizes every shared image reader mode', () {
    for (final mode in ReaderModePreference.values) {
      expect(ReaderTextResolver.mode(simplified, mode), isNotEmpty);
      expect(ReaderTextResolver.mode(traditional, mode), isNotEmpty);
      expect(ReaderTextResolver.modeChoice(simplified, mode), isNotEmpty);
      expect(ReaderTextResolver.modeChoice(traditional, mode), isNotEmpty);
    }
    expect(
      ReaderTextResolver.mode(simplified, ReaderModePreference.ltr),
      '左到右',
    );
    expect(
      ReaderTextResolver.mode(traditional, ReaderModePreference.ltr),
      '由左至右',
    );
  });

  test('localizes every image export failure reason', () {
    for (final reason in ReaderImageExportFailureReason.values) {
      expect(ReaderTextResolver.exportFailure(simplified, reason), isNotEmpty);
      expect(ReaderTextResolver.exportFailure(traditional, reason), isNotEmpty);
    }
  });
}
