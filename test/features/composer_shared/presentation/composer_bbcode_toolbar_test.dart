import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/composer_bbcode_command.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_color_picker_sheet.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_toolbar.dart';

void main() {
  test('normalizes composer BBCode hex color', () {
    expect(normalizeComposerBbCodeHexColor('#F3A'), '#ff33aa');
    expect(normalizeComposerBbCodeHexColor('fff3b0'), '#fff3b0');
    expect(normalizeComposerBbCodeHexColor('#ggg'), isNull);
  });

  test('converts picker color to Discuz-safe lowercase hex', () {
    expect(composerBbCodeColorToHex(const Color(0x66112233)), '#112233');
  });

  testWidgets('ComposerBbCodeToolbar returns custom color command', (
    tester,
  ) async {
    ComposerBbCodeCommand? selected;
    await tester.pumpWidget(
      _buildToolbar(onCommandSelected: (command) => selected = command),
    );

    await tester.tap(find.byKey(const Key('reply-composer-color-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-composer-color-sheet')), findsOneWidget);
    final picker = tester.widget<ColorPicker>(
      find.byKey(const Key('reply-composer-color-picker')),
    );
    picker.onColorChanged(const Color(0xff112233));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-color-use-button')));
    await tester.pumpAndSettle();

    expect(selected?.openingTag, '[color=#112233]');
    expect(selected?.closingTag, '[/color]');
  });

  testWidgets('ComposerBbCodeToolbar returns custom backcolor command', (
    tester,
  ) async {
    ComposerBbCodeCommand? selected;
    await tester.pumpWidget(
      _buildToolbar(onCommandSelected: (command) => selected = command),
    );

    await tester.tap(find.byKey(const Key('reply-composer-backcolor-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('reply-composer-backcolor-sheet')),
      findsOneWidget,
    );
    final picker = tester.widget<ColorPicker>(
      find.byKey(const Key('reply-composer-backcolor-picker')),
    );
    picker.onColorChanged(const Color(0xffaabbcc));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('reply-composer-backcolor-use-button')),
    );
    await tester.pumpAndSettle();

    expect(selected?.openingTag, '[backcolor=#aabbcc]');
    expect(selected?.closingTag, '[/backcolor]');
  });

  testWidgets('ComposerBbCodeToolbar does not insert color on cancellation', (
    tester,
  ) async {
    ComposerBbCodeCommand? selected;
    await tester.pumpWidget(
      _buildToolbar(onCommandSelected: (command) => selected = command),
    );

    await tester.tap(find.byKey(const Key('reply-composer-color-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('reply-composer-color-cancel-button')),
    );
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });

  testWidgets('ComposerBbCodeToolbar returns link command from sheet', (
    tester,
  ) async {
    ComposerBbCodeCommand? selected;
    await tester.pumpWidget(
      _buildToolbar(onCommandSelected: (command) => selected = command),
    );

    await tester.tap(find.byKey(const Key('reply-composer-link-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-composer-link-sheet')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('reply-composer-link-url-input')),
      ' https://example.com/a?b=1 ',
    );
    await tester.enterText(
      find.byKey(const Key('reply-composer-link-label-input')),
      ' 示例链接 ',
    );
    await tester.tap(find.byKey(const Key('reply-composer-link-use-button')));
    await tester.pumpAndSettle();

    expect(selected?.openingTag, '[url=https://example.com/a?b=1]');
    expect(selected?.closingTag, '[/url]');
    expect(selected?.body, '示例链接');
  });

  testWidgets('ComposerBbCodeToolbar keeps link sheet open for empty fields', (
    tester,
  ) async {
    ComposerBbCodeCommand? selected;
    await tester.pumpWidget(
      _buildToolbar(onCommandSelected: (command) => selected = command),
    );

    await tester.tap(find.byKey(const Key('reply-composer-link-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reply-composer-link-use-button')));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.byKey(const Key('reply-composer-link-sheet')), findsOneWidget);
    expect(find.text('请输入链接'), findsOneWidget);
    expect(find.text('请输入链接文字'), findsOneWidget);
  });

  testWidgets('ComposerBbCodeToolbar link sheet reserves keyboard inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildToolbar(
        onCommandSelected: (_) {},
        viewInsets: const EdgeInsets.only(bottom: 280),
      ),
    );

    await tester.tap(find.byKey(const Key('reply-composer-link-button')));
    await tester.pumpAndSettle();

    final scrollView = tester.widget<SingleChildScrollView>(
      find
          .ancestor(
            of: find.byKey(const Key('reply-composer-link-sheet')),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect((scrollView.padding! as EdgeInsets).bottom, 296);
  });

  testWidgets('ComposerBbCodeToolbar does not insert size on dismissal', (
    tester,
  ) async {
    ComposerBbCodeCommand? selected;
    await tester.pumpWidget(
      _buildToolbar(onCommandSelected: (command) => selected = command),
    );

    await tester.tap(find.byKey(const Key('reply-composer-size-button')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });

  testWidgets('ComposerBbCodeToolbar returns align command', (tester) async {
    ComposerBbCodeCommand? selected;
    await tester.pumpWidget(
      _buildToolbar(onCommandSelected: (command) => selected = command),
    );

    await tester.tap(find.byKey(const Key('reply-composer-align-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reply-composer-align-center')));
    await tester.pumpAndSettle();

    expect(selected?.openingTag, '[align=center]');
    expect(selected?.closingTag, '[/align]');
  });

  testWidgets('ComposerBbCodeToolbar places align before quote', (
    tester,
  ) async {
    await tester.pumpWidget(_buildToolbar(onCommandSelected: (_) {}));

    final alignCenter = tester.getCenter(
      find.byKey(const Key('reply-composer-align-button')),
    );
    final quoteCenter = tester.getCenter(
      find.byKey(const Key('reply-composer-quote-button')),
    );

    expect(alignCenter.dx, lessThan(quoteCenter.dx));
  });

  testWidgets('ComposerBbCodeToolbar returns quote command', (tester) async {
    ComposerBbCodeCommand? selected;
    await tester.pumpWidget(
      _buildToolbar(onCommandSelected: (command) => selected = command),
    );

    expect(find.byKey(const Key('reply-composer-code-button')), findsNothing);

    await tester.tap(find.byKey(const Key('reply-composer-quote-button')));
    await tester.pump();

    expect(selected?.openingTag, '[quote]');
    expect(selected?.closingTag, '[/quote]');
  });
}

Widget _buildToolbar({
  required ValueChanged<ComposerBbCodeCommand> onCommandSelected,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  return MaterialApp(
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: viewInsets),
        child: child!,
      );
    },
    home: Scaffold(
      body: ComposerBbCodeToolbar(
        onStickerPressed: () {},
        onCommandSelected: onCommandSelected,
      ),
    ),
  );
}
