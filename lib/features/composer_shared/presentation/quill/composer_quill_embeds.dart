import 'package:flutter_quill/flutter_quill.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import 'package:y300/features/composer_shared/domain/services/composer_collapse_bbcode_grammar.dart';

const composerQuillStickerEmbedType = 'sticker';
const composerQuillAttachEmbedType = 'attach';
const composerQuillCollapseEmbedType = 'collapse';
const _collapseGrammar = ComposerCollapseBbCodeGrammar();

Embeddable composerQuillStickerEmbed(String code) {
  return Embeddable(composerQuillStickerEmbedType, code);
}

Embeddable composerQuillCollapseEmbed({
  required String id,
  required String title,
  required String body,
  String? rawOpeningLine,
  String? rawClosing,
}) {
  return Embeddable(
    composerQuillCollapseEmbedType,
    _composerQuillCollapsePayload(
      id: id,
      title: title,
      body: body,
      rawOpeningLine: rawOpeningLine,
      rawClosing: rawClosing,
    ),
  );
}

Embeddable composerQuillAttachEmbed(
  String aid, [
  ComposerAttachTagKind kind = ComposerAttachTagKind.attach,
]) {
  return Embeddable(
    composerQuillAttachEmbedType,
    _composerQuillAttachPayload(aid, kind),
  );
}

String? composerQuillEmbedData(Object? data, String type) {
  if (data is Embeddable && data.type == type) {
    return data.data?.toString();
  }
  if (data is Map && data.containsKey(type)) {
    return data[type]?.toString();
  }
  return null;
}

Map<String, String> composerQuillStickerEmbedData(String code) {
  return <String, String>{composerQuillStickerEmbedType: code};
}

Map<String, Object?> composerQuillCollapseEmbedData({
  required String id,
  required String title,
  required String body,
  String? rawOpeningLine,
  String? rawClosing,
}) {
  return <String, Object?>{
    composerQuillCollapseEmbedType: _composerQuillCollapsePayload(
      id: id,
      title: title,
      body: body,
      rawOpeningLine: rawOpeningLine,
      rawClosing: rawClosing,
    ),
  };
}

Map<String, Object?> _composerQuillCollapsePayload({
  required String id,
  required String title,
  required String body,
  String? rawOpeningLine,
  String? rawClosing,
}) {
  return <String, Object?>{
    'version': 1,
    'id': id,
    'mode': 0,
    'title': title,
    'body': body,
    'rawOpeningLine': ?rawOpeningLine,
    'rawClosing': ?rawClosing,
  };
}

Object? _composerQuillCollapsePayloadFromData(Object? data) {
  if (data is Embeddable && data.type == composerQuillCollapseEmbedType) {
    return data.data;
  }
  if (data is Map && data.containsKey(composerQuillCollapseEmbedType)) {
    return data[composerQuillCollapseEmbedType];
  }
  if (data is Map && data['version'] != null && data['body'] != null) {
    return data;
  }
  return null;
}

Map<String, Object?>? composerQuillCollapseEmbedPayload(Object? data) {
  final payload = _composerQuillCollapsePayloadFromData(data);
  if (payload is! Map) {
    return null;
  }
  final version = int.tryParse(payload['version']?.toString() ?? '');
  final mode = int.tryParse(payload['mode']?.toString() ?? '');
  final id = payload['id']?.toString();
  final title = payload['title']?.toString();
  final body = payload['body']?.toString();
  final rawOpeningValue = payload['rawOpeningLine'];
  final rawClosingValue = payload['rawClosing'];
  if (version != 1 ||
      mode != 0 ||
      id == null ||
      title == null ||
      body == null ||
      !_collapseGrammar.isValidTitle(title) ||
      (rawOpeningValue != null && rawOpeningValue is! String) ||
      (rawClosingValue != null && rawClosingValue is! String)) {
    return null;
  }
  return <String, Object?>{
    'version': version,
    'id': id,
    'mode': mode,
    'title': title,
    'body': body,
    'rawOpeningLine': ?rawOpeningValue,
    'rawClosing': ?rawClosingValue,
  };
}

String? composerQuillCollapseEmbedId(Object? data) {
  return composerQuillCollapseEmbedPayload(data)?['id']?.toString();
}

String? composerQuillCollapseEmbedTitle(Object? data) {
  return composerQuillCollapseEmbedPayload(data)?['title']?.toString();
}

String? composerQuillCollapseEmbedBody(Object? data) {
  return composerQuillCollapseEmbedPayload(data)?['body']?.toString();
}

String? composerQuillCollapseEmbedRawOpeningLine(Object? data) {
  return composerQuillCollapseEmbedPayload(data)?['rawOpeningLine'] as String?;
}

String? composerQuillCollapseEmbedRawClosing(Object? data) {
  return composerQuillCollapseEmbedPayload(data)?['rawClosing'] as String?;
}

Map<String, Object?> composerQuillAttachEmbedData(
  String aid, [
  ComposerAttachTagKind kind = ComposerAttachTagKind.attach,
]) {
  return <String, Object?>{
    composerQuillAttachEmbedType: _composerQuillAttachPayload(aid, kind),
  };
}

String? composerQuillAttachEmbedAid(Object? data) {
  final payload = _composerQuillAttachPayloadFromData(data);
  if (payload is String) {
    return payload;
  }
  if (payload is Map) {
    return payload['aid']?.toString();
  }
  return null;
}

ComposerAttachTagKind composerQuillAttachEmbedTagKind(Object? data) {
  final payload = _composerQuillAttachPayloadFromData(data);
  if (payload is Map &&
      payload['tag']?.toString().toLowerCase() == 'attachimg') {
    return ComposerAttachTagKind.attachImg;
  }
  return ComposerAttachTagKind.attach;
}

Object _composerQuillAttachPayload(String aid, ComposerAttachTagKind kind) {
  // New embeds always persist both pieces of identity. Legacy persisted
  // embeds remain supported by the readers below when their payload is only
  // the aid string.
  return <String, String>{'aid': aid, 'tag': kind.wireName};
}

Object? _composerQuillAttachPayloadFromData(Object? data) {
  if (data is Embeddable && data.type == composerQuillAttachEmbedType) {
    return data.data;
  }
  if (data is Map && data.containsKey(composerQuillAttachEmbedType)) {
    return data[composerQuillAttachEmbedType];
  }
  if (data is Map && data.containsKey('aid')) {
    return data;
  }
  // Embed builders receive the inner payload, while delta codecs commonly
  // receive the outer {attach: payload} map. A raw string is the legacy inner
  // payload shape used by image insertion and older persisted documents.
  if (data is String) {
    return data;
  }
  return null;
}
