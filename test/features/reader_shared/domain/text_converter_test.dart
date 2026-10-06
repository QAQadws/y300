import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/opencc_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IdentityTextConverter', () {
    const converter = IdentityTextConverter();

    test('id is conv:none', () {
      expect(converter.id, 'conv:none');
    });

    test('mode is none', () {
      expect(converter.mode, TextConversionMode.none);
    });

    test('convertHtml returns input unchanged', () async {
      const html = '<p>你好世界</p>';
      expect(await converter.convertHtml(html), html);
    });

    test('convertHtml handles empty string', () async {
      expect(await converter.convertHtml(''), '');
    });
  });

  group('OpenccTextConverter', () {
    const channel = MethodChannel('flutter_open_chinese_convert');
    late List<MethodCall> nativeCalls;

    setUp(() {
      nativeCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeCalls.add(call);
            return (call.arguments as List<Object?>).first as String;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    for (final direction in [
      (TextConversionMode.toTraditional, 's2t'),
      (TextConversionMode.toSimplified, 't2s'),
    ]) {
      test(
        '${direction.$2} delegates long text to the native worker',
        () async {
          final converter = resolveTextConverter(direction.$1);
          final html = '<p>${'繁简正文' * 4000}</p>';

          expect(await converter.convertHtml(html), html);
          final call = nativeCalls.single;
          expect(call.method, 'convert');
          final arguments = call.arguments as List<Object?>;
          expect(arguments[0], html);
          expect(arguments[1], direction.$2);
          // This chooses the plugin's native worker, not its UI-thread branch.
          expect(arguments[2], isTrue);
        },
      );
    }

    test('empty input does not dispatch native work', () async {
      const converter = OpenccTextConverter(
        mode: TextConversionMode.toTraditional,
      );

      expect(await converter.convertHtml(''), '');
      expect(nativeCalls, isEmpty);
    });

    test('toTraditional has s2t in id', () {
      const converter = OpenccTextConverter(
        mode: TextConversionMode.toTraditional,
      );
      expect(converter.id, contains('s2t'));
      expect(converter.mode, TextConversionMode.toTraditional);
    });

    test('toSimplified has t2s in id', () {
      const converter = OpenccTextConverter(
        mode: TextConversionMode.toSimplified,
      );
      expect(converter.id, contains('t2s'));
      expect(converter.mode, TextConversionMode.toSimplified);
    });

    test('ids differ between directions', () {
      const s2t = OpenccTextConverter(mode: TextConversionMode.toTraditional);
      const t2s = OpenccTextConverter(mode: TextConversionMode.toSimplified);
      expect(s2t.id, isNot(t2s.id));
    });
  });

  group('resolveTextConverter', () {
    test('none resolves to IdentityTextConverter', () {
      final converter = resolveTextConverter(TextConversionMode.none);
      expect(converter, isA<IdentityTextConverter>());
    });

    test('toTraditional resolves to OpenccTextConverter s2t', () {
      final converter = resolveTextConverter(TextConversionMode.toTraditional);
      expect(converter, isA<OpenccTextConverter>());
      expect(converter.id, contains('s2t'));
    });

    test('toSimplified resolves to OpenccTextConverter t2s', () {
      final converter = resolveTextConverter(TextConversionMode.toSimplified);
      expect(converter, isA<OpenccTextConverter>());
      expect(converter.id, contains('t2s'));
    });
  });
}
