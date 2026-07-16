import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_inline_style_declarations.dart';

void main() {
  const codec = CssInlineStyleDeclarationCodec();

  group('CssInlineStyleDeclarationCodec', () {
    test('parses mixed declarations through csslib AST', () {
      final declarations = codec.tryParse(
        'FONT-SIZE: 18px; '
        'color: rgba(10, 20, 30, .5) !important; '
        'text-align: center; '
        'text-decoration: underline',
      )!;

      expect(
        declarations.declarations.map((declaration) => declaration.property),
        <String>['font-size', 'color', 'text-align', 'text-decoration'],
      );
      final color = declarations.effectiveDeclaration(const <String>{'color'});
      expect(color?.value, 'rgba(10, 20, 30, .5)');
      expect(color?.important, isTrue);
    });

    test('removes and updates color without damaging unrelated styles', () {
      final declarations = codec.tryParse(
        'font-size: 18px; '
        'color: rgba(10, 20, 30, .5); '
        'background-color: rgb(100%, 0%, 50%); '
        'text-align: center; '
        'text-decoration: underline',
      )!;

      final withoutColors = declarations.withoutProperties(const <String>{
        'color',
        'background-color',
      });
      final updated = declarations.upsert(property: 'color', value: '#112233');

      expect(
        withoutColors.toCss(),
        'font-size: 18px; text-align: center; text-decoration: underline',
      );
      expect(updated.toCss(), contains('font-size: 18px'));
      expect(updated.toCss(), contains('background-color: rgb(100%, 0%, 50%)'));
      expect(updated.toCss(), contains('text-align: center'));
      expect(updated.toCss(), contains('text-decoration: underline'));
      expect(updated.toCss(), endsWith('color: #112233'));
      expect(
        updated.declarations.where(
          (declaration) => declaration.property == 'color',
        ),
        hasLength(1),
      );
    });

    test('honors important before declaration order', () {
      final declarations = codec.tryParse(
        'color: red !important; color: blue; background: white',
      )!;

      expect(
        declarations.effectiveDeclaration(const <String>{'color'})?.value,
        'red',
      );
    });

    test('keeps unsupported var values in the recovered declaration AST', () {
      final declarations = codec.tryParse(
        'color: var(--author, rgb(1, 2, 3)); text-align: center',
      )!;

      expect(
        declarations.effectiveDeclaration(const <String>{'color'})?.value,
        'var(--author, rgb(1, 2, 3))',
      );
      expect(declarations.toCss(), contains('text-align: center'));
    });

    test('returns null for malformed declarations', () {
      expect(codec.tryParse('color: rgba(1, 2; text-align: center'), isNull);
    });
  });
}
