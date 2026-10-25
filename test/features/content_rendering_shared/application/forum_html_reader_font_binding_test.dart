import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/domain/services/font_file_validator.dart';
import 'package:y300/features/fonts/domain/services/font_runtime_loader.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

import '../../fonts/test_support/font_test_fixtures.dart';

void main() {
  test(
    'cold preferences remain unready until their font is actually loaded',
    () async {
      final host = _host();
      host.preferences.current = host.preferences.current.copyWith(
        fontFamily: host.first.id,
      );
      final loadingFont = host.runtime.pause(host.first.id);
      final loading = host.load();
      await host.runtime.whenEntered(host.first.id);

      expect(host.binding.isReady, isFalse);
      expect(host.binding.preferences.fontFamily, FontIdentity.system);
      expect(host.binding.resolvedFont, ResolvedFont.system);
      expect(host.preferences.calls, isEmpty);

      loadingFont.complete(FontIdentity.runtimeFamily(host.first.id));
      expect((await loading).fontFamily, host.first.id);
      expect(host.binding.isReady, isTrue);
      expect(host.binding.resolvedFont.id, host.first.id);
      expect(
        host.binding.resolvedFont.fontFamily,
        FontIdentity.runtimeFamily(host.first.id),
      );
      host.expectCoherentPublications();
    },
  );

  test(
    'a pending choice keeps the previously loaded preference and style',
    () async {
      final host = _host();
      host.preferences.current = host.preferences.current.copyWith(
        fontFamily: host.first.id,
      );
      await host.load();
      final loadingFont = host.runtime.pause(host.second.id);
      final choosing = host.controller.setFontFamily(host.second.id);
      await host.runtime.whenEntered(host.second.id);

      expect(host.binding.isReady, isTrue);
      expect(host.binding.preferences.fontFamily, host.first.id);
      expect(host.binding.resolvedFont.id, host.first.id);
      expect(host.binding.cacheKey, host.first.id);
      expect(host.preferences.calls, isEmpty);

      loadingFont.complete(FontIdentity.runtimeFamily(host.second.id));
      await choosing;
      expect(host.binding.preferences.fontFamily, host.second.id);
      expect(host.binding.resolvedFont.id, host.second.id);
      expect(host.preferences.current.fontFamily, host.second.id);
      host.expectCoherentPublications();
    },
  );

  test('the latest choice wins over a late older runtime load', () async {
    final host = _host();
    await host.load();
    final loadingFirst = host.runtime.pause(host.first.id);
    final earlier = host.controller.setFontFamily(host.first.id);
    await host.runtime.whenEntered(host.first.id);
    await host.controller.setFontFamily(host.second.id);
    loadingFirst.complete(FontIdentity.runtimeFamily(host.first.id));
    await earlier;

    expect(host.preferences.calls.map((value) => value.fontFamily), [
      host.second.id,
    ]);
    expect(host.binding.preferences.fontFamily, host.second.id);
    expect(host.binding.resolvedFont.id, host.second.id);
    host.expectCoherentPublications();
  });

  test(
    'deletion repairs only the persisted font while keeping a local draft',
    () async {
      final host = _host();
      final original = host.preferences.current.copyWith(
        fontFamily: host.first.id,
        preserveAuthorFontSize: false,
        conversionMode: TextConversionMode.toTraditional,
      );
      host.preferences.current = original;
      await host.load();
      final preview = host.controller.beginTypographyPreview(
        onError: (error, stack) => fail('$error'),
      );
      addTearDown(preview.cancel);
      preview.change(preview.value.copyWith(fontScale: 1.7));
      await host.service.deleteFont(host.first.id);
      await _settle();

      expect(host.binding.resolvedFont, ResolvedFont.system);
      expect(host.binding.preferences.fontFamily, FontIdentity.system);
      expect(host.binding.preferences.typography.fontScale, 1.7);
      expect(preview.isActive, isTrue);
      expect(host.preferences.calls, [
        original.copyWith(fontFamily: FontIdentity.system),
      ]);
      expect(
        host.preferences.current,
        original.copyWith(fontFamily: FontIdentity.system),
      );
      host.expectCoherentPublications();
    },
  );

  test(
    'a deletion repair waits for the writer and preserves an issued setting',
    () async {
      final host = _host();
      host.preferences.current = host.preferences.current.copyWith(
        fontFamily: host.first.id,
      );
      await host.load();
      final saving = Completer<void>();
      host.preferences.holdNext = saving;
      final setting = host.controller.setConversionMode(
        TextConversionMode.toSimplified,
      );
      await _settle();
      expect(host.preferences.calls, hasLength(1));
      await host.service.deleteFont(host.first.id);
      await _settle();
      expect(host.preferences.calls, hasLength(1));
      expect(host.binding.preferences.fontFamily, FontIdentity.system);

      saving.complete();
      await setting;
      await _settle();
      expect(host.preferences.calls, hasLength(2));
      expect(host.preferences.current.fontFamily, FontIdentity.system);
      expect(
        host.preferences.current.conversionMode,
        TextConversionMode.toSimplified,
      );
      expect(
        host.binding.preferences.conversionMode,
        TextConversionMode.toSimplified,
      );
      host.expectCoherentPublications();
    },
  );

  test(
    'a failed persisted repair is attempted once despite catalog events',
    () async {
      final host = _host();
      host.preferences.current = host.preferences.current.copyWith(
        fontFamily: host.first.id,
      );
      await host.load();
      host.preferences.failWrites = true;
      await host.service.deleteFont(host.first.id);
      await _settle();
      expect(host.preferences.calls, hasLength(1));
      expect(host.preferences.current.fontFamily, host.first.id);
      for (var index = 0; index < 3; index++) {
        host.fonts.publish();
        await _settle();
      }

      expect(host.preferences.calls, hasLength(1));
      expect(host.binding.preferences.fontFamily, FontIdentity.system);
      expect(host.binding.resolvedFont, ResolvedFont.system);
      host.expectCoherentPublications();
    },
  );

  test(
    'a transient runtime failure recovers from a catalog change without a save',
    () async {
      final host = _host();
      host.preferences.current = host.preferences.current.copyWith(
        fontFamily: host.first.id,
      );
      host.runtime.failures[host.first.id] = FontLibraryFailure.loadFailed;
      await host.load();
      await _settle();
      expect(host.binding.resolvedFont, ResolvedFont.system);
      expect(host.binding.resolution.requestedId, host.first.id);
      expect(host.binding.resolution.failure, FontLibraryFailure.loadFailed);
      expect(host.preferences.calls, isEmpty);

      host.runtime.failures.clear();
      host.fonts.publish();
      await _settle();
      expect(host.binding.preferences.fontFamily, host.first.id);
      expect(host.binding.resolvedFont.id, host.first.id);
      expect(host.binding.resolution.failure, isNull);
      expect(host.preferences.calls, isEmpty);
      host.expectCoherentPublications();
    },
  );

  test(
    'a failed choice rolls back both preferences and the prior loaded font',
    () async {
      final host = _host();
      host.preferences.current = host.preferences.current.copyWith(
        fontFamily: host.first.id,
      );
      await host.load();
      host.preferences.failWrites = true;
      await expectLater(
        host.controller.setFontFamily(host.second.id),
        throwsStateError,
      );

      expect(host.preferences.current.fontFamily, host.first.id);
      expect(host.binding.preferences.fontFamily, host.first.id);
      expect(host.binding.resolvedFont.id, host.first.id);
      expect(host.binding.cacheKey, host.first.id);
      host.expectCoherentPublications();
    },
  );

  test(
    'unrelated settings preserve a temporarily failed font for later recovery',
    () async {
      final host = _host();
      host.preferences.current = host.preferences.current.copyWith(
        fontFamily: host.first.id,
      );
      host.runtime.failures[host.first.id] = FontLibraryFailure.loadFailed;
      await host.load();

      await host.controller.setFontScale(1.4);
      await host.controller.setConversionMode(TextConversionMode.toTraditional);
      expect(host.preferences.current.fontFamily, host.first.id);
      expect(host.preferences.current.typography.fontScale, 1.4);
      expect(host.binding.resolvedFont, ResolvedFont.system);
      expect(host.binding.resolution.requestedId, host.first.id);
      expect(host.binding.resolution.failure, FontLibraryFailure.loadFailed);

      host.runtime.failures.clear();
      host.fonts.publish();
      await _settle();
      expect(host.binding.resolvedFont.id, host.first.id);
      expect(host.binding.preferences.typography.fontScale, 1.4);
      expect(
        host.binding.preferences.conversionMode,
        TextConversionMode.toTraditional,
      );
      expect(host.preferences.calls, hasLength(2));
      host.expectCoherentPublications();
    },
  );

  for (final reset in [false, true]) {
    test(
      '${reset ? 'reset' : 'explicit system choice'} replaces a temporarily failed font',
      () async {
        final host = _host();
        host.preferences.current = host.preferences.current.copyWith(
          fontFamily: host.first.id,
        );
        host.runtime.failures[host.first.id] = FontLibraryFailure.loadFailed;
        await host.load();

        if (reset) {
          await host.controller.reset();
        } else {
          await host.controller.setFontFamily(FontIdentity.system);
        }
        expect(host.preferences.current.fontFamily, FontIdentity.system);
        host.runtime.failures.clear();
        host.fonts.publish();
        await _settle();
        expect(host.binding.resolvedFont, ResolvedFont.system);
        expect(host.binding.resolution.requestedId, FontIdentity.system);
        expect(host.binding.resolution.failure, isNull);
        expect(host.preferences.calls, hasLength(1));
        host.expectCoherentPublications();
      },
    );
  }

  test(
    'a catalog event does not retire a new choice that is still loading',
    () async {
      final host = _host();
      host.preferences.current = host.preferences.current.copyWith(
        fontFamily: host.first.id,
      );
      await host.load();
      final loadingFont = host.runtime.pause(host.second.id);
      final choosing = host.controller.setFontFamily(host.second.id);
      await host.runtime.whenEntered(host.second.id);
      host.fonts.publish();
      await _settle();
      expect(host.binding.resolvedFont.id, host.first.id);
      loadingFont.complete(FontIdentity.runtimeFamily(host.second.id));
      await choosing;

      expect(host.binding.preferences.fontFamily, host.second.id);
      expect(host.binding.resolvedFont.id, host.second.id);
      expect(host.preferences.current.fontFamily, host.second.id);
      host.expectCoherentPublications();
    },
  );

  test(
    'deletion wins when another page changes typography in the same event',
    () async {
      final host = _host();
      host.preferences.current = host.preferences.current.copyWith(
        fontFamily: host.first.id,
      );
      await host.load();
      Future<void>? setting;
      final subscription = host.service.changes.listen((_) {
        setting = host.controller.setFontScale(1.4);
        unawaited(setting);
      });
      addTearDown(subscription.cancel);

      await host.service.deleteFont(host.first.id);
      await (setting ?? Future<void>.value());
      await _settle();

      expect(host.binding.resolvedFont, ResolvedFont.system);
      expect(host.binding.preferences.fontFamily, FontIdentity.system);
      expect(host.binding.preferences.typography.fontScale, 1.4);
      expect(host.preferences.current.fontFamily, FontIdentity.system);
      expect(host.preferences.current.typography.fontScale, 1.4);
      host.expectCoherentPublications();
    },
  );
}

_Harness _host() {
  final host = _Harness();
  addTearDown(host.dispose);
  return host;
}

Future<void> _settle() async {
  // Include the deferred repair task after resolver microtasks have published.
  for (var index = 0; index < 4; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Harness {
  _Harness() {
    first = fonts.seed(loadTestFont());
    second = fonts.seed(loadTestFont(variant: 2));
    service = FontLibraryService(repository: fonts, runtimeLoader: runtime);
    container = ProviderContainer(
      overrides: [
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          preferences,
        ),
        fontLibraryServiceProvider.overrideWithValue(service),
      ],
    );
  }

  final preferences = _Preferences();
  final fonts = _Fonts();
  final runtime = _Runtime();
  late final ImportedFont first;
  late final ImportedFont second;
  late final FontLibraryService service;
  late final ProviderContainer container;
  ProviderSubscription<ForumHtmlReaderFontBinding>? _subscription;
  final publications = <ForumHtmlReaderFontBinding>[];

  ForumHtmlReaderPreferencesController get controller =>
      container.read(forumHtmlReaderPreferencesControllerProvider.notifier);
  ForumHtmlReaderFontBinding get binding =>
      container.read(forumHtmlReaderFontBindingProvider);

  Future<ForumHtmlReaderPreferences> load() {
    _subscription ??= container.listen(forumHtmlReaderFontBindingProvider, (
      _,
      next,
    ) {
      publications.add(next);
    }, fireImmediately: true);
    return container.read(forumHtmlReaderPreferencesControllerProvider.future);
  }

  void expectCoherentPublications() {
    expect(publications.where((value) => value.isReady), isNotEmpty);
    for (final value in publications.where((value) => value.isReady)) {
      expect(value.preferences.fontFamily, value.resolvedFont.id);
    }
  }

  Future<void> dispose() async {
    _subscription?.close();
    container.dispose();
    service.dispose();
    await fonts.dispose();
  }
}

final class _Preferences implements ForumHtmlReaderPreferencesRepository {
  ForumHtmlReaderPreferences current = ForumHtmlReaderPreferences.defaults();
  final calls = <ForumHtmlReaderPreferences>[];
  Completer<void>? holdNext;
  bool failWrites = false;

  @override
  Future<ForumHtmlReaderPreferences> load() async => current;

  @override
  Future<void> save(ForumHtmlReaderPreferences value) async {
    calls.add(value);
    final held = holdNext;
    holdNext = null;
    if (held != null) await held.future;
    if (failWrites) throw StateError('private font preference storage details');
    current = value;
  }
}

final class _Runtime implements FontRuntimeLoader {
  final _gates = <String, Completer<String>>{};
  final _entered = <String, Completer<void>>{};
  final failures = <String, FontLibraryFailure>{};

  Completer<String> pause(String id) {
    final gate = Completer<String>();
    _gates[id] = gate;
    return gate;
  }

  Future<void> whenEntered(String id) =>
      _entered.putIfAbsent(id, Completer<void>.new).future;

  @override
  Future<String> load(ImportedFont font, Uint8List bytes) async {
    final entered = _entered.putIfAbsent(font.id, Completer<void>.new);
    if (!entered.isCompleted) entered.complete();
    final gate = _gates.remove(font.id);
    if (gate != null) return gate.future;
    final failure = failures[font.id];
    if (failure != null) throw FontLibraryException(failure);
    return FontIdentity.runtimeFamily(font.id);
  }
}

final class _Fonts implements FontLibraryRepository {
  final _entries = <String, ImportedFont>{};
  final _bytes = <String, Uint8List>{};
  final _changes = StreamController<void>.broadcast(sync: true);

  ImportedFont seed(Uint8List bytes, {String fileName = 'reader.ttf'}) {
    final font = const FontFileValidator().validate(
      fileName: fileName,
      bytes: bytes,
    );
    _entries[font.id] = font;
    _bytes[font.id] = Uint8List.fromList(bytes);
    return font;
  }

  void publish() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<List<ImportedFont>> listFonts() async =>
      List.unmodifiable(_entries.values);
  @override
  Future<Uint8List> readFont(String fontId) async {
    final bytes = _bytes[fontId];
    if (bytes == null) {
      throw const FontLibraryException(FontLibraryFailure.notFound);
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<ImportedFont> importFont({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final font = seed(bytes, fileName: fileName);
    publish();
    return font;
  }

  @override
  Future<void> deleteFont(String fontId) async {
    _entries.remove(fontId);
    _bytes.remove(fontId);
    publish();
  }

  @override
  Future<void> dispose() => _changes.close();
}
