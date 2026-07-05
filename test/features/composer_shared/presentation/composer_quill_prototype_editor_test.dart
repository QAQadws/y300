import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_sticker_image_cache_loader.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_image.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_editor.dart';

void main() {
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
      '16',
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
      '16',
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
      '14',
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
        onImagePressed: (_) async => _uploadedAttachment(),
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

    expect(latest, '{:9_656:}[attach]123456[/attach]');
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
        onImagePressed: (_) async => _uploadedAttachment(),
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

    expect(latest, '[attach]123456[/attach]后续');
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

Widget _buildEditor({
  QuillController? controller,
  ValueChanged<String>? onBbCodeChanged,
  ComposerQuillImagePicker? onImagePressed,
  ForumAttachPreviewImageBuilder? attachImageBuilder,
  ForumAttachPreviewFileExists? attachFileExists,
  List<StickerItem> stickers = const <StickerItem>[],
  List<StickerGroup> stickerGroups = const <StickerGroup>[],
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
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
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
            attachImageBuilder: attachImageBuilder,
            attachFileExists: attachFileExists,
            stickers: stickers,
            stickerGroups: stickerGroups,
          ),
        ),
      ),
    ),
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
