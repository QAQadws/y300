import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/fonts/data/services/flutter_font_runtime_loader.dart';
import 'package:y300/features/fonts/domain/models/font_identity.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/imported_font.dart';
import 'package:y300/features/fonts/domain/services/font_file_validator.dart';

import '../test_support/font_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const validator = FontFileValidator();

  test(
    'registration is single-flight and cached by content identity',
    () async {
      final bytes = loadTestFont();
      final font = validator.validate(fileName: 'story.ttf', bytes: bytes);
      final pending = Completer<void>();
      var calls = 0;
      final loader = FlutterFontRuntimeLoader(
        registerFont: (loaded, family) {
          calls++;
          expect(loaded, orderedEquals(bytes));
          expect(family, FontIdentity.runtimeFamily(font.id));
          return pending.future;
        },
      );
      final first = loader.load(font, bytes);
      final second = loader.load(font, bytes);
      expect(identical(first, second), isTrue);
      pending.complete();
      expect(await first, FontIdentity.runtimeFamily(font.id));
      expect(await loader.load(font, bytes), await second);
      expect(calls, 1);
    },
  );

  test(
    'different content keeps same-named fonts in distinct families',
    () async {
      final registrations = <String>[];
      final loader = FlutterFontRuntimeLoader(
        registerFont: (_, family) async {
          registrations.add(family);
        },
      );
      for (final variant in [1, 2]) {
        final bytes = loadTestFont(variant: variant);
        final font = validator.validate(fileName: 'same.ttf', bytes: bytes);
        await loader.load(font, bytes);
      }
      expect(registrations.toSet(), hasLength(2));
    },
  );

  for (final synchronous in [false, true]) {
    test('failed registration can retry (synchronous=$synchronous)', () async {
      var calls = 0;
      final bytes = loadTestFont();
      final font = validator.validate(fileName: 'retry.ttf', bytes: bytes);
      final loader = FlutterFontRuntimeLoader(
        registerFont: (_, _) {
          calls++;
          if (calls == 1) {
            if (synchronous) throw StateError('registration rejected');
            return Future.error(StateError('registration rejected'));
          }
          return Future.value();
        },
      );
      await expectLater(
        loader.load(font, bytes),
        throwsA(
          isA<FontLibraryException>().having(
            (error) => error.code,
            'code',
            FontLibraryFailure.loadFailed,
          ),
        ),
      );
      expect(
        await loader.load(font, bytes),
        FontIdentity.runtimeFamily(font.id),
      );
      expect(calls, 2);
    });
  }

  test('rejects invalid metadata before calling the engine', () async {
    var calls = 0;
    final loader = FlutterFontRuntimeLoader(
      registerFont: (_, _) async {
        calls++;
      },
    );
    await expectLater(
      loader.load(
        const ImportedFont(
          id: '../escape',
          displayName: 'invalid',
          storageFileName: 'invalid.ttf',
          byteLength: 12,
        ),
        Uint8List(12),
      ),
      throwsA(isA<FontLibraryException>()),
    );
    final bytes = loadTestFont();
    final font = validator.validate(fileName: 'ok.ttf', bytes: bytes);
    await expectLater(
      loader.load(font, Uint8List(1)),
      throwsA(isA<FontLibraryException>()),
    );
    expect(calls, 0);
  });

  testWidgets(
    'real engine registration draws the fixture glyph rather than fallback',
    (tester) async {
      await tester.runAsync(() async {
        final bytes = loadTestFont();
        final font = validator.validate(fileName: 'real.ttf', bytes: bytes);
        final family = await FlutterFontRuntimeLoader().load(font, bytes);
        final actual = await _renderGlyph(family);
        final fallback = await _renderGlyph('Ahem');
        expect(actual, isNot(orderedEquals(fallback)));
        expect(actual.any((byte) => byte != 0), isTrue);
      });
    },
  );
}

Future<Uint8List> _renderGlyph(String family) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final painter = TextPainter(
    text: TextSpan(
      text: '\ue003',
      style: TextStyle(fontFamily: family, fontSize: 40, color: Colors.black),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, const Offset(4, 4));
  painter.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
