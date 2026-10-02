import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/repositories/sticker_picker_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_sticker_image_cache_loader.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_input.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('plain input and unknown codes do not load the sticker catalog', (
    tester,
  ) async {
    final value = ValueNotifier('hello {:9_656:}');
    addTearDown(value.dispose);
    var loads = 0;
    await tester.pumpWidget(
      _app(
        value,
        loadGroups: () async {
          loads += 1;
          return _groups;
        },
      ),
    );
    await tester.pump();
    expect(loads, 0);
    expect(
      _editor(tester).controller.document.toPlainText(),
      '${value.value}\n',
    );
    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byKey(const Key('message-sticker-button')), findsOneWidget);
  });

  testWidgets('parent echoes preserve the document during IME composition', (
    tester,
  ) async {
    final value = ValueNotifier('');
    addTearDown(value.dispose);
    await tester.pumpWidget(_app(value));
    final editor = _editor(tester);
    final document = editor.controller.document;
    editor.focusNode.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '拼音\n',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(value.value, '拼音');
    expect(identical(_editor(tester).controller.document, document), isTrue);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '拼音输入\n\n',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(value.value, '拼音输入\n');
  });

  testWidgets('picker replaces the selection with a visible atomic sticker', (
    tester,
  ) async {
    final value = ValueNotifier('前替换后');
    addTearDown(value.dispose);
    await tester.pumpWidget(_app(value));
    final controller = _editor(tester).controller;
    controller.updateSelection(
      const TextSelection(baseOffset: 1, extentOffset: 3),
      ChangeSource.local,
    );
    await _pickSticker(tester);
    expect(value.value, '前${_sticker.code}后');
    expect(controller.selection.baseOffset, 2);
    final frame = find.byKey(
      Key('composer-quill-sticker-frame-${_sticker.code}'),
    );
    expect(frame, findsOneWidget);
    expect(tester.getSize(frame).width, tester.getSize(frame).height);
    controller.undo();
    await tester.pump();
    expect(value.value, '前替换后');
    controller.redo();
    await tester.pump();
    expect(value.value, '前${_sticker.code}后');
    controller.updateSelection(
      const TextSelection.collapsed(offset: 2),
      ChangeSource.local,
    );
    _editor(tester).focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(value.value, '前后');
  });

  testWidgets(
    'copy and paste use sticker codes without leaking other Quill styles',
    (tester) async {
      var clipboard = '';
      _mockClipboard((call) async {
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      final value = ValueNotifier('');
      addTearDown(value.dispose);
      await tester.pumpWidget(_app(value));
      await _pickSticker(tester);
      final controller = _editor(tester).controller;
      controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 1),
        ChangeSource.local,
      );
      _copy(controller);
      await tester.pump();
      expect(clipboard, _sticker.code);
      controller.updateSelection(
        const TextSelection.collapsed(offset: 1),
        ChangeSource.local,
      );
      await _paste(controller);
      await tester.pump();
      expect(value.value, '${_sticker.code}${_sticker.code}');
      expect(
        controller.document
            .toDelta()
            .toList()
            .where((op) => op.data is! String)
            .fold<int>(0, (count, op) => count + op.length!),
        2,
      );

      final other = QuillController(
        document: Document.fromDelta(
          Delta()
            ..insert('styled', {'bold': true})
            ..insert('\n'),
        ),
        selection: const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      addTearDown(other.dispose);
      _copy(other);
      await tester.pump();
      value.value = '';
      await tester.pump();
      await _paste(controller);
      await tester.pump();
      expect(value.value, 'styled');
      expect(controller.selection.baseOffset, 6);
      expect(
        controller.document.toDelta().toList().every(
          (op) => op.attributes?.isEmpty ?? true,
        ),
        isTrue,
      );
    },
  );

  testWidgets('bounds long text to five lines and a shorter parent viewport', (
    tester,
  ) async {
    final value = ValueNotifier('one');
    addTearDown(value.dispose);
    await tester.pumpWidget(_app(value));
    final shortHeight = tester
        .getSize(find.byKey(const Key('message-input')))
        .height;
    value.value = List.filled(20, 'line').join('\n');
    await tester.pump();
    final longHeight = tester
        .getSize(find.byKey(const Key('message-input')))
        .height;
    expect(longHeight, greaterThan(shortHeight));
    expect(longHeight, lessThanOrEqualTo(shortHeight * 5 + 1));
    expect(
      _editor(tester).scrollController.position.maxScrollExtent,
      greaterThan(0),
    );
    await tester.pumpWidget(_app(value, maxHeight: 80, textScale: 1.8));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(ComposerStickerInput)).height,
      lessThanOrEqualTo(80),
    );
  });

  testWidgets(
    'formatting shortcuts and non-sticker insertion are unavailable',
    (tester) async {
      final value = ValueNotifier('plain');
      addTearDown(value.dispose);
      await tester.pumpWidget(_app(value));
      final editor = _editor(tester);
      editor.focusNode.requestFocus();
      editor.controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
        ChangeSource.local,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(editor.controller.getSelectionStyle().attributes, isEmpty);
      editor.controller.replaceText(
        0,
        5,
        composerQuillAttachEmbed('123'),
        const TextSelection.collapsed(offset: 1),
      );
      expect(value.value, 'plain');
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets('clearing externally rejects a late picker selection', (
    tester,
  ) async {
    final value = ValueNotifier('draft');
    addTearDown(value.dispose);
    await tester.pumpWidget(_app(value));
    await tester.tap(find.byKey(const Key('message-sticker-button')));
    await tester.pumpAndSettle();
    value.value = '';
    await tester.pump();
    await tester.tap(find.byKey(Key('reply-sticker-item-${_sticker.code}')));
    await tester.pumpAndSettle();
    expect(value.value, '');
    expect(_editor(tester).controller.document.toPlainText(), '\n');
  });

  testWidgets('disabled input ignores a picker result and clipboard paste', (
    tester,
  ) async {
    final value = ValueNotifier('draft');
    final enabled = ValueNotifier(true);
    addTearDown(value.dispose);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(_app(value, enabled: enabled));
    await tester.tap(find.byKey(const Key('message-sticker-button')));
    await tester.pumpAndSettle();
    enabled.value = false;
    await tester.pump();
    await tester.tap(find.byKey(Key('reply-sticker-item-${_sticker.code}')));
    await tester.pumpAndSettle();
    expect(value.value, 'draft');
    expect(_editor(tester).controller.readOnly, isTrue);
    await _paste(_editor(tester).controller);
    expect(value.value, 'draft');
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('message-sticker-button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a picker result cannot update a disposed input', (tester) async {
    final value = ValueNotifier('draft');
    final visible = ValueNotifier(true);
    addTearDown(value.dispose);
    addTearDown(visible.dispose);
    await tester.pumpWidget(_app(value, visible: visible));
    await tester.tap(find.byKey(const Key('message-sticker-button')));
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pump();
    await tester.tap(find.byKey(Key('reply-sticker-item-${_sticker.code}')));
    await tester.pumpAndSettle();
    expect(value.value, 'draft');
    expect(find.byType(ComposerStickerInput), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'choosing a literal code updates its image without changing text',
    (tester) async {
      final value = ValueNotifier(_sticker.code);
      addTearDown(value.dispose);
      await tester.pumpWidget(_app(value));
      final editor = _editor(tester);
      // Keep focus stable to ensure the image lookup is updated by insertion,
      // rather than incidentally by a focus listener after closing the sheet.
      editor.focusNode.canRequestFocus = false;
      editor.controller.updateSelection(
        TextSelection(baseOffset: 0, extentOffset: _sticker.code.length),
        ChangeSource.local,
      );
      await _pickSticker(tester);
      expect(value.value, _sticker.code);
      expect(
        find.byKey(Key('composer-quill-sticker-${_sticker.code}')),
        findsOneWidget,
      );
      expect(editor.controller.document.toDelta().first.data, {
        'sticker': _sticker.code,
      });
    },
  );

  testWidgets('clipboard return cannot insert into an abandoned selection', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    _mockClipboard(
      (call) async =>
          call.method == 'Clipboard.getData' ? pending.future : null,
    );
    final value = ValueNotifier('draft');
    addTearDown(value.dispose);
    await tester.pumpWidget(_app(value));
    final controller = _editor(tester).controller;
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 2),
      ChangeSource.local,
    );
    final paste = _paste(controller);
    controller.updateSelection(
      const TextSelection.collapsed(offset: 5),
      ChangeSource.local,
    );
    pending.complete({'text': 'late'});
    await paste;
    await tester.pump();
    expect(value.value, 'draft');
    expect(controller.selection.baseOffset, 5);
  });

  testWidgets('picker return cannot replace an abandoned selection', (
    tester,
  ) async {
    final value = ValueNotifier('draft');
    addTearDown(value.dispose);
    await tester.pumpWidget(_app(value));
    final controller = _editor(tester).controller;
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 2),
      ChangeSource.local,
    );
    await tester.tap(find.byKey(const Key('message-sticker-button')));
    await tester.pumpAndSettle();
    controller.updateSelection(
      const TextSelection.collapsed(offset: 5),
      ChangeSource.local,
    );
    await tester.tap(find.byKey(Key('reply-sticker-item-${_sticker.code}')));
    await tester.pumpAndSettle();
    expect(value.value, 'draft');
    expect(controller.selection.baseOffset, 5);
  });

  testWidgets('external clear discards the sent document undo history', (
    tester,
  ) async {
    final value = ValueNotifier('');
    addTearDown(value.dispose);
    await tester.pumpWidget(_app(value));
    final controller = _editor(tester).controller;
    controller.replaceText(
      0,
      0,
      'sent',
      const TextSelection.collapsed(offset: 4),
    );
    await tester.pump();
    expect(controller.hasUndo, isTrue);
    final sentDocument = controller.document;
    value.value = '';
    await tester.pump();
    expect(identical(controller.document, sentDocument), isFalse);
    expect(controller.hasUndo, isFalse);
    expect(controller.hasRedo, isFalse);
    controller.undo();
    controller.redo();
    await tester.pump();
    expect(value.value, '');
    controller.replaceText(
      0,
      0,
      'fresh',
      const TextSelection.collapsed(offset: 5),
    );
    controller.undo();
    await tester.pump();
    expect(value.value, '');
    controller.redo();
    await tester.pump();
    expect(value.value, 'fresh');
  });

  testWidgets('AltGr character chords are not intercepted as formatting', (
    tester,
  ) async {
    final value = ValueNotifier('');
    addTearDown(value.dispose);
    await tester.pumpWidget(_app(value));
    final editor = _editor(tester);
    editor.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
    // Exercise the pinned Quill hook with the hardware modifier state used by AltGr.
    // ignore: experimental_member_use
    final handler = editor.config.onKeyPressed!;
    expect(
      handler(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyM,
          logicalKey: LogicalKeyboardKey.keyM,
          character: 'µ',
          timeStamp: Duration.zero,
        ),
        null,
      ),
      isNull,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  for (final dispose in [false, true]) {
    testWidgets(
      'late clipboard result is ignored after ${dispose ? 'disposal' : 'external replacement'}',
      (tester) async {
        final pending = Completer<Object?>();
        _mockClipboard(
          (call) async =>
              call.method == 'Clipboard.getData' ? pending.future : null,
        );
        final value = ValueNotifier('draft');
        addTearDown(value.dispose);
        await tester.pumpWidget(_app(value));
        final paste = _paste(_editor(tester).controller);
        if (dispose) {
          await tester.pumpWidget(const SizedBox());
        } else {
          value.value = 'new';
          await tester.pump();
        }
        pending.complete({'text': 'late'});
        await paste;
        await tester.pump();
        expect(value.value, dispose ? 'draft' : 'new');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

QuillEditor _editor(WidgetTester tester) =>
    tester.widget<QuillEditor>(find.byKey(const Key('message-input')));

// These tests deliberately exercise the pinned Quill 11.5.1 clipboard entry
// points, including its internal rich-copy cache shared between editors.
bool _copy(QuillController controller) {
  // ignore: experimental_member_use
  return controller.clipboardSelection(true);
}

Future<bool> _paste(QuillController controller) {
  // ignore: experimental_member_use
  return controller.clipboardPaste();
}

Future<void> _pickSticker(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('message-sticker-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('reply-sticker-item-${_sticker.code}')));
  await tester.pumpAndSettle();
}

void _mockClipboard(Future<Object?> Function(MethodCall) handler) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, handler);
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

Widget _app(
  ValueNotifier<String> value, {
  ValueNotifier<bool>? enabled,
  ValueNotifier<bool>? visible,
  Future<List<StickerGroup>> Function()? loadGroups,
  double maxHeight = 300,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      stickerGroupsProvider.overrideWith(
        (_) => (loadGroups ?? () async => _groups)(),
      ),
      stickerPickerPreferencesRepositoryProvider.overrideWithValue(
        _Preferences(),
      ),
      composerStickerImageCacheLoaderProvider.overrideWithValue(
        ComposerStickerImageCacheLoader(
          imageCacheService: _Images(),
          networkGap: Duration.zero,
        ),
      ),
    ],
    child: LocalizedTestApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 320, maxHeight: maxHeight),
              child: ListenableBuilder(
                listenable: Listenable.merge([value, ?enabled, ?visible]),
                builder: (context, _) => visible?.value == false
                    ? const SizedBox.shrink()
                    : ComposerStickerInput(
                        value: value.value,
                        onChanged: (next) => value.value = next,
                        enabled: enabled?.value ?? true,
                        hintText: 'input',
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _sticker = StickerItem(
  code: '{:9_656:}',
  rawCodePattern: '{:9_656:}',
  imagePath: 'bugcat/a.gif',
  imageUrl: 'https://bbs.yamibo.com/static/image/smiley/bugcat/a.gif',
  cacheKey: 'sticker-a',
);
const _groups = [
  StickerGroup(id: 'bugcat', title: '表情', stickers: [_sticker]),
];

class _Preferences implements StickerPickerPreferencesRepository {
  @override
  Future<String?> loadLastGroupId() async => null;
  @override
  Future<void> saveLastGroupId(String groupId) async {}
}

class _Images implements ImageCacheService {
  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async =>
      CachedImageResult.failed;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
