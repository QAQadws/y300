import 'package:flutter_quill/flutter_quill.dart';

const composerQuillStickerEmbedType = 'sticker';
const composerQuillAttachEmbedType = 'attach';

Embeddable composerQuillStickerEmbed(String code) {
  return Embeddable(composerQuillStickerEmbedType, code);
}

Embeddable composerQuillAttachEmbed(String aid) {
  return Embeddable(composerQuillAttachEmbedType, aid);
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

Map<String, String> composerQuillAttachEmbedData(String aid) {
  return <String, String>{composerQuillAttachEmbedType: aid};
}
