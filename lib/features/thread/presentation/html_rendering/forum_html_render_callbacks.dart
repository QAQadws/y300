import 'dart:async';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';

@immutable
class ForumHtmlRenderCallbacks {
  const ForumHtmlRenderCallbacks({
    this.onTapUrl,
    this.onTapImage,
    this.onImageLayoutShift,
  });

  final FutureOr<bool> Function(String url)? onTapUrl;
  final void Function(ForumHtmlImageRequest request)? onTapImage;
  final void Function(ForumHtmlImageLayoutShift shift)? onImageLayoutShift;
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

@immutable
class ForumHtmlImageLayoutShift {
  const ForumHtmlImageLayoutShift({
    required this.sourceUrl,
    required this.cacheKey,
    required this.oldGlobalRect,
    required this.oldSize,
    required this.newSize,
    required this.oldAspectRatio,
    required this.newAspectRatio,
  });

  final String sourceUrl;
  final String cacheKey;
  final Rect oldGlobalRect;
  final Size oldSize;
  final Size newSize;
  final double oldAspectRatio;
  final double newAspectRatio;

  double get deltaHeight => newSize.height - oldSize.height;
}
