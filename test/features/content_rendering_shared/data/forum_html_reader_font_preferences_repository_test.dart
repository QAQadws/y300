import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_key_names.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/content_rendering_shared/data/repositories/shared_prefs_forum_html_reader_preferences_repository.dart';
import 'package:y300/features/fonts/fonts.dart' show FontIdentity;
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

void main() {
  final fontId = 'a' * 64;

  test(
    'old typography settings load with the system font without a font write',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PreferenceKeyNames.legacyThreadTextFontScale: 1.3,
        PreferenceKeyNames.legacyThreadTextLineHeightScale: 1.9,
        PreferenceKeyNames.forumHtmlReaderConversionMode: 'toTraditional',
        PreferenceKeyNames.forumHtmlReaderPreserveAuthorFontSize: false,
      });
      final loaded = await SharedPrefsForumHtmlReaderPreferencesRepository()
          .load();
      final stored = await SharedPreferences.getInstance();

      expect(loaded.fontFamily, FontIdentity.system);
      expect(loaded.typography.fontScale, 1.3);
      expect(loaded.typography.lineHeightScale, 1.9);
      expect(loaded.conversionMode, TextConversionMode.toTraditional);
      expect(loaded.preserveAuthorFontSize, isFalse);
      expect(
        stored.containsKey(PreferenceKeyNames.forumHtmlReaderFontFamily),
        isFalse,
      );
      expect(
        stored.getInt(PreferenceKeyNames.forumHtmlReaderMigrationVersion),
        1,
      );
    },
  );

  test(
    'a content ID survives repository recreation with all other values',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final choice = ForumHtmlReaderPreferences.defaults().copyWith(
        fontFamily: fontId,
        typography: const RichTextTypography(
          fontScale: 1.4,
          lineHeightScale: 1.8,
          paragraphSpacing: ForumHtmlReaderPreferences.defaultParagraphSpacing,
        ),
        conversionMode: TextConversionMode.toSimplified,
        preserveAuthorFontSize: false,
      );
      await SharedPrefsForumHtmlReaderPreferencesRepository().save(choice);
      final loaded = await SharedPrefsForumHtmlReaderPreferencesRepository()
          .load();
      final stored = await SharedPreferences.getInstance();

      expect(loaded, choice);
      expect(
        stored.getString(PreferenceKeyNames.forumHtmlReaderFontFamily),
        fontId,
      );
    },
  );

  for (final raw in <Object>[
    'serif',
    'Y300ImportedFont_${'a' * 64}',
    '../font.ttf',
    r'C:\Downloads\font.otf',
    'A' * 64,
    'a' * 63,
    '',
    17,
    true,
  ]) {
    test(
      'invalid stored font $raw falls back without changing unrelated values',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          PreferenceKeyNames.forumHtmlReaderFontFamily: raw,
          PreferenceKeyNames.forumHtmlReaderFontScale: 1.7,
          PreferenceKeyNames.forumHtmlReaderMigrationVersion: 1,
        });
        final loaded = await SharedPrefsForumHtmlReaderPreferencesRepository()
            .load();
        final stored = await SharedPreferences.getInstance();

        expect(loaded.fontFamily, FontIdentity.system);
        expect(loaded.typography.fontScale, 1.7);
        expect(stored.get(PreferenceKeyNames.forumHtmlReaderFontFamily), raw);
      },
    );
  }

  test('saving an invalid font normalizes only the font choice', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final choice = ForumHtmlReaderPreferences.defaults().copyWith(
      fontFamily: 'Y300ImportedFont_$fontId',
      preserveAuthorFontSize: false,
      conversionMode: TextConversionMode.toTraditional,
    );
    final repository = SharedPrefsForumHtmlReaderPreferencesRepository();
    await repository.save(choice);

    expect(
      await repository.load(),
      choice.copyWith(fontFamily: FontIdentity.system),
    );
  });

  test('font selection changes preference identity but keeps preparation options neutral', () {
    final baseline = ForumHtmlReaderPreferences.defaults();
    final imported = baseline.copyWith(fontFamily: fontId);

    expect(imported, isNot(baseline));
    expect(imported.copyWith(), imported);
    expect(imported.copyWith().hashCode, imported.hashCode);
    expect(imported.renderOptions, baseline.renderOptions);
    expect(imported.copyWith(fontFamily: FontIdentity.system), baseline);
  });

  test('forum font writes preserve the independent novel snapshot', () async {
    const novelSnapshot =
        '{"schemaVersion":1,"fontFamily":"system","fontSize":24}';
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferenceKeyNames.novelReaderSnapshotV1: novelSnapshot,
    });
    await SharedPrefsForumHtmlReaderPreferencesRepository().save(
      ForumHtmlReaderPreferences.defaults().copyWith(fontFamily: fontId),
    );
    final stored = await SharedPreferences.getInstance();

    expect(
      stored.getString(PreferenceKeyNames.novelReaderSnapshotV1),
      novelSnapshot,
    );
    expect(
      stored.getString(PreferenceKeyNames.forumHtmlReaderFontFamily),
      fontId,
    );
  });
}
