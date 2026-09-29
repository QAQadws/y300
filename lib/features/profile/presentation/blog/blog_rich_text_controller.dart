import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:y300/features/profile/presentation/blog/blog_quill_html_codec.dart';
import 'package:y300/features/profile/presentation/blog/blog_rich_text_clipboard.dart';

/// Keeps the server HTML exact until an actual document edit occurs.
final class BlogRichTextController {
  BlogRichTextController({required this.onChanged}) {
    // Keyboard replacement can bypass Quill's clipboard hook and reuse another
    // editor's static embed cache. Keep those nodes out of the HTML document.
    quill.onReplaceText = (_, _, data) => supportsBlogTextInsertion(data);
    _listen();
  }
  final ValueChanged<String> onChanged;
  late final QuillController quill = QuillController.basic(
    config: QuillControllerConfig(
      // Quill 11 exposes paste interception only through this experimental API.
      // ignore: experimental_member_use
      clipboardConfig: QuillClipboardConfig(
        // ignore: experimental_member_use
        onClipboardPaste: () {
          final current = generation;
          return pasteBlogText(
            quill,
            isCurrent: () => !_disposed && generation == current,
          );
        },
      ),
    ),
  );
  final focusNode = FocusNode();
  final scrollController = ScrollController();
  final _codec = const BlogQuillHtmlCodec();
  StreamSubscription<DocChange>? _changes;
  String _html = '';
  bool _disposed = false;
  int generation = 0;

  void load(String html) {
    if (_disposed || html == _html) return;
    ++generation;
    _html = html;
    _changes?.cancel();
    quill.document = _codec.decodeDocument(html);
    quill.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    _listen();
  }

  void _listen() {
    _changes = quill.document.changes.listen((_) {
      if (_disposed) return;
      final html = _codec.encodeDocument(quill.document);
      if (html == _html) return;
      _html = html;
      onChanged(html);
    });
  }

  void insertImage(String src, {bool inline = false}) {
    if (_disposed) return;
    final selection = quill.selection;
    final start = selection.start.clamp(0, quill.document.length - 1);
    final length = selection.isValid ? selection.end - selection.start : 0;
    quill.replaceText(
      start,
      length,
      blogQuillImageEmbed(src),
      TextSelection.collapsed(offset: start + 1),
    );
    if (!inline) {
      quill.replaceText(
        start + 1,
        0,
        '\n',
        TextSelection.collapsed(offset: start + 2),
      );
    }
  }

  void expire() {
    ++generation;
    quill.readOnly = true;
    focusNode.unfocus();
    load('');
  }

  void dispose() {
    _disposed = true;
    ++generation;
    _changes?.cancel();
    quill.dispose();
    focusNode.dispose();
    scrollController.dispose();
  }
}
