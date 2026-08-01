import 'package:flutter_quill/flutter_quill.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';

const composerQuillStickerEmbedType = 'sticker';
const composerQuillAttachEmbedType = 'attach';

Embeddable composerQuillStickerEmbed(String code) {
  return Embeddable(composerQuillStickerEmbedType, code);
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
