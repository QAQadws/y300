import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';

void main() {
  test('defaults use the production HTML typography baseline', () {
    final defaults = ForumHtmlReaderPreferences.defaults();

    expect(defaults.typography.fontScale, 1.15);
    expect(defaults.typography.lineHeightScale, 1.5);
    expect(defaults.typography.paragraphSpacing, 12);
    expect(defaults.conversionMode, TextConversionMode.none);
    expect(defaults.preserveAuthorFontSize, isTrue);
  });

  test('repository uses production defaults when storage is empty', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = SharedPrefsForumHtmlReaderPreferencesRepository();

    final loaded = await repository.load();

    expect(loaded, ForumHtmlReaderPreferences.defaults());
  });

  test(
    'repository preserves legal values and rejects unknown codecs',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'forum_html_reader_font_scale': 0.9,
        'forum_html_reader_conversion_mode': 'future-conversion',
      });
      final repository = SharedPrefsForumHtmlReaderPreferencesRepository();

      final loaded = await repository.load();

      expect(loaded.typography.fontScale, 0.9);
      expect(loaded.conversionMode, TextConversionMode.none);
    },
  );

  test(
    'repository loads supported values and keeps spacing internal',
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
      expect(loaded.typography.paragraphSpacing, 12.0);
      expect(loaded.conversionMode, TextConversionMode.toTraditional);
      expect(loaded.preserveAuthorFontSize, isFalse);
    },
  );

  test('repository migrates supported legacy typography once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'thread_text_font_scale': 0.9,
      'thread_text_line_height_scale': 1.8,
      'thread_text_paragraph_spacing': 30.0,
    });
    final repository = SharedPrefsForumHtmlReaderPreferencesRepository();

    final loaded = await repository.load();
    final preferences = await SharedPreferences.getInstance();

    expect(loaded.typography.fontScale, 0.9);
    expect(loaded.typography.lineHeightScale, 1.8);
    expect(loaded.typography.paragraphSpacing, 12.0);
    expect(preferences.getDouble('forum_html_reader_font_scale'), 0.9);
    expect(preferences.getDouble('forum_html_reader_line_height_scale'), 1.8);
    expect(
      preferences.containsKey('forum_html_reader_paragraph_spacing'),
      isFalse,
    );
    expect(preferences.getInt('forum_html_reader_migration_version'), 1);
  });

  test('canonical typography wins over legacy values field by field', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'forum_html_reader_font_scale': 1.3,
      'thread_text_font_scale': 0.8,
      'thread_text_line_height_scale': 1.9,
    });
    final repository = SharedPrefsForumHtmlReaderPreferencesRepository();

    final loaded = await repository.load();

    expect(loaded.typography.fontScale, 1.3);
    expect(loaded.typography.lineHeightScale, 1.9);
  });

  test('completed migration does not resurrect legacy values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'forum_html_reader_migration_version': 1,
      'thread_text_font_scale': 0.8,
      'thread_text_line_height_scale': 2.0,
    });
    final repository = SharedPrefsForumHtmlReaderPreferencesRepository();

    final loaded = await repository.load();

    expect(loaded.typography.fontScale, 1.15);
    expect(loaded.typography.lineHeightScale, 1.5);
  });

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
    expect(loaded.typography.paragraphSpacing, 12);
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
    await controller.setPreserveAuthorFontSize(false);

    final state = container
        .read(forumHtmlReaderPreferencesControllerProvider)
        .value!;
    expect(state.conversionMode, TextConversionMode.toTraditional);
    expect(state.typography.fontScale, 1.3);
    expect(state.typography.lineHeightScale, 1.9);
    expect(state.typography.paragraphSpacing, 12);
    expect(state.preserveAuthorFontSize, isFalse);
    expect(repository.saved.last, state);

    await controller.reset();
    expect(
      container.read(forumHtmlReaderPreferencesControllerProvider).value,
      ForumHtmlReaderPreferences.defaults(),
    );
  });

  test(
    'controller rolls back an optimistic update when saving fails',
    () async {
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
      repository.saveError = StateError('save failed');

      await expectLater(
        container
            .read(forumHtmlReaderPreferencesControllerProvider.notifier)
            .setFontScale(1.4),
        throwsStateError,
      );

      expect(
        container.read(forumHtmlReaderPreferencesControllerProvider).value,
        ForumHtmlReaderPreferences.defaults(),
      );
    },
  );
}

class _FakeForumHtmlReaderPreferencesRepository
    implements ForumHtmlReaderPreferencesRepository {
  ForumHtmlReaderPreferences current = ForumHtmlReaderPreferences.defaults();
  final saved = <ForumHtmlReaderPreferences>[];
  Object? saveError;

  @override
  Future<ForumHtmlReaderPreferences> load() async => current;

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    final error = saveError;
    if (error != null) {
      throw error;
    }
    current = preferences;
    saved.add(preferences);
  }
}
