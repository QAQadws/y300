import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/presentation/blog/blog_quill_html_codec.dart';
import 'package:y300/features/profile/presentation/blog/blog_rich_text_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    clipboard = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return clipboard == null ? null : {'text': clipboard};
      }
      return null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

  test('external text is literal and replaces the selected range', () async {
    final controller = _controller(Delta()..insert('前选择后\n'));
    controller.updateSelection(
      const TextSelection(baseOffset: 1, extentOffset: 3),
      ChangeSource.local,
    );
    clipboard = '<b>文字</b>\n下一行';
    expect(await pasteBlogText(controller, isCurrent: () => true), true);
    expect(controller.document.toPlainText(), '前<b>文字</b>\n下一行后\n');
    expect(controller.selection.baseOffset, 1 + clipboard!.length);
    expect(
      const BlogQuillHtmlCodec().encodeDocument(controller.document),
      contains('&lt;b&gt;'),
    );
  });

  test('internal copy keeps supported inline formats', () async {
    final source = _controller(
      Delta()
        ..insert('格式', {
          Attribute.bold.key: true,
          Attribute.underline.key: true,
          Attribute.size.key: '18',
        })
        ..insert('\n'),
    );
    await _copy(source, 0, 2);
    final target = _controller();
    await pasteBlogText(target, isCurrent: () => true);
    expect(target.document.toDelta(), source.document.toDelta());
    expect(target.selection.baseOffset, 2);
  });

  test('internal blog images and preserved HTML remain valid embeds', () async {
    final source = _controller(
      Delta()
        ..insert(blogQuillImageEmbed('https://example.com/image.jpg').toJson())
        ..insert({
          blogQuillHtmlEmbedType: '<table><tr><td>原文</td></tr></table>',
        })
        ..insert('\n'),
    );
    await _copy(source, 0, 2);
    final target = _controller();
    await pasteBlogText(target, isCurrent: () => true);
    expect(target.document.toDelta(), source.document.toDelta());
    expect(
      const BlogQuillHtmlCodec().encodeDocument(target.document),
      contains('<table>'),
    );
  });

  for (final embed in [
    {'image': 'https://example.com/forum.jpg'},
    {'attach': '42'},
    {'unknown': 'future payload'},
  ]) {
    test(
      'foreign ${embed.keys.single} embed falls back to text without importing the embed',
      () async {
        final source = _controller(
          Delta()
            ..insert('前')
            ..insert(embed)
            ..insert('后\n'),
        );
        await _copy(source, 0, 3);
        final target = _controller();
        await pasteBlogText(target, isCurrent: () => true);
        expect(target.document.toPlainText(), '前后\n');
        expect(
          target.document.toDelta().toList().every(
            (operation) => operation.data is String,
          ),
          true,
        );
      },
    );
  }

  test('unsupported forum formatting falls back to plain text', () async {
    final source = _controller(
      Delta()
        ..insert('背景', {Attribute.background.key: '#ff0000'})
        ..insert('\n'),
    );
    await _copy(source, 0, 2);
    final target = _controller();
    await pasteBlogText(target, isCurrent: () => true);
    expect(target.document.toPlainText(), '背景\n');
    expect(target.document.toDelta().first.attributes, isNull);
  });

  test(
    'a changed system clipboard does not reuse stale internal formatting',
    () async {
      final source = _controller(
        Delta()
          ..insert('旧', {Attribute.bold.key: true})
          ..insert('\n'),
      );
      await _copy(source, 0, 1);
      clipboard = '新';
      final target = _controller();
      await pasteBlogText(target, isCurrent: () => true);
      expect(target.document.toPlainText(), '新\n');
      expect(target.document.toDelta().first.attributes, isNull);
    },
  );

  test(
    'missing clipboard text consumes paste without falling back to image paste',
    () async {
      final target = _controller();
      expect(await pasteBlogText(target, isCurrent: () => true), true);
      expect(target.document.toPlainText(), '\n');
    },
  );

  for (final change in ['session', 'readOnly', 'document', 'selection']) {
    test('late clipboard response is ignored after $change changes', () async {
      final target = _controller(Delta()..insert('正文\n'));
      final response = Completer<Object?>();
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) => response.future,
      );
      var current = true;
      final pending = pasteBlogText(target, isCurrent: () => current);
      switch (change) {
        case 'session':
          current = false;
        case 'readOnly':
          target.readOnly = true;
        case 'document':
          target.document = Document()..insert(0, '新正文');
        case 'selection':
          target.updateSelection(
            const TextSelection.collapsed(offset: 2),
            ChangeSource.local,
          );
      }
      final unchanged = target.document.toDelta();
      response.complete({'text': '迟到内容'});
      expect(await pending, true);
      expect(target.document.toDelta(), unchanged);
    });
  }

  test(
    'clipboard platform errors are consumed without mutating the document',
    () async {
      final target = _controller();
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      expect(await pasteBlogText(target, isCurrent: () => true), true);
      expect(target.document.toPlainText(), '\n');
    },
  );
}

QuillController _controller([Delta? delta]) {
  final controller = QuillController(
    document: delta == null ? Document() : Document.fromDelta(delta),
    selection: const TextSelection.collapsed(offset: 0),
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _copy(QuillController controller, int start, int end) async {
  controller.updateSelection(
    TextSelection(baseOffset: start, extentOffset: end),
    ChangeSource.local,
  );
  // Exercise the same Quill clipboard hook used by the editor's copy menu.
  // ignore: experimental_member_use
  expect(controller.clipboardSelection(true), true);
  await Clipboard.setData(ClipboardData(text: controller.pastePlainText));
}
