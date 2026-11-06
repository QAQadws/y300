import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';

const _a = 'work-a';
const _b = 'work-b';
String _key(String work) =>
    'reader.novel.work.v1.${sha256.convert(utf8.encode(work))}';

SharedPreferencesNovelReaderPreferencesRepository _repository() =>
    SharedPreferencesNovelReaderPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
      legacySource: const _NoLegacy(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('work keeps only chosen fields including explicit defaults', () async {
    final repo = _repository();
    final global = NovelReaderPreferences.defaults().copyWith(
      fontSize: 22,
      showRubyAnnotations: false,
      viewport: const NovelReaderViewportOverrides(left: 12, top: 8),
      colors: const NovelReaderColorOverrides(foreground: 0x010203),
      typography: const NovelReaderTypographyOverrides(
        roleFontSizes: NovelReaderRoleFontSizes(heading: 125, ruby: 135),
      ),
    );
    await repo.save(global);
    final initial = await repo.loadScopes(_a);
    expect(initial.effective, global);
    expect(initial.hasWorkOverrides, isFalse);
    final saved = await repo.saveScope(
      _a,
      scope: NovelReaderPreferenceScope.work,
      previous: initial.effective,
      next: initial.effective.copyWith(
        fontSize: 24,
        showRubyAnnotations: true,
        colors: const NovelReaderColorOverrides(),
        viewport: const NovelReaderViewportOverrides(left: 0, top: 8),
        typography: const NovelReaderTypographyOverrides(
          roleFontSizes: NovelReaderRoleFontSizes(heading: 125, ruby: 100),
        ),
      ),
    );
    expect(saved.canEditWork, isTrue);
    expect(saved.hasWorkOverrides, isTrue);
    expect(saved.effective.colors.foreground, isNull);
    expect(saved.defaults, global);
    final preferences = await SharedPreferences.getInstance();
    final raw = jsonDecode(preferences.getString(_key(_a))!) as Map;
    expect(raw['fields'], {
      'fontSize': 24,
      'showRubyAnnotations': true,
      'viewport.left': {'unit': 'logicalPixels', 'value': 0, 'enabled': true},
      'typography.roleFontSizes.ruby': 100,
      'colors.foreground': null,
    });
    expect(preferences.containsKey(_key(_b)), isFalse);

    final updatedGlobal = global.copyWith(
      fontSize: 28,
      lineHeight: 2,
      viewport: const NovelReaderViewportOverrides(left: 19, top: 30),
      colors: const NovelReaderColorOverrides(
        foreground: 0x102030,
        background: 0xf0f0f0,
      ),
      typography: const NovelReaderTypographyOverrides(
        roleFontSizes: NovelReaderRoleFontSizes(heading: 140, ruby: 150),
      ),
    );
    final preview = saved.previewDefaults(updatedGlobal);
    expect(await repo.load(), global);
    final written = await repo.saveScope(
      _a,
      scope: NovelReaderPreferenceScope.defaults,
      previous: global,
      next: updatedGlobal,
    );
    expect(written.effective, preview);
    final a = (await _repository().loadScopes(_a)).effective;
    expect(a, preview);
    expect(a.fontSize, 24);
    expect(a.showRubyAnnotations, isTrue);
    expect(a.lineHeight, 2);
    expect(a.viewport, const NovelReaderViewportOverrides(left: 0, top: 30));
    expect(
      a.typography.roleFontSizes,
      const NovelReaderRoleFontSizes(heading: 140, ruby: 100),
    );
    expect(a.colors, const NovelReaderColorOverrides(background: 0xf0f0f0));
    expect((await repo.loadScopes(_b)).effective, updatedGlobal);

    final reset = await repo.resetWork(_a);
    expect(reset.effective, updatedGlobal);
    expect(reset.hasWorkOverrides, isFalse);
    expect(preferences.containsKey(_key(_a)), isFalse);
  });

  test(
    'queued edits merge against latest scope and stay with their work',
    () async {
      final repo = _repository();
      final baseline = (await repo.loadScopes(_a)).effective;
      Future<NovelReaderPreferenceScopes> write(
        String work,
        NovelReaderPreferenceScope scope,
        NovelReaderPreferences next,
      ) => repo.saveScope(work, scope: scope, previous: baseline, next: next);

      await Future.wait([
        write(
          _a,
          NovelReaderPreferenceScope.work,
          baseline.copyWith(fontSize: 25),
        ),
        write(
          _a,
          NovelReaderPreferenceScope.work,
          baseline.copyWith(lineHeight: 2),
        ),
        write(
          _b,
          NovelReaderPreferenceScope.work,
          baseline.copyWith(fontSize: 16),
        ),
        write(
          _b,
          NovelReaderPreferenceScope.defaults,
          baseline.copyWith(compressBlankLines: true),
        ),
        write(
          _a,
          NovelReaderPreferenceScope.defaults,
          baseline.copyWith(safeAreaEnabled: false),
        ),
      ]);
      final a = (await repo.loadScopes(_a)).effective;
      final b = (await repo.loadScopes(_b)).effective;
      expect(a.fontSize, 25);
      expect(a.lineHeight, 2);
      expect(a.compressBlankLines, isTrue);
      expect(a.safeAreaEnabled, isFalse);
      expect(b.fontSize, 16);
      expect(b.lineHeight, baseline.lineHeight);
      expect(b.safeAreaEnabled, isFalse);
      expect((await repo.load()).fontSize, baseline.fontSize);
    },
  );

  test('reset keeps known schema extensions and untouched work', () async {
    final preferences = await SharedPreferences.getInstance();
    const other = '{"schemaVersion":1,"fields":{"fontSize":16}}';
    await preferences.setString(_key(_b), other);
    await preferences.setString(
      _key(_a),
      '{"schemaVersion":1,"tag":"keep","fields":{"fontSize":21,"futureField":[1,2]}}',
    );
    final repo = _repository();
    final old = await repo.loadScopes(_a);
    expect(old.effective.fontSize, 21);
    expect(old.canEditWork, isTrue);
    final reset = await repo.resetWork(_a);
    expect(reset.hasWorkOverrides, isFalse);
    expect(jsonDecode(preferences.getString(_key(_a))!), {
      'schemaVersion': 1,
      'tag': 'keep',
      'fields': {
        'futureField': [1, 2],
      },
    });
    expect(preferences.getString(_key(_b)), other);
  });

  for (final source in [
    '{"schemaVersion":2,"fields":{"fontSize":25}}',
    '{"schemaVersion":1,"fields":{"typography.wordSpacing":{"unit":"future"}}}',
    '{"schemaVersion":1,"fields":{"showRubyAnnotations":"false"}}',
    '{broken',
  ]) {
    test(
      'unsafe work snapshot is read-only and cannot poison the queue: $source',
      () async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(_key(_a), source);
        final repo = _repository();
        final old = await repo.loadScopes(_a);
        expect(old.canEditWork, isFalse);
        expect(old.effective, old.defaults);
        final rejected = expectLater(
          repo.resetWork(_a),
          throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
        );
        final saved = await repo.saveScope(
          _b,
          scope: NovelReaderPreferenceScope.work,
          previous: old.defaults,
          next: old.defaults.copyWith(fontSize: 19),
        );
        await rejected;
        expect(saved.effective.fontSize, 19);
        expect(preferences.getString(_key(_a)), source);
      },
    );
  }
}

final class _NoLegacy implements NovelReaderPreferencesLegacySource {
  const _NoLegacy();
  @override
  Future<NovelReaderPreferences?> load() async => null;
}
