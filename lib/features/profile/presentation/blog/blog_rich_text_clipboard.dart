import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_size_mapping.dart';
import 'package:y300/features/profile/presentation/blog/blog_quill_html_codec.dart';

/// Consumes the paste operation so Quill cannot import forum AIDs or its own
/// image embeds, neither of which belong to the blog HTML document contract.
Future<bool> pasteBlogText(
  QuillController controller, {
  required bool Function() isCurrent,
}) async {
  if (!isCurrent() || controller.readOnly || !controller.selection.isValid) {
    return true;
  }
  final document = controller.document;
  final selection = controller.selection;
  final internalText = controller.pastePlainText;
  final internalDelta = Delta.from(controller.pasteDelta);
  String? text;
  try {
    text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  } on PlatformException {
    return true;
  } on MissingPluginException {
    return true;
  }
  if (!isCurrent() ||
      controller.readOnly ||
      !identical(controller.document, document) ||
      controller.selection != selection ||
      text == null ||
      text.isEmpty) {
    return true;
  }
  final useDelta = text == internalText && _supportsDelta(internalDelta);
  // An object replacement character from another editor is not body text.
  final plain = text.replaceAll(Embed.kObjectReplacementCharacter, '');
  if (!useDelta && plain.isEmpty) return true;
  final Object value = useDelta ? internalDelta : plain;
  final length = useDelta
      ? internalDelta.toList().fold<int>(
          0,
          (sum, operation) => sum + operation.length!,
        )
      : plain.length;
  controller.replaceText(
    selection.start,
    selection.end - selection.start,
    value,
    null,
  );
  // Quill's Delta paste applies its own selection offset adjustment. Set the
  // final caret explicitly so selected-range replacement cannot jump forward.
  controller.updateSelection(
    TextSelection.collapsed(offset: selection.start + length),
    ChangeSource.local,
  );
  return true;
}

bool supportsBlogTextInsertion(Object? data) {
  if (data is String) return true;
  if (data is Delta) return _supportsDelta(data);
  if (data is Embeddable) {
    return data.type == blogQuillImageEmbedType &&
            blogQuillImagePayload(data) != null ||
        data.type == blogQuillHtmlEmbedType &&
            blogQuillHtmlSource(data) != null;
  }
  return false;
}

bool _supportsDelta(Delta delta) {
  if (delta.isEmpty) return false;
  const attributes = {
    'bold',
    'italic',
    'underline',
    'size',
    'color',
    'font',
    'link',
    'align',
    'list',
    'blockquote',
  };
  for (final operation in delta.toList()) {
    if (!operation.isInsert ||
        (operation.attributes?.keys.any((key) => !attributes.contains(key)) ??
            false)) {
      return false;
    }
    final style = operation.attributes ?? const <String, dynamic>{};
    if (style['size'] != null &&
        composerDiscuzSizeForQuillSize(style['size']) == null) {
      return false;
    }
    if (style['color'] != null &&
        (style['color'] is! String ||
            !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(style['color'] as String))) {
      return false;
    }
    if (style['list'] != null &&
        !const {'ordered', 'bullet'}.contains(style['list'])) {
      return false;
    }
    final value = operation.data;
    if (value is String) continue;
    if (value is! Map || value.length != 1) return false;
    if (value.containsKey(blogQuillImageEmbedType)) {
      if (blogQuillImagePayload(value) == null) return false;
    } else if (value.containsKey(blogQuillHtmlEmbedType)) {
      if (blogQuillHtmlSource(value) == null) return false;
    } else {
      return false;
    }
  }
  return true;
}
