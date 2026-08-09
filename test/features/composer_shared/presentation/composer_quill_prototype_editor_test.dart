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
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_selection_adapter.dart';
import 'package:y300/features/composer_shared/domain/services/composer_sticker_image_cache_loader.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_attachment_preview.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_source_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_image.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_toolbar_action.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_collapse_chrome.dart';
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

  testWidgets('collapse header toggles while only trailing icon edits', (
    tester,
  ) async {
    const source =
        '[collapse=0,外层]\n'
        '外层正文\n'
        '[collapse=0,内层]\n内层正文[/collapse]\n'
        '外层结尾[/collapse]';
    await tester.pumpWidget(_buildEditor(initialBbCode: source));

    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-collapse-collapse-1-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('test-quill-collapse-editor-page')),
      findsNothing,
    );
    await tester.tap(find.text('外层'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-collapse-collapse-1-content')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-collapse-1-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ForumCollapseChrome), findsNWidgets(2));
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('test-quill-collapse-editor-page')),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-collapse-collapse-1-content')),
      findsOneWidget,
    );
  });

  testWidgets('adjacent collapse cards get one scalable visual line gap', (
    tester,
  ) async {
    const source =
        '[collapse=0,第一]\n内容一[/collapse]\n'
        '[collapse=0,第二]\n内容二[/collapse]\n'
        '[collapse=0,第三]\n内容三[/collapse]';
    const firstGap = Key('composer-quill-collapse-gap-after-collapse-0');
    const secondGap = Key('composer-quill-collapse-gap-after-collapse-1');
    const trailingGap = Key('composer-quill-collapse-gap-after-collapse-2');

    await tester.pumpWidget(_buildEditor(initialBbCode: source, textScale: 1));

    expect(find.byKey(firstGap), findsOneWidget);
    expect(find.byKey(secondGap), findsOneWidget);
    expect(find.byKey(trailingGap), findsNothing);
    final normalHeight = tester.getSize(find.byKey(firstGap)).height;
    expect(normalHeight, greaterThan(0));
    expect(tester.getSize(find.byKey(secondGap)).height, normalHeight);

    await tester.pumpWidget(
      _buildEditor(initialBbCode: source, textScale: 1.5),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byKey(firstGap)).height,
      greaterThan(normalHeight),
    );
  });

  testWidgets('existing blank or text suppresses synthetic collapse gap', (
    tester,
  ) async {
    const gap = Key('composer-quill-collapse-gap-after-collapse-0');
    await tester.pumpWidget(
      _buildEditor(
        initialBbCode:
            '[collapse=0,第一]\n内容一[/collapse]\n\n'
            '[collapse=0,第二]\n内容二[/collapse]',
      ),
    );
    expect(find.byKey(gap), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      _buildEditor(
        initialBbCode:
            '[collapse=0,第一]\n内容一[/collapse]\n'
            '间隔正文\n'
            '[collapse=0,第二]\n内容二[/collapse]',
      ),
    );
    expect(find.byKey(gap), findsNothing);
  });

  testWidgets('surface strips formatting applied to an atomic collapse', (
    tester,
  ) async {
    const codec = ComposerQuillBbCodeCodec();
    const source = '[collapse=0,标题]\n[b]内部[/b][/collapse]';
    final document = codec.decodeDocument(source);
    const selection = TextSelection(baseOffset: 0, extentOffset: 1);
    final controller = QuillController(
      document: document,
      selection: selection,
    );
    addTearDown(controller.dispose);
    String? latest;
    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
      ),
    );

    controller.formatText(0, 1, Attribute.bold);
    controller.formatText(1, 1, Attribute.blockQuote);
    await tester.pump();

    final operations = controller.document.toDelta().toList();
    final collapseIndex = operations.indexWhere(
      (operation) => composerQuillCollapseEmbedPayload(operation.data) != null,
    );
    expect(operations[collapseIndex].attributes, isNull);
    expect(operations[collapseIndex + 1].data, '\n');
    expect(operations[collapseIndex + 1].attributes, isNull);
    expect(controller.selection, selection);
    expect(codec.encodeDocument(controller.document), source);
    expect(latest, isNull);
  });

  testWidgets('collapse title and save action match composer chrome', (
    tester,
  ) async {
    const initial = '[collapse=0,标题]\n正文[/collapse]';
    final theme = AppTheme.light();
    await tester.pumpWidget(_buildEditor(initialBbCode: initial));
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-0')),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.byKey(
      const Key('test-quill-collapse-editor-title-field'),
    );
    final titleField = tester.widget<TextField>(titleFinder);
    final decoration = titleField.decoration!;
    final localizations = AppLocalizations.of(tester.element(titleFinder));
    expect(decoration.hintText, localizations.composerCollapseTitleHint);
    expect(decoration.labelText, isNull);
    expect(decoration.filled, isFalse);
    expect(decoration.border, isA<UnderlineInputBorder>());
    expect(decoration.enabledBorder, isA<UnderlineInputBorder>());
    expect(decoration.focusedBorder, isA<UnderlineInputBorder>());
    expect(decoration.border, isNot(isA<OutlineInputBorder>()));
    final contentColumn = tester.widget<Column>(
      find.byKey(const Key('test-quill-collapse-editor-content-column')),
    );
    expect(contentColumn.children.whereType<Divider>(), isEmpty);

    final titlePadding = tester.widget<Padding>(
      find.byKey(const Key('test-quill-collapse-editor-title-padding')),
    );
    final resolvedPadding = titlePadding.padding.resolve(TextDirection.ltr);
    expect(
      resolvedPadding,
      const EdgeInsets.fromLTRB(
        ForumContentSpacing.composerPageHorizontal,
        ForumContentSpacing.composerPageVertical,
        ForumContentSpacing.composerPageHorizontal,
        12,
      ),
    );

    final saveFinder = find.byKey(
      const Key('test-quill-collapse-editor-save-button'),
    );
    var saveButton = tester.widget<IconButton>(saveFinder);
    final appBarForeground = theme.appBarTheme.foregroundColor!;
    expect(saveButton.tooltip, localizations.commonSave);
    expect(saveButton.onPressed, isNull);
    expect(
      saveButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      appBarForeground,
    );
    expect(
      saveButton.style?.foregroundColor?.resolve(<WidgetState>{
        WidgetState.disabled,
      }),
      appBarForeground.withValues(alpha: 0.38),
    );
    expect(
      find.descendant(
        of: saveFinder,
        matching: find.byIcon(Icons.save_outlined),
      ),
      findsOneWidget,
    );

    await tester.enterText(titleFinder, '新]题\n\uFFFC');
    await tester.pump();
    expect(tester.widget<TextField>(titleFinder).controller!.text, '新题');
    saveButton = tester.widget<IconButton>(saveFinder);
    expect(saveButton.onPressed, isNotNull);

    await tester.enterText(titleFinder, '标题');
    await tester.pump();
    saveButton = tester.widget<IconButton>(saveFinder);
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('creating then discarding a collapse leaves parent unchanged', (
    tester,
  ) async {
    String? latest;
    await tester.pumpWidget(
      _buildEditor(
        initialBbCode: '父正文',
        onBbCodeChanged: (value) => latest = value,
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-collapse-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('test-quill-collapse-editor-page')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('test-quill-collapse-editor-save-button')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.enterText(
      find.byKey(const Key('test-quill-collapse-editor-title-field')),
      '未保存标题',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const Key('test-quill-collapse-editor-discard-confirm-button'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const Key('test-quill-collapse-editor-discard-confirm-button'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('test-quill-collapse-editor-page')),
      findsNothing,
    );
    expect(latest, isNull);
  });

  testWidgets('safe text selection is prefilled and saved as one collapse', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(
      0,
      0,
      '选中的正文',
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    String? latest;
    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-collapse-button')));
    await tester.pumpAndSettle();
    final bodyEditor = tester.widget<QuillEditor>(
      find.byKey(const Key('test-quill-collapse-editor-body-editor')),
    );
    expect(
      const ComposerQuillBbCodeCodec().encodeDocument(
        bodyEditor.controller.document,
      ),
      '选中的正文',
    );
    await tester.enterText(
      find.byKey(const Key('test-quill-collapse-editor-title-field')),
      '标题',
    );
    await tester.tap(
      find.byKey(const Key('test-quill-collapse-editor-save-button')),
    );
    await tester.pumpAndSettle();

    expect(latest, '[collapse=0,标题]\n选中的正文[/collapse]');
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('selection containing an embed is preserved when creating', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(0, 0, 'A', const TextSelection.collapsed(offset: 1));
    controller.replaceText(
      1,
      0,
      composerQuillStickerEmbed('{:9_656:}'),
      const TextSelection.collapsed(offset: 2),
    );
    controller.replaceText(
      2,
      0,
      'B',
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    String? latest;
    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onBbCodeChanged: (value) => latest = value,
      ),
    );

    await tester.tap(find.byKey(const Key('test-quill-collapse-button')));
    await tester.pumpAndSettle();
    final bodyEditor = tester.widget<QuillEditor>(
      find.byKey(const Key('test-quill-collapse-editor-body-editor')),
    );
    expect(
      const ComposerQuillBbCodeCodec().encodeDocument(
        bodyEditor.controller.document,
      ),
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('test-quill-collapse-editor-title-field')),
      '空正文',
    );
    await tester.tap(
      find.byKey(const Key('test-quill-collapse-editor-save-button')),
    );
    await tester.pumpAndSettle();

    expect(latest, '[collapse=0,空正文]\n[/collapse]\nA{:9_656:}B');
  });

  testWidgets(
    'editing deletes title and body text but preserves nested BBCode',
    (tester) async {
      const initial =
          '[collapse=0,外层]\n'
          '嵌套1\n'
          '[collapse=0,内层]\n内层正文[/collapse][/collapse]';
      var latest = initial;
      await tester.pumpWidget(
        _buildEditor(
          initialBbCode: initial,
          onBbCodeChanged: (value) => latest = value,
        ),
      );

      await tester.tap(
        find.byKey(const Key('composer-quill-collapse-edit-collapse-1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const Key('test-quill-collapse-editor-body-collapse-button'),
        ),
        findsOneWidget,
      );
      expect(find.byType(QuillEditor), findsOneWidget);
      final titleField = tester.widget<TextField>(
        find.byKey(const Key('test-quill-collapse-editor-title-field')),
      );
      expect(titleField.enableInteractiveSelection, isTrue);
      await tester.enterText(
        find.byKey(const Key('test-quill-collapse-editor-title-field')),
        '',
      );
      final bodyEditor = tester.widget<QuillEditor>(
        find.byKey(const Key('test-quill-collapse-editor-body-editor')),
      );
      expect(bodyEditor.config.enableInteractiveSelection, isTrue);
      bodyEditor.controller.replaceText(
        2,
        1,
        '',
        const TextSelection.collapsed(offset: 2),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('test-quill-collapse-editor-save-button')),
      );
      await tester.pumpAndSettle();

      expect(
        latest,
        '[collapse=0,]\n'
        '嵌套\n'
        '[collapse=0,内层]\n内层正文[/collapse][/collapse]',
      );
    },
  );

  testWidgets('second-level collapse save stays local until outer save', (
    tester,
  ) async {
    const initial = '[collapse=0,外层]\n外层正文[/collapse]';
    var latest = initial;
    await tester.pumpWidget(
      _buildEditor(
        initialBbCode: initial,
        onBbCodeChanged: (value) => latest = value,
      ),
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-0')),
    );
    await tester.pumpAndSettle();

    await _createSecondLevelCollapse(tester);

    expect(latest, initial);
    expect(
      find.byKey(const Key('test-quill-collapse-editor-page')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('test-quill-collapse-editor-save-button')),
    );
    await tester.pumpAndSettle();

    expect(
      latest,
      '[collapse=0,外层]\n'
      '外层正文\n'
      '[collapse=0,内层]\n内层正文[/collapse][/collapse]',
    );
  });

  testWidgets('discarding outer editor drops saved nested draft', (
    tester,
  ) async {
    const initial = '[collapse=0,外层]\n外层正文[/collapse]';
    var latest = initial;
    await tester.pumpWidget(
      _buildEditor(
        initialBbCode: initial,
        onBbCodeChanged: (value) => latest = value,
      ),
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-0')),
    );
    await tester.pumpAndSettle();

    await _createSecondLevelCollapse(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('test-quill-collapse-editor-discard-confirm-button'),
      ),
    );
    await tester.pumpAndSettle();

    expect(latest, initial);
    expect(
      find.byKey(const Key('test-quill-collapse-editor-page')),
      findsNothing,
    );
  });

  testWidgets('second-level editor keeps deeper history preview-only', (
    tester,
  ) async {
    const initial =
        '[collapse=0,第一层]\n'
        '第一层正文\n'
        '[collapse=0,第二层]\n'
        '第二层正文\n'
        '[collapse=0,第三层]\n第三层正文[/collapse]\n'
        '[/collapse]\n'
        '[/collapse]';
    await tester.pumpWidget(_buildEditor(initialBbCode: initial));
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-2')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('test-quill-collapse-editor-body-collapse-button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const Key(
          'test-quill-collapse-editor-body-collapse-editor-body-collapse-button',
        ),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-0')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('composer-quill-collapse-collapse-0-toggle')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-collapse-0-toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-collapse-collapse-0-content')),
      findsOneWidget,
    );
    expect(find.textContaining('第三层正文', findRichText: true), findsOneWidget);
  });

  testWidgets('collapse title and body can both be deleted to empty', (
    tester,
  ) async {
    var latest = '[collapse=0,标题]\n正文[/collapse]';
    await tester.pumpWidget(
      _buildEditor(
        initialBbCode: latest,
        onBbCodeChanged: (value) => latest = value,
      ),
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-0')),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.byKey(
      const Key('test-quill-collapse-editor-title-field'),
    );
    final titleController = tester.widget<TextField>(titleFinder).controller!;
    await tester.enterText(titleFinder, '');
    await tester.pump();
    expect(
      tester.widget<TextField>(titleFinder).controller,
      same(titleController),
    );
    final bodyFinder = find.byKey(
      const Key('test-quill-collapse-editor-body-editor'),
    );
    final bodyController = tester.widget<QuillEditor>(bodyFinder).controller;
    bodyController.replaceText(
      0,
      2,
      '',
      const TextSelection.collapsed(offset: 0),
    );
    await tester.pump();
    expect(
      tester.widget<QuillEditor>(bodyFinder).controller,
      same(bodyController),
    );
    expect(bodyController.document.toPlainText(), '\n');

    await tester.tap(
      find.byKey(const Key('test-quill-collapse-editor-save-button')),
    );
    await tester.pumpAndSettle();
    expect(latest, '[collapse=0,]\n[/collapse]');
  });

  testWidgets('delete confirmation removes one atomic collapse', (
    tester,
  ) async {
    var latest = '[collapse=0,标题]\n正文[/collapse]';
    await tester.pumpWidget(
      _buildEditor(
        initialBbCode: latest,
        onBbCodeChanged: (value) => latest = value,
      ),
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-0')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('test-quill-collapse-editor-delete-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('test-quill-collapse-editor-delete-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(latest, isEmpty);
    expect(
      find.byKey(const Key('test-quill-collapse-editor-page')),
      findsNothing,
    );
  });

  testWidgets('upload bridge blocks collapse save delete and route exit', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildEditor(
        initialBbCode: '[collapse=0,标题]\n正文[/collapse]',
        isUploadingImages: true,
        imageUploadCurrent: 1,
        imageUploadTotal: 2,
      ),
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-0')),
    );
    await tester.pumpAndSettle();

    final saveButton = tester.widget<IconButton>(
      find.byKey(const Key('test-quill-collapse-editor-save-button')),
    );
    final deleteButton = tester.widget<IconButton>(
      find.byKey(const Key('test-quill-collapse-editor-delete-button')),
    );
    expect(saveButton.onPressed, isNull);
    expect(deleteButton.onPressed, isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    expect(
      find.byKey(const Key('test-quill-collapse-editor-page')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('collapse image insertion stays local until save', (
    tester,
  ) async {
    const initial = '[collapse=0,标题]\n正文[/collapse]';
    const codec = ComposerQuillBbCodeCodec();
    final document = codec.decodeDocument(initial);
    final rootController = QuillController(
      document: document,
      selection: TextSelection.collapsed(offset: document.length - 1),
    );
    addTearDown(rootController.dispose);
    var latest = initial;
    await tester.pumpWidget(
      _buildEditor(
        controller: rootController,
        onBbCodeChanged: (value) => latest = value,
        onImagePressed: (anchor) async {
          _insertTestAttachment(rootController, anchor);
        },
        imageAttachments: [_uploadedAttachment()],
        attachImageBuilder: _buildTestAttachPreviewImage,
        attachFileExists: _testAttachFileExists,
      ),
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-0')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('test-quill-collapse-editor-body-image-button')),
    );
    await tester.pumpAndSettle();

    expect(latest, initial);
    final bodyEditor = tester.widget<QuillEditor>(
      find.byKey(const Key('test-quill-collapse-editor-body-editor')),
    );
    expect(
      codec.encodeDocument(bodyEditor.controller.document),
      '正文\n[attach]123456[/attach]',
    );

    await tester.tap(
      find.byKey(const Key('test-quill-collapse-editor-save-button')),
    );
    await tester.pumpAndSettle();

    expect(latest, '[collapse=0,标题]\n正文\n[attach]123456[/attach]\n[/collapse]');
  });

  testWidgets('external parent replacement keeps conflicting editor open', (
    tester,
  ) async {
    final key = GlobalKey<_ControlledCollapseHarnessState>();
    await tester.pumpWidget(
      _buildControlledCollapseEditor(
        key: key,
        initialBbCode: '[collapse=0,标题]\n正文[/collapse]',
      ),
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-collapse-edit-collapse-0')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('conflict-quill-collapse-editor-title-field')),
      '本地标题',
    );

    key.currentState!.replaceExternally('外部替换');
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('conflict-quill-collapse-editor-save-button')),
    );
    await tester.pumpAndSettle();

    expect(key.currentState!.source, '外部替换');
    expect(
      find.byKey(const Key('conflict-quill-collapse-editor-page')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsOneWidget);
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

  testWidgets('custom actions share the embedded Quill tool panel', (
    tester,
  ) async {
    final action = ComposerToolbarAction.panel(
      key: const Key('test-quill-custom-panel-button'),
      icon: Icons.collections_outlined,
      tooltip: 'custom panel',
      panelBuilder: (_) =>
          const SizedBox.expand(key: Key('test-quill-custom-panel-content')),
    );
    await tester.pumpWidget(_buildEditor(extraToolbarActions: [action]));

    await tester.tap(find.byKey(const Key('test-quill-custom-panel-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test-quill-tool-panel')), findsOneWidget);
    expect(
      find.byKey(const Key('test-quill-custom-panel-content')),
      findsOneWidget,
    );
    expect(_toolbarBottomGap(tester), greaterThan(200));

    final updatedAction = ComposerToolbarAction.panel(
      key: const Key('test-quill-custom-panel-button'),
      icon: Icons.collections_outlined,
      tooltip: 'custom panel',
      panelBuilder: (_) =>
          const SizedBox.expand(key: Key('test-quill-updated-panel-content')),
    );
    await tester.pumpWidget(_buildEditor(extraToolbarActions: [updatedAction]));
    await tester.pump();
    expect(
      find.byKey(const Key('test-quill-updated-panel-content')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('test-quill-format-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('test-quill-updated-panel-content')),
      findsNothing,
    );
    expect(find.byKey(const Key('test-quill-format-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('test-quill-custom-panel-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-quill-format-sheet')), findsNothing);
    expect(
      find.byKey(const Key('test-quill-updated-panel-content')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('test-quill-custom-panel-button')));
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

  testWidgets(
    'attachment preview follows the Quill body width without stretching small images',
    (tester) async {
      const narrowSurfaceWidth = 420.0;
      const wideSurfaceWidth = 620.0;
      final controller = QuillController.basic();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _buildEditor(
          controller: controller,
          surfaceWidth: narrowSurfaceWidth,
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

      var preview = tester.widget<ComposerAttachmentPreviewImage>(
        find.byKey(const Key('composer-quill-attach-preview-123456')),
      );
      expect(
        preview.maxWidth,
        closeTo(_expectedAttachmentMaxWidth(narrowSurfaceWidth), 0.001),
      );
      expect(preview.maxWidth, isNot(320));
      expect(
        tester.getSize(
          find.byKey(const Key('composer-quill-attach-image-123456')),
        ),
        const Size(32, 32),
      );

      await tester.pumpWidget(
        _buildEditor(
          controller: controller,
          surfaceWidth: wideSurfaceWidth,
          imageAttachments: [_uploadedAttachment()],
          attachImageBuilder: _buildTestAttachPreviewImage,
          attachFileExists: _testAttachFileExists,
        ),
      );
      await tester.pumpAndSettle();

      preview = tester.widget<ComposerAttachmentPreviewImage>(
        find.byKey(const Key('composer-quill-attach-preview-123456')),
      );
      expect(
        preview.maxWidth,
        closeTo(_expectedAttachmentMaxWidth(wideSurfaceWidth), 0.001),
      );
      expect(
        tester.getSize(
          find.byKey(const Key('composer-quill-attach-image-123456')),
        ),
        const Size(32, 32),
      );
    },
  );

  testWidgets('oversized attachment is constrained to the Quill body width', (
    tester,
  ) async {
    const surfaceWidth = 420.0;
    final controller = QuillController.basic();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        surfaceWidth: surfaceWidth,
        imageAttachments: [_uploadedAttachment()],
        attachImageBuilder: _buildWideTestAttachPreviewImage,
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

    final imageSize = tester.getSize(
      find.byKey(const Key('composer-quill-attach-image-123456')),
    );
    expect(
      imageSize.width,
      closeTo(_expectedAttachmentMaxWidth(surfaceWidth), 0.001),
    );
    expect(imageSize.height, closeTo(imageSize.width / 2, 0.001));
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

Future<void> _createSecondLevelCollapse(WidgetTester tester) async {
  const firstBodyCollapseButton = Key(
    'test-quill-collapse-editor-body-collapse-button',
  );
  const secondPagePrefix = 'test-quill-collapse-editor-body-collapse-editor';
  expect(find.byKey(firstBodyCollapseButton), findsOneWidget);
  await tester.tap(find.byKey(firstBodyCollapseButton));
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('$secondPagePrefix-page')), findsOneWidget);
  expect(
    find.byKey(const Key('$secondPagePrefix-body-collapse-button')),
    findsNothing,
  );
  await tester.enterText(
    find.byKey(const Key('$secondPagePrefix-title-field')),
    '内层',
  );
  const nestedBody = '内层正文';
  final bodyEditor = tester.widget<QuillEditor>(
    find.byKey(const Key('$secondPagePrefix-body-editor')),
  );
  bodyEditor.controller.replaceText(
    0,
    0,
    nestedBody,
    const TextSelection.collapsed(offset: nestedBody.length),
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('$secondPagePrefix-save-button')));
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('$secondPagePrefix-page')), findsNothing);
}

Widget _buildEditor({
  QuillController? controller,
  String? initialBbCode,
  ValueChanged<String>? onBbCodeChanged,
  ComposerImageInsertCallback? onImagePressed,
  List<ComposerImageAttachment> imageAttachments =
      const <ComposerImageAttachment>[],
  ForumAttachPreviewImageBuilder? attachImageBuilder,
  ForumAttachPreviewFileExists? attachFileExists,
  List<StickerItem> stickers = const <StickerItem>[],
  List<StickerGroup> stickerGroups = const <StickerGroup>[],
  List<ComposerToolbarAction> extraToolbarActions =
      const <ComposerToolbarAction>[],
  String? initialStickerGroupId,
  ValueChanged<String>? onStickerGroupChanged,
  bool isUploadingImages = false,
  int imageUploadCurrent = 0,
  int imageUploadTotal = 0,
  EdgeInsets viewInsets = EdgeInsets.zero,
  double? surfaceWidth,
  double textScale = 1,
}) {
  final editor = ComposerQuillPrototypeEditor(
    keyPrefix: 'test-quill',
    controller: controller,
    initialBbCode: initialBbCode,
    onBbCodeChanged: onBbCodeChanged,
    onImagePressed: onImagePressed,
    imageAttachments: imageAttachments,
    attachImageBuilder: attachImageBuilder,
    attachFileExists: attachFileExists,
    stickers: stickers,
    stickerGroups: stickerGroups,
    extraToolbarActions: extraToolbarActions,
    initialStickerGroupId: initialStickerGroupId,
    onStickerGroupChanged: onStickerGroupChanged,
    isUploadingImages: isUploadingImages,
    imageUploadCurrent: imageUploadCurrent,
    imageUploadTotal: imageUploadTotal,
  );
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
            textScaler: TextScaler.linear(textScale),
          ),
          child: surfaceWidth == null
              ? editor
              : Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: surfaceWidth,
                    height: 600,
                    child: editor,
                  ),
                ),
        ),
      ),
    ),
  );
}

Widget _buildControlledCollapseEditor({
  required GlobalKey<_ControlledCollapseHarnessState> key,
  required String initialBbCode,
}) {
  return LocalizedTestApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: _ControlledCollapseHarness(
          key: key,
          initialBbCode: initialBbCode,
        ),
      ),
    ),
  );
}

class _ControlledCollapseHarness extends StatefulWidget {
  const _ControlledCollapseHarness({super.key, required this.initialBbCode});

  final String initialBbCode;

  @override
  State<_ControlledCollapseHarness> createState() =>
      _ControlledCollapseHarnessState();
}

class _ControlledCollapseHarnessState
    extends State<_ControlledCollapseHarness> {
  late String source;
  int revision = 0;

  @override
  void initState() {
    super.initState();
    source = widget.initialBbCode;
  }

  void replaceExternally(String value) {
    setState(() {
      source = value;
      revision += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ComposerQuillEditorSurface(
      keyPrefix: 'conflict-quill',
      bbCode: source,
      messageRevision: revision,
      onBbCodeChanged: (value) {
        setState(() {
          source = value;
          revision += 1;
        });
      },
    );
  }
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
  final localInsertion = anchor.localAttachmentInsertion;
  if (localInsertion != null) {
    localInsertion(const ['[attach]123456[/attach]']);
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

Widget _buildWideTestAttachPreviewImage(File file, Key key) {
  return AspectRatio(key: key, aspectRatio: 2);
}

double _expectedAttachmentMaxWidth(double surfaceWidth) {
  return surfaceWidth -
      (ForumContentSpacing.composerQuillSurfaceHorizontal * 2) -
      (ForumContentSpacing.quillInnerHorizontal * 2) -
      4;
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
