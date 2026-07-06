import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';

@immutable
class ForumHtmlRenderCallbacks {
  const ForumHtmlRenderCallbacks({this.onTapUrl, this.onTapImage});

  final FutureOr<bool> Function(String url)? onTapUrl;
  final void Function(ForumHtmlImageRequest request)? onTapImage;
}

@immutable
class ForumHtmlImageRequest {
  const ForumHtmlImageRequest({
    required this.url,
    this.alt,
    this.title,
    this.width,
    this.height,
    this.isSticker = false,
    this.attachmentId,
    this.readableIndex,
    this.cacheKey,
    this.kind,
  });

  final String url;
  final String? alt;
  final String? title;
  final double? width;
  final double? height;
  final bool isSticker;
  final String? attachmentId;
  final int? readableIndex;
  final String? cacheKey;
  final ForumImageKind? kind;
}
