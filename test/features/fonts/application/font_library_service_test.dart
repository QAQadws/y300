import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/fonts/application/font_library_service.dart';
import 'package:y300/features/fonts/domain/models/font_identity.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/imported_font.dart';
import 'package:y300/features/fonts/domain/models/resolved_font.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/domain/services/font_file_validator.dart';
import 'package:y300/features/fonts/domain/services/font_runtime_loader.dart';

import '../test_support/font_test_fixtures.dart';

void main() {
  const validator = FontFileValidator();
  late _MemoryFontRepository repository;
  late _ControlledRuntime runtime;
  late FontLibraryService service;
  late ImportedFont original;

  setUp(() {
    repository = _MemoryFontRepository();
    runtime = _ControlledRuntime();
    service = FontLibraryService(
      repository: repository,
      runtimeLoader: runtime,
    );
    original = repository.seed(loadTestFont());
  });

  tearDown(() async {
    service.dispose();
    await repository.dispose();
  });

  test('system and unknown IDs resolve without touching the library', () async {
    for (final id in <String?>[null, '', FontIdentity.system]) {
      final resolution = await service.resolveFont(id);
      expect(resolution.font, ResolvedFont.system);
      expect(resolution.failure, isNull);
    }
    final unknown = await service.resolveFont('../outside.ttf');
    expect(unknown.font, ResolvedFont.system);
    expect(unknown.failure, FontLibraryFailure.notFound);
    expect(repository.listCalls, 0);
    expect(runtime.calls, 0);
  });

  test('concurrent resolution shares only the same content request', () async {
    final loading = Completer<String>();
    runtime.onLoad = (_, _) => loading.future;
    final first = service.resolveFont(original.id);
    final second = service.resolveFont(original.id);
    expect(identical(first, second), isTrue);
    await runtime.entered.future;
    loading.complete(FontIdentity.runtimeFamily(original.id));
    final resolved = await first;
    expect(resolved.font.id, original.id);
    expect(resolved.font.cacheKey, original.id);
    expect(resolved.font.fontFamily, FontIdentity.runtimeFamily(original.id));
    expect(resolved.failure, isNull);
    expect(runtime.calls, 1);
  });

  test(
    'missing content uses typed fallback without deleting metadata',
    () async {
      repository.bytes.remove(original.id);
      final resolution = await service.resolveFont(original.id);
      expect(resolution.font, ResolvedFont.system);
      expect(resolution.isFallback, isTrue);
      expect(resolution.failure, FontLibraryFailure.notFound);
      expect(repository.fonts, contains(original.id));
      expect(runtime.calls, 0);
    },
  );

  test('library read failure preserves typed fallback reason', () async {
    repository.listFailure = FontLibraryFailure.corruptLibrary;
    final resolution = await service.resolveFont(original.id);
    expect(resolution.font, ResolvedFont.system);
    expect(resolution.failure, FontLibraryFailure.corruptLibrary);
    expect(repository.fonts, contains(original.id));
  });

  test('a failed runtime load never publishes an imported entry', () async {
    runtime.onLoad = (_, _) =>
        throw const FontLibraryException(FontLibraryFailure.loadFailed);
    final otherBytes = loadTestFont(variant: 2);
    final other = validator.validate(fileName: 'other.ttf', bytes: otherBytes);
    await expectLater(
      service.importFont(fileName: 'other.ttf', bytes: otherBytes),
      throwsA(
        isA<FontLibraryException>().having(
          (error) => error.code,
          'code',
          FontLibraryFailure.loadFailed,
        ),
      ),
    );
    expect(repository.fonts, isNot(contains(other.id)));
    expect(repository.importCalls, 0);
  });

  test(
    'invalid bytes never reach the runtime or persistent repository',
    () async {
      await expectLater(
        service.importFont(fileName: 'broken.ttf', bytes: Uint8List(12)),
        throwsA(isA<FontLibraryException>()),
      );
      expect(repository.importCalls, 0);
      expect(runtime.calls, 0);
    },
  );

  test('import snapshots caller bytes and loads before publication', () async {
    final source = loadTestFont(variant: 2);
    final expected = validator.validate(fileName: 'story.ttf', bytes: source);
    final loading = Completer<String>();
    runtime.onLoad = (_, _) => loading.future;
    final pending = service.importFont(fileName: 'story.ttf', bytes: source);
    source[0] ^= 0xff;
    await runtime.entered.future;
    expect(repository.importCalls, 0);
    loading.complete(FontIdentity.runtimeFamily(expected.id));
    expect(await pending, expected);
    expect(repository.fonts[expected.id], expected);
    expect(
      repository.bytes[expected.id],
      orderedEquals(loadTestFont(variant: 2)),
    );
  });

  test('deleting during load retires the previously requested font', () async {
    final loading = Completer<String>();
    runtime.onLoad = (_, _) => loading.future;
    final pending = service.resolveFont(original.id);
    await runtime.entered.future;
    await service.deleteFont(original.id);
    loading.complete(FontIdentity.runtimeFamily(original.id));
    final resolution = await pending;
    expect(resolution.font, ResolvedFont.system);
    expect(resolution.failure, FontLibraryFailure.notFound);
  });

  test(
    'a queued deletion also fences requests made after it was queued',
    () async {
      final loading = Completer<String>();
      runtime.onLoad = (_, _) => loading.future;
      final newBytes = loadTestFont(variant: 2);
      final newId = validator.validate(fileName: 'new.ttf', bytes: newBytes).id;
      final importing = service.importFont(
        fileName: 'new.ttf',
        bytes: newBytes,
      );
      await runtime.entered.future;
      final deleting = service.deleteFont(original.id);
      final resolution = await service.resolveFont(original.id);
      expect(resolution.font, ResolvedFont.system);
      expect(resolution.failure, FontLibraryFailure.notFound);
      expect(repository.fonts, contains(original.id));
      loading.complete(FontIdentity.runtimeFamily(newId));
      await importing;
      await deleting;
      expect(repository.fonts, isNot(contains(original.id)));
      expect(repository.fonts, contains(newId));
    },
  );

  test(
    'failed deletion permits a fresh resolution of the retained font',
    () async {
      repository.deleteFailure = true;
      await expectLater(
        service.deleteFont(original.id),
        throwsA(isA<FontLibraryException>()),
      );
      expect((await service.resolveFont(original.id)).font.id, original.id);
    },
  );

  test(
    'disposal retires an in-flight load before it can be published',
    () async {
      final loading = Completer<String>();
      runtime.onLoad = (_, _) => loading.future;
      final pending = service.resolveFont(original.id);
      await runtime.entered.future;
      service.dispose();
      loading.complete(FontIdentity.runtimeFamily(original.id));
      expect((await pending).font, ResolvedFont.system);
    },
  );

  test('a failed operation does not poison the mutation queue', () async {
    await expectLater(
      service.importFont(fileName: 'bad.ttf', bytes: Uint8List(1)),
      throwsA(isA<FontLibraryException>()),
    );
    final font = await service.importFont(
      fileName: 'ok.ttf',
      bytes: loadTestFont(),
    );
    expect(font.id, original.id);
    expect((await service.resolveFont(font.id)).font.id, font.id);
  });
}

final class _ControlledRuntime implements FontRuntimeLoader {
  Future<String> Function(ImportedFont, Uint8List)? onLoad;
  final entered = Completer<void>();
  int calls = 0;

  @override
  Future<String> load(ImportedFont font, Uint8List bytes) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    return onLoad?.call(font, bytes) ?? FontIdentity.runtimeFamily(font.id);
  }
}

final class _MemoryFontRepository implements FontLibraryRepository {
  final fonts = <String, ImportedFont>{};
  final bytes = <String, Uint8List>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  FontLibraryFailure? listFailure;
  bool deleteFailure = false;
  int listCalls = 0;
  int importCalls = 0;

  ImportedFont seed(Uint8List data, {String fileName = 'story.ttf'}) {
    final font = const FontFileValidator().validate(
      fileName: fileName,
      bytes: data,
    );
    fonts[font.id] = font;
    bytes[font.id] = Uint8List.fromList(data);
    return font;
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<ImportedFont>> listFonts() async {
    listCalls++;
    final failure = listFailure;
    if (failure != null) throw FontLibraryException(failure);
    return List.unmodifiable(fonts.values);
  }

  @override
  Future<ImportedFont> importFont({
    required String fileName,
    required Uint8List bytes,
  }) async {
    importCalls++;
    final font = seed(bytes, fileName: fileName);
    _changes.add(null);
    return font;
  }

  @override
  Future<Uint8List> readFont(String fontId) async {
    final data = bytes[fontId];
    if (data == null) {
      throw const FontLibraryException(FontLibraryFailure.notFound);
    }
    return Uint8List.fromList(data);
  }

  @override
  Future<void> deleteFont(String fontId) async {
    if (deleteFailure) {
      throw const FontLibraryException(FontLibraryFailure.storage);
    }
    fonts.remove(fontId);
    bytes.remove(fontId);
    _changes.add(null);
  }

  @override
  Future<void> dispose() => _changes.close();
}
