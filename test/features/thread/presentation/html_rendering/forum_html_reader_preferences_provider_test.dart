import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';

void main() {
  test('defaults keep author font sizes and use standard typography', () {
    final defaults = ForumHtmlReaderPreferences.defaults();

    expect(defaults.typography, RichTextTypography.standard);
    expect(defaults.conversionMode, TextConversionMode.none);
    expect(defaults.preserveAuthorFontSize, isTrue);
  });

  test(
    'repository loads supported values and ignores obsolete color keys',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'forum_html_reader_font_scale': 9.0,
        'forum_html_reader_line_height_scale': 0.1,
        'forum_html_reader_paragraph_spacing': 99.0,
        'forum_html_reader_conversion_mode': 'toTraditional',
        'forum_html_reader_preserve_author_font_size': false,
        'forum_html_reader_preserve_author_color': false,
        'forum_html_reader_preserve_author_background': false,
      });
      final repository = SharedPrefsForumHtmlReaderPreferencesRepository();

      final loaded = await repository.load();

      expect(loaded.typography.fontScale, 2.0);
      expect(loaded.typography.lineHeightScale, 1.0);
      expect(loaded.typography.paragraphSpacing, 40.0);
      expect(loaded.conversionMode, TextConversionMode.toTraditional);
      expect(loaded.preserveAuthorFontSize, isFalse);
    },
  );

  test('repository saves values to shared preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = SharedPrefsForumHtmlReaderPreferencesRepository();

    await repository.save(
      ForumHtmlReaderPreferences.defaults().copyWith(
        typography: const RichTextTypography(
          fontScale: 1.25,
          lineHeightScale: 1.8,
          paragraphSpacing: 18,
        ),
        conversionMode: TextConversionMode.toSimplified,
        preserveAuthorFontSize: false,
      ),
    );
    final loaded = await repository.load();

    expect(loaded.typography.fontScale, 1.25);
    expect(loaded.typography.lineHeightScale, 1.8);
    expect(loaded.typography.paragraphSpacing, 18);
    expect(loaded.conversionMode, TextConversionMode.toSimplified);
    expect(loaded.preserveAuthorFontSize, isFalse);
  });

  test('controller updates all preference fields', () async {
    final repository = _FakeForumHtmlReaderPreferencesRepository();
    final container = ProviderContainer(
      overrides: [
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          repository,
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(forumHtmlReaderPreferencesControllerProvider.future);
    final controller = container.read(
      forumHtmlReaderPreferencesControllerProvider.notifier,
    );

    await controller.setConversionMode(TextConversionMode.toTraditional);
    await controller.setFontScale(1.3);
    await controller.setLineHeightScale(1.9);
    await controller.setParagraphSpacing(24);
    await controller.setPreserveAuthorFontSize(false);

    final state = container
        .read(forumHtmlReaderPreferencesControllerProvider)
        .value!;
    expect(state.conversionMode, TextConversionMode.toTraditional);
    expect(state.typography.fontScale, 1.3);
    expect(state.typography.lineHeightScale, 1.9);
    expect(state.typography.paragraphSpacing, 24);
    expect(state.preserveAuthorFontSize, isFalse);
    expect(repository.saved.last, state);

    await controller.reset();
    expect(
      container.read(forumHtmlReaderPreferencesControllerProvider).value,
      ForumHtmlReaderPreferences.defaults(),
    );
  });
}

class _FakeForumHtmlReaderPreferencesRepository
    implements ForumHtmlReaderPreferencesRepository {
  ForumHtmlReaderPreferences current = ForumHtmlReaderPreferences.defaults();
  final saved = <ForumHtmlReaderPreferences>[];

  @override
  Future<ForumHtmlReaderPreferences> load() async => current;

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    current = preferences;
    saved.add(preferences);
  }
}
