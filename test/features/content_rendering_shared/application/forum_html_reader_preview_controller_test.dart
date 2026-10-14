import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

void main() {
  test(
    'an older save failure cannot roll back a newer unsaved preview',
    () async {
      final repository = _Repository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(forumHtmlReaderPreferencesControllerProvider.future);
      final controller = container.read(
        forumHtmlReaderPreferencesControllerProvider.notifier,
      );
      final first = controller.setFontScale(1.3);
      final failure = expectLater(first, throwsStateError);
      final preview = controller.beginTypographyPreview(
        onError: (error, stack) => fail('$error'),
      );
      preview.change(preview.value.copyWith(fontScale: 1.7));
      repository.complete(error: StateError('old save'));
      await failure;
      expect(
        container
            .read(forumHtmlReaderPreferencesControllerProvider)
            .value!
            .typography
            .fontScale,
        1.7,
      );
      expect(preview.isActive, isTrue);
      final finalSave = preview.flush();
      repository.complete();
      await finalSave;
      expect(repository.current.typography.fontScale, 1.7);
      preview.cancel();
    },
  );

  test(
    'a latest save failure rolls back to the last successful snapshot',
    () async {
      final repository = _Repository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(forumHtmlReaderPreferencesControllerProvider.future);
      final controller = container.read(
        forumHtmlReaderPreferencesControllerProvider.notifier,
      );
      final first = controller.setFontScale(1.3);
      final latest = controller.setFontScale(1.7);
      final failure = expectLater(latest, throwsStateError);
      repository.complete();
      await first;
      expect(
        container
            .read(forumHtmlReaderPreferencesControllerProvider)
            .value!
            .typography
            .fontScale,
        1.7,
      );
      repository.complete(error: StateError('latest save'));
      await failure;
      expect(
        container.read(forumHtmlReaderPreferencesControllerProvider).value,
        repository.current,
      );
      expect(repository.current.typography.fontScale, 1.3);
    },
  );

  testWidgets(
    'discrete settings include the latest draft and reset retires it',
    (tester) async {
      final repository = _Repository(immediate: true);
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(forumHtmlReaderPreferencesControllerProvider.future);
      final controller = container.read(
        forumHtmlReaderPreferencesControllerProvider.notifier,
      );
      final preview = controller.beginTypographyPreview(
        onError: (error, stack) => fail('$error'),
      );
      preview.change(preview.value.copyWith(fontScale: 1.3));
      preview.change(preview.value.copyWith(fontScale: 1.9));
      await controller.setConversionMode(TextConversionMode.toSimplified);
      expect(preview.isActive, isFalse);
      expect(repository.current.typography.fontScale, 1.9);
      expect(
        repository.current.conversionMode,
        TextConversionMode.toSimplified,
      );

      final resetting = controller.beginTypographyPreview(
        onError: (error, stack) => fail('$error'),
      );
      resetting.change(resetting.value.copyWith(fontScale: 1.6));
      resetting.change(resetting.value.copyWith(fontScale: 1.8));
      resetting.close();
      await controller.reset();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.calls, hasLength(2));
      expect(repository.current, ForumHtmlReaderPreferences.defaults());
      expect(
        container.read(forumHtmlReaderPreferencesControllerProvider).value,
        repository.current,
      );
    },
  );

  testWidgets(
    'invalidation cancels dismissal drafts and reload waits for issued saves',
    (tester) async {
      final repository = _Repository();
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(forumHtmlReaderPreferencesControllerProvider.future);
      final controller = container.read(
        forumHtmlReaderPreferencesControllerProvider.notifier,
      );
      final saving = controller.setFontScale(1.3);
      final preview = controller.beginTypographyPreview(
        onError: (error, stack) => fail('$error'),
      );
      preview.change(preview.value.copyWith(fontScale: 1.7));
      preview.change(preview.value.copyWith(fontScale: 1.9));
      preview.close();
      container.invalidate(forumHtmlReaderPreferencesControllerProvider);
      final reloading = container.read(
        forumHtmlReaderPreferencesControllerProvider.future,
      );
      repository.complete();
      await saving;
      expect((await reloading).typography.fontScale, 1.3);
      await tester.pump(const Duration(seconds: 1));
      expect(repository.calls, hasLength(1));
      expect(preview.isActive, isFalse);
    },
  );
}

ProviderContainer _container(_Repository repository) => ProviderContainer(
  overrides: [
    forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(repository),
  ],
);

class _Repository implements ForumHtmlReaderPreferencesRepository {
  _Repository({this.immediate = false});
  final bool immediate;
  ForumHtmlReaderPreferences current = ForumHtmlReaderPreferences.defaults();
  final calls = <ForumHtmlReaderPreferences>[];
  final pending = <Completer<void>>[];
  @override
  Future<ForumHtmlReaderPreferences> load() async => current;
  @override
  Future<void> save(ForumHtmlReaderPreferences value) async {
    calls.add(value);
    if (!immediate) {
      final completer = Completer<void>();
      pending.add(completer);
      await completer.future;
    }
    current = value;
  }

  void complete({Object? error}) {
    final completer = pending.removeAt(0);
    if (error == null) {
      completer.complete();
    } else {
      completer.completeError(error);
    }
  }
}
