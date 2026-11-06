import 'dart:convert';
import 'dart:ui' show TextDirection;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_snapshot_codec.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_viewport_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_preference_impact_analyzer.dart';

const _codec = NovelReaderPreferencesSnapshotCodec();
const _viewport = NovelReaderViewportOverrides(
  left: 0,
  top: 12,
  right: 31,
  bottom: 48,
  contentWidth: NovelReaderContentWidth.limited(640),
);
NovelReaderPreferences _prefs([
  NovelReaderViewportOverrides value = _viewport,
]) => NovelReaderPreferences.defaults().copyWith(
  viewport: value,
  typography: const NovelReaderTypographyOverrides(
    fontWeight: NovelReaderFontWeight(value: 700),
    textAlignment: NovelReaderTextAlignment(
      mode: NovelReaderTextAlignMode.justify,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'zero, inheritance and available width remain distinct sparse requests',
    () {
      expect(const NovelReaderViewportOverrides().over(_viewport), _viewport);
      expect(
        _viewport
            .withMargin(NovelReaderViewportEdge.left, null)
            .over(_viewport)
            .left,
        0,
      );
      for (final edge in NovelReaderViewportEdge.values) {
        final edited = _viewport.withMargin(edge, null);
        expect(edited.contentWidth, _viewport.contentWidth);
        for (final other in NovelReaderViewportEdge.values.where(
          (v) => v != edge,
        )) {
          expect(edited.marginFor(other), _viewport.marginFor(other));
        }
      }
      final full = _viewport.withContentWidth(
        const NovelReaderContentWidth.available(logicalPixels: 640),
      );
      expect(full, isNot(_viewport));
      expect(full.left, 0);
      expect(full.withContentWidth(null).left, 0);
      expect(_prefs().copyWith(fontFamily: 'system').viewport, _viewport);
      const analyzer = DefaultNovelReaderPreferenceImpactAnalyzer();
      expect(analyzer.compare(_prefs(), _prefs(full)).impacts, {
        NovelReaderPreferenceImpact.relayout,
      });
      expect(analyzer.compare(_prefs(), _prefs()).impacts, {
        NovelReaderPreferenceImpact.none,
      });
    },
  );
  test(
    'every edge extreme and both width modes survive repository reconstruction',
    () async {
      for (final edge in NovelReaderViewportEdge.values) {
        for (final number in [0.0, 96.0]) {
          final prefs = _prefs(_viewport.withMargin(edge, number));
          await _repository().save(prefs);
          expect(await _repository().load(), prefs);
        }
      }
      for (final width in [
        const NovelReaderContentWidth.limited(160),
        const NovelReaderContentWidth.limited(2560),
        const NovelReaderContentWidth.available(logicalPixels: 640),
      ]) {
        final prefs = _prefs(_viewport.withContentWidth(width));
        await _repository().save(prefs);
        expect(await _repository().load(), prefs);
      }
    },
  );
  test(
    'legacy transient values retain default behavior without new persistence',
    () {
      final prefs = NovelReaderPreferences.defaults().copyWith(
        pagePadding: 13,
        contentMaxWidth: 500,
      );
      final actual = resolveNovelReaderNativeViewport(prefs);
      expect(actual, (
        left: 13.0,
        top: 13.0,
        right: 13.0,
        bottom: 13.0,
        maximumWidth: 500.0,
      ));
      final encoded = jsonDecode(_codec.encode(prefs)) as Map;
      expect(encoded, isNot(contains('viewport')));
      expect(encoded, isNot(contains('pagePadding')));
      expect(encoded, isNot(contains('contentMaxWidth')));
      encoded['pagePadding'] = 35;
      encoded['contentMaxWidth'] = 1000;
      final loaded = _codec.decode(jsonEncode(encoded));
      expect(loaded.viewport.isEmpty, true);
      expect(loaded.pagePadding, 8);
      expect(loaded.contentMaxWidth, 720);
    },
  );
  test(
    'column choice round trips independently of width and margins',
    () async {
      for (final count in NovelReaderColumnCount.values) {
        final viewport = _viewport
            .withColumns(count)
            .withMargin(NovelReaderViewportEdge.right, 5)
            .withContentWidth(null);
        await _repository().save(_prefs(viewport));
        expect((await _repository().load()).viewport, viewport);
      }
    },
  );

  test('effective columns respect width, font size and flow direction', () {
    final preferences = _prefs(
      const NovelReaderViewportOverrides(
        columns: NovelReaderColumnCount.triple,
      ),
    );
    ({double width, int count, TextDirection order}) geometry(
      NovelReaderPreferences value,
      double available, {
      double font = 18.5,
    }) {
      final resolved = resolveNovelReaderNativePageBox(
        value,
        availableWidth: available,
        maximumWidth: resolveNovelReaderNativeViewport(value).maximumWidth,
        scaledBodyFontSize: font,
      );
      return (
        width: resolved.width,
        count: resolved.columns.count,
        order: resolved.columns.readingOrder,
      );
    }

    expect(geometry(preferences, 827), (
      width: 720.0,
      count: 1,
      order: TextDirection.ltr,
    ));
    expect(geometry(preferences, 828), (
      width: 828.0,
      count: 3,
      order: TextDirection.ltr,
    ));
    expect(geometry(preferences, 1060, font: 28).count, 3);
    expect(geometry(preferences, 1060, font: 29).count, 1);
    final limited = preferences.copyWith(
      viewport: preferences.viewport.withContentWidth(
        const NovelReaderContentWidth.limited(800),
      ),
    );
    expect(geometry(limited, 1200), (
      width: 800.0,
      count: 1,
      order: TextDirection.ltr,
    ));
    final rtl = preferences.copyWith(flowMode: NovelReaderFlowMode.pagedRtl);
    expect(geometry(rtl, 900), (
      width: 900.0,
      count: 3,
      order: TextDirection.rtl,
    ));
    expect(
      geometry(rtl.copyWith(flowMode: NovelReaderFlowMode.vertical), 900).count,
      1,
    );
    expect(rtl.viewport.columns, NovelReaderColumnCount.triple);
  });

  test(
    'invalid values are isolated by codec and rejected at native projection',
    () {
      for (final edge in NovelReaderViewportEdge.values) {
        for (final invalid in [-1.0, 96.01, double.nan, double.infinity]) {
          final bad = _viewport.withMargin(edge, invalid);
          expect(
            _codec.normalize(_prefs(bad)).viewport,
            _viewport.withMargin(edge, null),
          );
          expect(
            () => resolveNovelReaderNativeViewport(_prefs(bad)),
            throwsArgumentError,
          );
        }
      }
      for (final number in [159.0, 2561.0, double.nan, double.infinity]) {
        final bad = _viewport.withContentWidth(
          NovelReaderContentWidth.limited(number),
        );
        expect(
          _codec.normalize(_prefs(bad)).viewport,
          _viewport.withContentWidth(null),
        );
        expect(
          () => resolveNovelReaderNativeViewport(_prefs(bad)),
          throwsArgumentError,
        );
      }
    },
  );
  test('per-field reset preserves unknown extensions idempotently', () {
    final raw = jsonDecode(_codec.encode(_prefs())) as Map;
    final viewport = raw['viewport'] as Map;
    (viewport['left'] as Map)['extension'] = ['keep', null];
    (viewport['contentWidth'] as Map)['extension'] = {'preserve': true};
    viewport['futureSetting'] = 42;
    final source = jsonEncode(raw);
    final reset = _codec.encode(
      _prefs(
        _viewport
            .withMargin(NovelReaderViewportEdge.left, null)
            .withContentWidth(null),
      ),
      previousSource: source,
    );
    final saved = (jsonDecode(reset) as Map)['viewport'] as Map;
    expect((saved['left'] as Map)['enabled'], false);
    expect((saved['left'] as Map)['extension'], ['keep', null]);
    expect((saved['contentWidth'] as Map)['enabled'], false);
    expect((saved['contentWidth'] as Map)['extension'], {'preserve': true});
    expect(saved['futureSetting'], 42);
    expect(
      _codec.decode(reset).viewport,
      _viewport
          .withMargin(NovelReaderViewportEdge.left, null)
          .withContentWidth(null),
    );
    expect(
      jsonDecode(_codec.encode(_codec.decode(reset), previousSource: reset)),
      jsonDecode(reset),
    );
  });
  for (final (field, unknown) in <(String?, Object)>[
    (null, {'schemaVersion': 2}),
    (null, 'futureNamespace'),
    ('left', {'unit': 'em', 'value': 2}),
    ('right', {'unit': 'logicalPixels', 'value': 4, 'enabled': 'future'}),
    ('top', 'futureShape'),
    ('contentWidth', {'unit': 'logicalPixels', 'mode': 'future', 'value': 500}),
    ('contentWidth', {'unit': 'em', 'mode': 'limited', 'value': 500}),
    ('columns', 'future'),
  ]) {
    test(
      'unknown viewport data survives unrelated edits and reset ($field, $unknown)',
      () async {
        final raw = jsonDecode(_codec.encode(_prefs())) as Map;
        if (field == null) {
          raw['viewport'] = unknown;
        } else {
          (raw['viewport'] as Map)[field] = unknown;
        }
        final source = ' ${jsonEncode(raw)} ';
        final storage = await SharedPreferences.getInstance();
        await storage.setString(
          PreferenceKeys.novelReaderSnapshotV1.name,
          source,
        );
        final loaded = await _repository().load();
        for (final next in [
          loaded.copyWith(fontSize: 24),
          loaded.copyWith(viewport: const NovelReaderViewportOverrides()),
        ]) {
          await expectLater(
            _repository().save(next),
            throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
          );
          expect(
            storage.getString(PreferenceKeys.novelReaderSnapshotV1.name),
            source,
          );
        }
      },
    );
  }
  test('a late namespace change is rechecked by the same writer', () async {
    final repo = _repository();
    await repo.save(_prefs());
    final loaded = await repo.load();
    final raw = jsonDecode(_codec.encode(loaded)) as Map;
    (raw['viewport'] as Map)['schemaVersion'] = 2;
    final source = jsonEncode(raw);
    final storage = await SharedPreferences.getInstance();
    await storage.setString(PreferenceKeys.novelReaderSnapshotV1.name, source);
    await expectLater(
      repo.save(loaded),
      throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
    );
    expect(
      storage.getString(PreferenceKeys.novelReaderSnapshotV1.name),
      source,
    );
  });
}

SharedPreferencesNovelReaderPreferencesRepository _repository() =>
    SharedPreferencesNovelReaderPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
      legacySource: _NoLegacy(),
    );

final class _NoLegacy implements NovelReaderPreferencesLegacySource {
  @override
  Future<NovelReaderPreferences?> load() async => null;
}
