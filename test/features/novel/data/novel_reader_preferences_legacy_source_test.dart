import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temp;
  late String dbPath;
  late Database db;
  late SqliteNovelReaderPreferencesLegacySource source;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('y300-novel-reader-legacy-');
    dbPath = p.join(temp.path, 'reader.db');
    db = await ComicLocalDb.open(databaseName: dbPath);
    source = SqliteNovelReaderPreferencesLegacySource(
      Future<Database>.value(db),
    );
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(dbPath);
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('reads valid supported fields and resets obsolete meanings', () async {
    await db.insert(ComicLocalDb.readerPreferencesTable, <String, Object?>{
      'content_type': 'novel',
      'font_size': 19.0,
      'line_height': 1.9,
      'paragraph_spacing': 28.0,
      'page_padding': 30.0,
      'theme_mode': 'light',
      'font_family': 'custom',
      'flow_mode': 'pagedRtl',
      'theme_preset': 'dark',
      'content_max_width': 500.0,
      'first_line_indent': 20.0,
      'font_weight': 700,
      'text_align': 'justify',
      'show_progress_indicator': 0,
      'show_chapter_title': 1,
      'conversion_mode': 'toSimplified',
    });

    final loaded = await source.load();

    expect(loaded, isNotNull);
    expect(loaded!.fontSize, 19);
    expect(loaded.lineHeight, 1.9);
    expect(loaded.themePreset, NovelReaderThemePreset.dark);
    expect(loaded.conversionMode, NovelReaderConversionMode.toSimplified);
    expect(loaded.flowMode, NovelReaderFlowMode.vertical);
    expect(loaded.paragraphSpacing, 10);
    expect(loaded.pagePadding, 16);
    expect(loaded.fontFamily, 'system');
    expect(loaded.contentMaxWidth, 720);
    expect(loaded.firstLineIndent, 0);
    expect(loaded.fontWeight, 400);
    expect(loaded.textAlign, NovelReaderTextAlignMode.start);
    expect(loaded.showProgressIndicator, isTrue);
  });

  test('invalid legacy display values fall back to new defaults', () async {
    await db.insert(ComicLocalDb.readerPreferencesTable, <String, Object?>{
      'content_type': 'novel',
      'font_size': 100.0,
      'line_height': 0.5,
      'paragraph_spacing': 10.0,
      'page_padding': 16.0,
      'theme_mode': 'future-theme',
      'font_family': 'system',
      'conversion_mode': 'future-conversion',
    });

    expect(await source.load(), NovelReaderPreferences.defaults());
  });
}
