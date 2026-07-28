import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_message_insertion_service.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_selection_adapter.dart';
import 'package:y300/features/composer_shared/domain/services/composer_sticker_image_cache_loader.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_source_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_image.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_editor.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';

void main() {
  testWidgets('composer surfaces align with native forum body spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 240,
            child: ComposerQuillEditorSurface(
              key: const Key('spacing-quill-surface'),
              keyPrefix: 'spacing-quill',
              minHeight: 120,
            ),
          ),
        ),
      ),
    );

    final quillSurface = tester.widget<ComposerQuillEditorSurface>(
      find.byKey(const Key('spacing-quill-surface')),
    );
    final quillPadding = quillSurface.contentPadding.resolve(TextDirection.ltr);
    expect(
      quillPadding.left + ForumContentSpacing.quillInnerHorizontal,
      ForumContentSpacing.readableBodyHorizontal,
    );

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: ComposerBbCodeSourceEditor(
                viewKey: const Key('spacing-source-editor'),
                inputKey: const Key('spacing-source-input'),
                controller: TextEditingController(),
                enabled: true,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final sourcePadding = tester.widget<Padding>(
      find.byKey(const Key('spacing-source-editor')),
    );
    final resolvedSourcePadding = sourcePadding.padding.resolve(
      TextDirection.ltr,
    );
    expect(
      resolvedSourcePadding.left + ForumContentSpacing.composerPageHorizontal,
      ForumContentSpacing.readableBodyHorizontal,
    );
  });

  testWidgets('ComposerQuillPrototypeEditor exposes WYSIWYG toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(_buildEditor());

    expect(find.byKey(const Key('test-quill-format-button')), findsOneWidget);
    expect(find.byKey(const Key('test-quill-align-button')), findsOneWidget);
    expect(find.byKey(const Key('test-quill-quote-button')), findsOneWidget);
    expect(find.byKey(const Key('test-quill-link-button')), findsOneWidget);
    expect(find.byKey(const Key('test-quill-sticker-button')), findsOneWidget);
    expect(find.byKey(const Key('test-quill-image-button')), findsOneWidget);
    expect(find.byKey(const Key('test-quill-bbcode-output')), findsNothing);
    expect(
      find.ancestor(
        of: find.byKey(const Key('test-quill-format-button')),
        matching: find.byWidgetPredicate((widget) {
          return widget is Material &&
              widget.color ==
                  AppTheme.light().colorScheme.surfaceContainerHighest;
        }),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('test-quill-editor')),
        matching: find.byWidgetPredicate((widget) {
          if (widget is! DecoratedBox) {
            return false;
          }
          final decoration = widget.decoration;
          return decoration is BoxDecoration && decoration.border != null;
        }),
      ),
      findsNothing,
    );
  });

  testWidgets('format button toggles an embedded tool panel', (tester) async {
    await tester.pumpWidget(_buildEditor());

    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test-quill-tool-panel')), findsOneWidget);
    expect(find.byKey(const Key('test-quill-format-sheet')), findsOneWidget);
    expect(find.text('格式'), findsNothing);
    _expectIconButtonIcon(
      tester,
      const Key('test-quill-format-bold-toggle'),
      Icons.format_bold,
    );
    _expectIconButtonIcon(
      tester,
      const Key('test-quill-format-italic-toggle'),
      Icons.format_italic,
    );
    _expectIconButtonIcon(
      tester,
      const Key('test-quill-format-underline-toggle'),
      Icons.format_underline,
    );
    _expectIconButtonIcon(
      tester,
      const Key('test-quill-format-strike-toggle'),
      Icons.format_strikethrough,
    );
    expect(
      find.byKey(const Key('test-quill-format-clear-state-button')),
      findsOneWidget,
    );
    _expectClearStateOnFormatRow(tester);
    _expectSizeControlsStayOnOneLine(tester);

    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test-quill-tool-panel')), findsNothing);
  });

  testWidgets(
    'closing the active tool panel keeps toolbar raised until keyboard returns',
    (tester) async {
      const keyboardInsets = EdgeInsets.only(bottom: 320);
      await tester.pumpWidget(_buildEditor(viewInsets: keyboardInsets));
      await tester.pump();

      await tester.tap(find.byKey(const Key('test-quill-format-button')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_buildEditor());
      await tester.pump();

      expect(find.byKey(const Key('test-quill-tool-panel')), findsOneWidget);
      final panelGap = _toolbarBottomGap(tester);
      expect(panelGap, greaterThan(260));

      await tester.tap(find.byKey(const Key('test-quill-format-button')));
      await tester.pump();

      expect(find.byKey(const Key('test-quill-tool-panel')), findsNothing);
      final waitingForKeyboardGap = _toolbarBottomGap(tester);
      expect(waitingForKeyboardGap, greaterThan(260));

      await tester.pumpWidget(_buildEditor(viewInsets: keyboardInsets));
      await tester.pump();

      final keyboardGap = _toolbarBottomGap(tester);
      expect(keyboardGap, greaterThan(260));
    },
  );

  testWidgets('an externally opened keyboard dismisses the active tool panel', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_buildEditor(controller: controller));

    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-quill-tool-panel')), findsOneWidget);

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        viewInsets: const EdgeInsets.only(bottom: 320),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test-quill-tool-panel')), findsNothing);
    expect(_toolbarBottomGap(tester), greaterThan(260));
  });

  testWidgets('format sheet applies selected text formatting immediately', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
      ),
    );
    controller.replaceText(
      0,
      0,
      '文字',
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('test-quill-format-apply-button')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('test-quill-format-bold-toggle')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('test-quill-format-underline-toggle')),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-size-4')),
    );
    await tester.tap(find.byKey(const Key('test-quill-format-size-4')));
    await tester.pump();
    expect(
      controller.getSelectionStyle().attributes[Attribute.size.key]?.value,
      '18',
    );
    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-color-swatch-d32f2f')),
    );
    await tester.tap(
      find.byKey(const Key('test-quill-format-color-swatch-d32f2f')),
    );
    await tester.pump();

    expect(latest, '[b][u][size=4][color=#d32f2f]文字[/color][/size][/u][/b]');
  });

  testWidgets('format options do not refocus the editor until tool closes', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_buildEditor(controller: controller));
    controller.replaceText(
      0,
      0,
      '文字',
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    await tester.pump();

    final editorFocusNode = _editorFocusNode(tester);
    editorFocusNode.requestFocus();
    await tester.pump();
    expect(editorFocusNode.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();
    expect(editorFocusNode.hasFocus, isFalse);

    await tester.tap(find.byKey(const Key('test-quill-format-bold-toggle')));
    await tester.pump();
    expect(editorFocusNode.hasFocus, isFalse);
    await tester.tap(find.byKey(const Key('test-quill-format-italic-toggle')));
    await tester.pump();
    expect(editorFocusNode.hasFocus, isFalse);
    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-size-4')),
    );
    await tester.tap(find.byKey(const Key('test-quill-format-size-4')));
    await tester.pump();
    expect(editorFocusNode.hasFocus, isFalse);
    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-color-swatch-d32f2f')),
    );
    await tester.tap(
      find.byKey(const Key('test-quill-format-color-swatch-d32f2f')),
    );
    await tester.pump();
    expect(editorFocusNode.hasFocus, isFalse);

    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-button')),
    );
    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pump();

    expect(find.byKey(const Key('test-quill-tool-panel')), findsNothing);
    expect(editorFocusNode.hasFocus, isTrue);
  });

  testWidgets(
    'tapping a normal editor position closes tools and adopts nearby style',
    (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      controller.replaceText(
        0,
        0,
        '普通斜体',
        const TextSelection.collapsed(offset: 0),
      );
      controller.formatText(2, 2, Attribute.italic);

      await tester.pumpWidget(_buildEditor(controller: controller));
      await tester.tap(find.byKey(const Key('test-quill-format-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('test-quill-format-bold-toggle')));
      await tester.pump();

      _dispatchEditorTap(tester, controller: controller, offset: 3);
      await tester.pump();

      expect(find.byKey(const Key('test-quill-tool-panel')), findsNothing);
      expect(controller.toggledStyle.isEmpty, isTrue);
      expect(
        controller.getSelectionStyle().attributes[Attribute.italic.key]?.value,
        isTrue,
      );
      expect(
        controller.getSelectionStyle().attributes[Attribute.bold.key],
        isNull,
      );

      await tester.tap(find.byKey(const Key('test-quill-format-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test-quill-tool-panel')), findsOneWidget);
    },
  );

  testWidgets('tapping document end restores the explicitly selected style', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(
      0,
      0,
      '普通末尾',
      const TextSelection.collapsed(offset: 0),
    );
    controller.formatText(2, 2, Attribute.italic);
    controller.formatText(2, 2, Attribute.clone(Attribute.color, '#d32f2f'));

    await tester.pumpWidget(_buildEditor(controller: controller));
    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-quill-format-bold-toggle')));
    await tester.pump();

    _dispatchEditorTap(tester, controller: controller, offset: 4);
    await tester.pump();
    controller.replaceText(4, 0, '新', const TextSelection.collapsed(offset: 5));
    await tester.pump();

    final insertedStyle = controller.document.collectStyle(4, 1).attributes;
    expect(find.byKey(const Key('test-quill-tool-panel')), findsNothing);
    expect(insertedStyle[Attribute.bold.key]?.value, isTrue);
    expect(insertedStyle[Attribute.italic.key], isNull);
    expect(insertedStyle[Attribute.color.key], isNull);
  });

  testWidgets(
    'align and sticker tools mutate content without refocusing editor',
    (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      String latest = '';

      await tester.pumpWidget(
        _buildEditor(
          controller: controller,
          onBbCodeChanged: (value) => latest = value,
          stickerGroups: _stickerGroups(),
        ),
      );
      final editorFocusNode = _editorFocusNode(tester);
      editorFocusNode.requestFocus();
      await tester.pump();

      await tester.tap(find.byKey(const Key('test-quill-align-button')));
      await tester.pumpAndSettle();
      expect(editorFocusNode.hasFocus, isFalse);
      await tester.tap(find.byKey(const Key('test-quill-align-center')));
      await tester.pump();
      expect(editorFocusNode.hasFocus, isFalse);
      expect(
        _currentLineAlignment(controller),
        Attribute.centerAlignment.value,
      );

      await tester.tap(find.byKey(const Key('test-quill-sticker-button')));
      await tester.pumpAndSettle();
      expect(editorFocusNode.hasFocus, isFalse);
      await tester.tap(
        find.byKey(const Key('test-quill-sticker-item-{:9_656:}')),
      );
      await tester.pump();

      expect(editorFocusNode.hasFocus, isFalse);
      expect(latest, '[align=center]{:9_656:}[/align]');
    },
  );

  testWidgets('format toggles affect future input and can be turned off', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-quill-format-bold-toggle')));
    await tester.pump();

    controller.replaceText(0, 0, '粗体', null);
    await tester.pump();

    await tester.tap(find.byKey(const Key('test-quill-format-bold-toggle')));
    await tester.pump();
    controller.replaceText(2, 0, '普通', null);
    await tester.pump();

    expect(latest, '[b]粗体[/b]普通');
  });

  testWidgets('active selected text format can be removed immediately', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
      ),
    );
    controller.replaceText(
      0,
      0,
      '文字',
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    controller.formatSelection(Attribute.bold);
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 2),
      ChangeSource.local,
    );
    await tester.pump();
    expect(latest, '[b]文字[/b]');

    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-quill-format-bold-toggle')));
    await tester.pump();

    expect(latest, '文字');
  });

  testWidgets('size color and background clear immediately', (tester) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
      ),
    );
    controller.replaceText(
      0,
      0,
      '文字',
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-size-4')),
    );
    await tester.tap(find.byKey(const Key('test-quill-format-size-4')));
    await tester.pump();
    expect(latest, '[size=4]文字[/size]');
    expect(
      controller.getSelectionStyle().attributes[Attribute.size.key]?.value,
      '18',
    );

    await tester.tap(find.byKey(const Key('test-quill-format-size-4')));
    await tester.pump();
    expect(latest, '文字');

    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-color-swatch-d32f2f')),
    );
    await tester.tap(
      find.byKey(const Key('test-quill-format-color-swatch-d32f2f')),
    );
    await tester.pump();
    expect(latest, '[color=#d32f2f]文字[/color]');

    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-color-swatch-ffffff')),
    );
    await tester.tap(
      find.byKey(const Key('test-quill-format-color-swatch-ffffff')),
    );
    await tester.pump();
    expect(latest, '[color=#ffffff]文字[/color]');

    await tester.tap(
      find.byKey(const Key('test-quill-format-clear-color-button')),
    );
    await tester.pump();
    expect(latest, '文字');

    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-backcolor-swatch-fff3b0')),
    );
    await tester.tap(
      find.byKey(const Key('test-quill-format-backcolor-swatch-fff3b0')),
    );
    await tester.pump();
    expect(latest, '[backcolor=#fff3b0]文字[/backcolor]');

    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-clear-backcolor-button')),
    );
    await tester.tap(
      find.byKey(const Key('test-quill-format-clear-backcolor-button')),
    );
    await tester.pump();
    expect(latest, '文字');
  });

  testWidgets(
    'clear state removes every managed style from a mixed selection',
    (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      String latest = '';

      await tester.pumpWidget(
        _buildEditor(
          controller: controller,
          onBbCodeChanged: (value) => latest = value,
        ),
      );
      controller.replaceText(
        0,
        0,
        '甲乙',
        const TextSelection.collapsed(offset: 2),
      );
      controller.formatText(0, 1, Attribute.bold);
      controller.formatText(0, 1, Attribute.italic);
      controller.formatText(0, 1, Attribute.underline);
      controller.formatText(0, 1, Attribute.strikeThrough);
      controller.formatText(0, 1, Attribute.clone(Attribute.size, '18'));
      controller.formatText(0, 1, Attribute.clone(Attribute.color, '#d32f2f'));
      controller.formatText(
        0,
        1,
        Attribute.clone(Attribute.background, '#fff3b0'),
      );
      controller.formatText(
        0,
        1,
        Attribute.clone(Attribute.link, 'https://example.com'),
      );
      controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 2),
        ChangeSource.local,
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('test-quill-format-button')));
      await tester.pumpAndSettle();
      final clearButton = tester.widget<TextButton>(
        find.byKey(const Key('test-quill-format-clear-state-button')),
      );
      expect(clearButton.onPressed, isNotNull);
      await tester.tap(
        find.byKey(const Key('test-quill-format-clear-state-button')),
      );
      await tester.pump();

      expect(latest, '[url=https://example.com]甲[/url]乙');
    },
  );

  testWidgets('clear state isolates future input at a collapsed caret', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(
      0,
      0,
      '末尾',
      const TextSelection.collapsed(offset: 2),
    );
    controller.formatText(0, 2, Attribute.bold);
    controller.formatText(0, 2, Attribute.italic);
    controller.formatText(0, 2, Attribute.clone(Attribute.size, '18'));
    controller.formatText(0, 2, Attribute.clone(Attribute.color, '#d32f2f'));
    controller.updateSelection(
      const TextSelection.collapsed(offset: 2),
      ChangeSource.local,
    );

    await tester.pumpWidget(_buildEditor(controller: controller));
    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('test-quill-format-clear-state-button')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pump();
    controller.replaceText(2, 0, '新', const TextSelection.collapsed(offset: 3));
    await tester.pump();

    final insertedStyle = controller.document.collectStyle(2, 1).attributes;
    expect(insertedStyle[Attribute.bold.key], isNull);
    expect(insertedStyle[Attribute.italic.key], isNull);
    expect(insertedStyle[Attribute.size.key], isNull);
    expect(insertedStyle[Attribute.color.key], isNull);
  });

  testWidgets('size 3 exports normal Discuz size only when selected', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
      ),
    );
    controller.replaceText(
      0,
      0,
      '文字',
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    await tester.pump();
    expect(latest, '文字');

    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('test-quill-format-size-3')),
    );
    await tester.tap(find.byKey(const Key('test-quill-format-size-3')));
    await tester.pump();

    expect(latest, '[size=3]文字[/size]');
    expect(
      controller.getSelectionStyle().attributes[Attribute.size.key]?.value,
      '16',
    );
  });

  testWidgets('link sheet inserts label and exports url BBCode', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-link-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-quill-tool-panel')), findsNothing);
    final linkUrlEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('test-quill-link-url-input')),
        matching: find.byType(EditableText),
      ),
    );
    expect(linkUrlEditable.focusNode.hasFocus, isTrue);
    await tester.enterText(
      find.byKey(const Key('test-quill-link-url-input')),
      'https://example.com',
    );
    await tester.enterText(
      find.byKey(const Key('test-quill-link-label-input')),
      '示例',
    );
    await tester.tap(find.byKey(const Key('test-quill-link-use-button')));
    await tester.pumpAndSettle();

    expect(latest, '[url=https://example.com]示例[/url]');
  });

  testWidgets('cancelling link sheet returns focus without changing content', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(
      0,
      0,
      '正文',
      const TextSelection.collapsed(offset: 2),
    );

    await tester.pumpWidget(_buildEditor(controller: controller));
    await tester.tap(find.byKey(const Key('test-quill-link-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-quill-link-cancel-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test-quill-link-sheet')), findsNothing);
    expect(_editorFocusNode(tester).hasFocus, isTrue);
    expect(controller.document.toPlainText(), '正文\n');
  });

  testWidgets(
    'collapsed link insertion does not inherit active inline styles',
    (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      String latest = '';

      await tester.pumpWidget(
        _buildEditor(
          controller: controller,
          onBbCodeChanged: (value) => latest = value,
        ),
      );

      await tester.tap(find.byKey(const Key('test-quill-format-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('test-quill-format-bold-toggle')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('test-quill-format-size-4')),
      );
      await tester.tap(find.byKey(const Key('test-quill-format-size-4')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('test-quill-format-color-swatch-d32f2f')),
      );
      await tester.tap(
        find.byKey(const Key('test-quill-format-color-swatch-d32f2f')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('test-quill-link-button')),
      );
      await tester.tap(find.byKey(const Key('test-quill-link-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('test-quill-link-url-input')),
        'https://example.com',
      );
      await tester.enterText(
        find.byKey(const Key('test-quill-link-label-input')),
        '示例',
      );
      await tester.tap(find.byKey(const Key('test-quill-link-use-button')));
      await tester.pumpAndSettle();

      expect(latest, '[url=https://example.com]示例[/url]');
    },
  );

  testWidgets('multi line quote exports as one continuous quote block', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
      ),
    );
    controller.replaceText(
      0,
      0,
      '第一行\n第二行',
      const TextSelection(baseOffset: 0, extentOffset: 7),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('test-quill-quote-button')));
    await tester.pump();

    expect(latest, '[quote]第一行\n第二行[/quote]');
  });

  testWidgets(
    'quote toggles on a normal blank line after exiting quote as a new block',
    (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      String latest = '';

      await tester.pumpWidget(
        _buildEditor(
          controller: controller,
          onBbCodeChanged: (value) => latest = value,
        ),
      );

      await tester.tap(find.byKey(const Key('test-quill-quote-button')));
      await tester.pump();
      controller.replaceText(
        0,
        0,
        '旧引用',
        const TextSelection.collapsed(offset: 3),
      );
      await tester.pump();
      controller.replaceText(
        3,
        0,
        '\n',
        const TextSelection.collapsed(offset: 4),
      );
      await tester.pump();
      controller.replaceText(
        4,
        0,
        '\n',
        const TextSelection.collapsed(offset: 5),
      );
      await tester.pump();

      expect(_currentLineIsQuoted(controller), isFalse);

      await tester.tap(find.byKey(const Key('test-quill-quote-button')));
      await tester.pump();

      expect(_currentLineIsQuoted(controller), isTrue);

      final offset = controller.selection.start;
      controller.replaceText(
        offset,
        0,
        '新引用',
        TextSelection.collapsed(offset: offset + 3),
      );
      await tester.pump();

      expect(latest, '[quote]旧引用[/quote]\n[quote]新引用[/quote]');
    },
  );

  testWidgets('sticker and image callbacks insert embeds and export BBCode', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
        onImagePressed: (anchor) async {
          _insertTestAttachment(controller, anchor);
        },
        imageAttachments: [_uploadedAttachment()],
        attachImageBuilder: _buildTestAttachPreviewImage,
        attachFileExists: _testAttachFileExists,
        stickerGroups: _stickerGroups(),
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-sticker-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('test-quill-sticker-item-{:9_656:}')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('test-quill-image-button')));
    await tester.pumpAndSettle();

    expect(latest, '{:9_656:}\n[attach]123456[/attach]');
    final stickerImage = tester.widget<ComposerStickerImage>(
      find.byKey(const Key('composer-quill-sticker-{:9_656:}')),
    );
    expect(stickerImage.width, isNull);
    expect(stickerImage.height, isNull);
    final frame = tester.widget<ConstrainedBox>(
      find.byKey(const Key('composer-quill-sticker-frame-{:9_656:}')),
    );
    expect(frame.constraints.maxWidth, 96);
    expect(frame.constraints.maxHeight, 96);
    expect(
      find.byKey(const Key('composer-quill-attach-image-123456')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-quill-attach-123456')),
      findsOneWidget,
    );
  });

  testWidgets('a hand written legal attach code renders its image', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
        imageAttachments: [_uploadedAttachment()],
        attachImageBuilder: _buildTestAttachPreviewImage,
        attachFileExists: _testAttachFileExists,
      ),
    );

    controller.replaceText(
      0,
      0,
      '[attach]123456[/attach]',
      const TextSelection.collapsed(offset: 23),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-attach-image-123456')),
      findsOneWidget,
    );
    expect(latest, '[attach]123456[/attach]');
    // 归一后光标落到图片之后，逻辑宽度收缩为 1。
    expect(controller.selection.baseOffset, 1);
  });

  testWidgets('an illegal attach code stays editable text', (tester) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
        imageAttachments: [_uploadedAttachment()],
        attachImageBuilder: _buildTestAttachPreviewImage,
        attachFileExists: _testAttachFileExists,
      ),
    );

    controller.replaceText(
      0,
      0,
      '[attach]abc[/attach]',
      const TextSelection.collapsed(offset: 20),
    );
    await tester.pumpAndSettle();

    expect(find.byType(_TestAttachPreviewImage), findsNothing);
    expect(latest, '[attach]abc[/attach]');
    expect(
      controller.document.toPlainText().trimRight(),
      '[attach]abc[/attach]',
    );
  });

  testWidgets('a deleted image renders again once its code is retyped', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
        onImagePressed: (anchor) async {
          _insertTestAttachment(controller, anchor);
        },
        imageAttachments: [_uploadedAttachment()],
        attachImageBuilder: _buildTestAttachPreviewImage,
        attachFileExists: _testAttachFileExists,
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-image-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-quill-attach-image-123456')),
      findsOneWidget,
    );
    final withImage = latest;

    // 手动删掉图片节点。
    controller.replaceText(0, 1, '', const TextSelection.collapsed(offset: 0));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-quill-attach-image-123456')),
      findsNothing,
    );

    // 再把同一段 attach 代码原样写回去：编码结果与删除前完全相同，
    // 这条用例专门覆盖 `next == _bbCodeText` 的提前返回路径。
    controller.replaceText(
      0,
      0,
      '[attach]123456[/attach]',
      const TextSelection.collapsed(offset: 23),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-attach-image-123456')),
      findsOneWidget,
    );
    expect(latest, withImage);
  });

  testWidgets('sticker drawer pages by sticker group', (tester) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
        stickerGroups: _stickerGroups(),
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-sticker-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test-quill-sticker-tabs')), findsOneWidget);
    expect(
      find.byKey(const Key('test-quill-sticker-group-tab-bugcat')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('test-quill-sticker-group-tab-azukisan')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('test-quill-sticker-item-{:9_656:}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('test-quill-sticker-item-{:6_1:}')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('test-quill-sticker-group-tab-azukisan')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('test-quill-sticker-item-{:6_1:}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('test-quill-sticker-item-{:6_1:}')));
    await tester.pump();

    expect(latest, '{:6_1:}');
    expect(find.byKey(const Key('test-quill-sticker-sheet')), findsOneWidget);
  });

  testWidgets('sticker drawer restores and reports the shared group id', (
    tester,
  ) async {
    String? selectedGroupId;
    await tester.pumpWidget(
      _buildEditor(
        stickerGroups: _stickerGroups(),
        initialStickerGroupId: 'azukisan',
        onStickerGroupChanged: (groupId) => selectedGroupId = groupId,
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-sticker-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('test-quill-sticker-item-{:6_1:}')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('test-quill-sticker-group-tab-bugcat')),
    );
    await tester.pumpAndSettle();

    expect(selectedGroupId, 'bugcat');
  });

  testWidgets('unknown sticker group falls back to the first group', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildEditor(
        stickerGroups: _stickerGroups(),
        initialStickerGroupId: 'removed-group',
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-sticker-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('test-quill-sticker-item-{:9_656:}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('test-quill-sticker-item-{:6_1:}')),
      findsNothing,
    );
  });

  testWidgets('inserted embeds can be deleted before continuing text', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
        onImagePressed: (anchor) async {
          _insertTestAttachment(controller, anchor);
        },
        imageAttachments: [_uploadedAttachment()],
        stickerGroups: _stickerGroups(),
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-sticker-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('test-quill-sticker-item-{:9_656:}')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('test-quill-image-button')));
    await tester.pumpAndSettle();

    controller.replaceText(0, 1, '', const TextSelection.collapsed(offset: 0));
    controller.replaceText(
      1,
      0,
      '后续',
      const TextSelection.collapsed(offset: 3),
    );
    await tester.pump();

    expect(latest, '\n后续[attach]123456[/attach]');
  });
}

bool _currentLineIsQuoted(QuillController controller) {
  final index = controller.selection.start
      .clamp(0, controller.document.length)
      .toInt();
  final query = controller.document.queryChild(index);
  final line = query.node;
  if (line is! Line) {
    return false;
  }
  return line.style.attributes[Attribute.blockQuote.key]?.value == true ||
      line.parent is Block &&
          (line.parent as Block)
                  .style
                  .attributes[Attribute.blockQuote.key]
                  ?.value ==
              true;
}

Object? _currentLineAlignment(QuillController controller) {
  final index = controller.selection.start
      .clamp(0, controller.document.length)
      .toInt();
  final query = controller.document.queryChild(index);
  final line = query.node;
  if (line is! Line) {
    return null;
  }
  return line.style.attributes[Attribute.align.key]?.value;
}

FocusNode _editorFocusNode(WidgetTester tester) {
  return tester.widget<QuillEditor>(find.byType(QuillEditor)).focusNode;
}

void _dispatchEditorTap(
  WidgetTester tester, {
  required QuillController controller,
  required int offset,
}) {
  final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
  TextPosition positionResolver(Offset _) => TextPosition(offset: offset);
  final details = TapDownDetails(
    globalPosition: Offset.zero,
    kind: PointerDeviceKind.touch,
  );
  expect(editor.config.onTapDown!(details, positionResolver), isFalse);
  expect(
    editor.config.onTapUp!(
      TapUpDetails(globalPosition: Offset.zero, kind: PointerDeviceKind.touch),
      positionResolver,
    ),
    isFalse,
  );
  controller.updateSelection(
    TextSelection.collapsed(offset: offset),
    ChangeSource.local,
  );
}

double _toolbarBottomGap(WidgetTester tester) {
  final scaffoldBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;
  final toolbarBottom = tester
      .getBottomLeft(find.byKey(const Key('test-quill-format-button')))
      .dy;
  return scaffoldBottom - toolbarBottom;
}

void _expectIconButtonIcon(
  WidgetTester tester,
  Key buttonKey,
  IconData expectedIcon,
) {
  final icon = tester.widget<Icon>(
    find
        .descendant(of: find.byKey(buttonKey), matching: find.byType(Icon))
        .first,
  );
  expect(icon.icon, expectedIcon);
}

void _expectSizeControlsStayOnOneLine(WidgetTester tester) {
  final firstTop = tester
      .getTopLeft(find.byKey(const Key('test-quill-format-size-1')))
      .dy;
  for (var size = 2; size <= 7; size += 1) {
    final top = tester
        .getTopLeft(find.byKey(Key('test-quill-format-size-$size')))
        .dy;
    expect(top, firstTop);
  }
}

void _expectClearStateOnFormatRow(WidgetTester tester) {
  final strikeCenter = tester.getCenter(
    find.byKey(const Key('test-quill-format-strike-toggle')),
  );
  final clearCenter = tester.getCenter(
    find.byKey(const Key('test-quill-format-clear-state-button')),
  );
  expect(clearCenter.dx, greaterThan(strikeCenter.dx));
  expect(clearCenter.dy, closeTo(strikeCenter.dy, 2));
}

Widget _buildEditor({
  QuillController? controller,
  ValueChanged<String>? onBbCodeChanged,
  ComposerImageInsertCallback? onImagePressed,
  List<ComposerImageAttachment> imageAttachments =
      const <ComposerImageAttachment>[],
  ForumAttachPreviewImageBuilder? attachImageBuilder,
  ForumAttachPreviewFileExists? attachFileExists,
  List<StickerItem> stickers = const <StickerItem>[],
  List<StickerGroup> stickerGroups = const <StickerGroup>[],
  String? initialStickerGroupId,
  ValueChanged<String>? onStickerGroupChanged,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  return ProviderScope(
    overrides: [
      imageCacheServiceProvider.overrideWithValue(_FailingImageCacheService()),
      composerStickerImageCacheLoaderProvider.overrideWithValue(
        ComposerStickerImageCacheLoader(
          imageCacheService: _FailingImageCacheService(),
          networkGap: Duration.zero,
          delay: (_) async {},
        ),
      ),
    ],
    child: LocalizedTestApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            viewInsets: viewInsets,
          ),
          child: ComposerQuillPrototypeEditor(
            keyPrefix: 'test-quill',
            controller: controller,
            onBbCodeChanged: onBbCodeChanged,
            onImagePressed: onImagePressed,
            imageAttachments: imageAttachments,
            attachImageBuilder: attachImageBuilder,
            attachFileExists: attachFileExists,
            stickers: stickers,
            stickerGroups: stickerGroups,
            initialStickerGroupId: initialStickerGroupId,
            onStickerGroupChanged: onStickerGroupChanged,
          ),
        ),
      ),
    ),
  );
}

ComposerImageAttachment _uploadedAttachment() {
  return ComposerImageAttachment(
    localId: 'local-123456',
    localPath: '/gallery/123456.png',
    fileName: '123456.png',
    mimeType: 'image/png',
    order: 0,
    status: ComposerImageAttachmentStatus.uploaded,
    aid: '123456',
    uploadedAt: DateTime.utc(2026, 7, 4),
  );
}

void _insertTestAttachment(
  QuillController controller,
  ComposerInsertionAnchor? anchor,
) {
  if (anchor == null) {
    return;
  }
  const codec = ComposerQuillBbCodeCodec();
  const insertionService = ComposerMessageInsertionService();
  const selectionAdapter = ComposerQuillSelectionAdapter();
  final source = codec.encodeDocument(controller.document);
  final sourceSelection = selectionAdapter.toSourceSelection(
    source: source,
    document: controller.document,
    selection: controller.selection,
  );
  if (sourceSelection == null) {
    return;
  }
  final mutation = insertionService.insertAttachmentBlock(
    source: source,
    selection: sourceSelection,
    attachmentCodes: const ['[attach]123456[/attach]'],
    revision: 1,
  );
  final document = codec.decodeDocument(mutation.nextSource);
  controller.document = document;
  final selection = selectionAdapter.toQuillSelection(
    source: mutation.nextSource,
    document: document,
    selection: mutation.resultSelection,
  );
  controller.updateSelection(
    selection ?? TextSelection.collapsed(offset: document.length - 1),
    ChangeSource.local,
  );
}

List<StickerGroup> _stickerGroups() {
  return [
    StickerGroup(id: 'bugcat', title: '貓貓蟲', stickers: [_sticker()]),
    StickerGroup(id: 'azukisan', title: '小豆泥', stickers: [_secondSticker()]),
  ];
}

StickerItem _sticker() {
  return _stickerWith(
    code: '{:9_656:}',
    imagePath: 'bugcat/Capoo16.gif',
    cacheKey: 'remote-smiley:bugcat/Capoo16.gif',
  );
}

StickerItem _secondSticker() {
  return _stickerWith(
    code: '{:6_1:}',
    imagePath: 'azukisan/1.gif',
    cacheKey: 'remote-smiley:azukisan/1.gif',
  );
}

StickerItem _stickerWith({
  required String code,
  required String imagePath,
  required String cacheKey,
}) {
  return StickerItem(
    code: code,
    rawCodePattern: code,
    imagePath: imagePath,
    imageUrl: 'https://bbs.yamibo.com/static/image/smiley/$imagePath',
    cacheKey: cacheKey,
  );
}

Widget _buildTestAttachPreviewImage(File file, Key key) {
  return _TestAttachPreviewImage(file: file, key: key);
}

bool _testAttachFileExists(File file) {
  return file.path.isNotEmpty && !file.path.contains('/missing/');
}

class _TestAttachPreviewImage extends StatelessWidget {
  const _TestAttachPreviewImage({super.key, required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 32, height: 32);
  }
}

class _FailingImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    return null;
  }

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async {
    return 0;
  }

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }
}
