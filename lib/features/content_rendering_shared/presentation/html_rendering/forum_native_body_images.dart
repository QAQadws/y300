import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

/// Frozen resources for the prepared body that supplies the viewer list.
final class ForumNativeBodyImages {
  ForumNativeBodyImages(this.document);

  final ForumBodyDocument document;
  final _sources = <String, ForumBodyInlineImageSource>{};
  final _layouts = <String, ForumHtmlImageLayout>{};
  final _pathsByIndex = <int, String>{};

  String? pathForIndex(int index) => _pathsByIndex[index];

  ForumHtmlReadableImageSequence galleryFor(
    ForumHtmlReadableImageSequence source,
  ) {
    if (_pathsByIndex.length == source.entries.length) return source;
    return ForumHtmlReadableImageSequence(
      sourceId: source.sourceId,
      entries: List.unmodifiable([
        for (final entry in source.entries)
          if (_pathsByIndex.containsKey(entry.index)) entry,
      ]),
    );
  }

  void add({
    required ForumBodyElement element,
    required ForumHtmlReadableImageSequence sequence,
    required ForumHtmlImageHost host,
    required ForumHtmlImageLayout? learnedLayout,
  }) {
    final reference = element.resource!;
    final raw = reference.rawSource;
    final resolved = raw == null ? null : const SiteUrlResolver().resolve(raw);
    final uri = resolved == null
        ? null
        : Uri.tryParse(resolved)?.removeFragment();
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    final index = reference.readableImageIndex;
    final original = index == null ? null : sequence.entryAt(index);
    final isSticker = uri.path.toLowerCase().contains('/static/image/smiley/');
    if (isSticker
        ? index != null
        : original == null ||
              original.url != uri.toString() ||
              _pathsByIndex.containsKey(index)) {
      return;
    }
    final size = reference.width != null && reference.height != null
        ? Size(reference.width!, reference.height!)
        : null;
    final display = host.resolveImage(
      url: uri,
      imageIndex: index,
      isSticker: isSticker,
      htmlSize: size,
    );
    if (display == null ||
        display.sourceUrl != uri.toString() ||
        display.isSticker != isSticker ||
        (original != null && display.cacheKey != original.cacheKey)) {
      return;
    }
    // Preparation can normalize src. Keep the viewer entry in its original
    // sequence while the renderer verifies the actual prepared attribute.
    final entry = original == null || original.rawSrc == raw
        ? original
        : ForumHtmlReadableImageEntry(
            index: original.index,
            url: original.url,
            rawSrc: raw!,
            resource: original.resource,
            attachmentId: original.attachmentId,
            alt: original.alt,
            title: original.title,
            htmlWidth: original.htmlWidth,
            htmlHeight: original.htmlHeight,
          );
    _sources[element.path] = ForumBodyInlineImageSource(
      document: document,
      element: element,
      image: display,
      entry: entry,
    );
    _layouts[element.path] = learnedLayout ?? display.initialLayout;
    if (index != null) _pathsByIndex[index] = element.path;
  }

  ForumBodyInlineImageSource? _source(
    ForumBodyIdentity identity,
    ForumBodyElement element,
  ) {
    final source = _sources[element.path];
    return identity == document.identity && identical(source?.element, element)
        ? source
        : null;
  }

  ForumBodyImageInput? block(
    ForumBodyIdentity identity,
    ForumBodyElement element,
  ) {
    final source = _source(identity, element);
    final entry = source?.entry;
    return entry == null
        ? null
        : ForumBodyImageInput(
            identity: identity,
            element: element,
            entry: entry,
            layout: _layouts[element.path]!,
          );
  }

  ForumBodyInlineImageInput? inline(
    ForumBodyIdentity identity,
    ForumBodyElement element,
    ForumBodyResolvedStyle style,
    TextScaler scaler,
    double height,
  ) {
    final source = _source(identity, element);
    if (source == null ||
        (source.entry != null &&
            !const {
              'inline',
              'inline-block',
            }.contains(element.style.value('display')?.trim().toLowerCase()))) {
      return null;
    }
    for (final (property, normal) in const [
      ('float', 'none'),
      ('clear', 'none'),
      ('position', 'static'),
    ]) {
      final value = element.style.value(property)?.trim().toLowerCase();
      if (value != null &&
          value != normal &&
          value != 'initial' &&
          value != 'unset') {
        return null;
      }
    }
    final layout = _layouts[element.path]!;
    final em = scaler.scale(style.textStyle.fontSize!);
    final ratio = layout.isFallback ? null : layout.aspectRatio;
    final imageHeight = ratio == null ? em : em / ratio;
    final intrinsic =
        layout.displaySize ??
        source.image.htmlSize ??
        Size(em, imageHeight.isFinite && imageHeight > 0 ? imageHeight : em);
    return ForumBodyInlineImageInput.replaced(
      source: source,
      box: style.box,
      intrinsicSize: intrinsic,
      maxHeight: height - math.min(em, height / 2),
    );
  }

  ForumHtmlImageLayout? layoutFor(ForumBodyElement element) =>
      _layouts[element.path];
}
