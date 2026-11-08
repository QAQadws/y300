import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'forum_native_body_images.dart';

/// Resolved inputs shared by a mounted flow and an explicit navigation demand.
/// Hosts and live source work belong to that demand, never to a reusable cache.
final class ForumNativeBodyFlowInput {
  ForumNativeBodyFlowInput({
    required this.document,
    required this.prepared,
    required this.width,
    this.compactMinWidth,
    required this.textStyle,
    required this.fontRevision,
    required this.textScaler,
    required this.direction,
    required this.paragraphAfter,
    required this.theme,
    required this.cache,
    required this.host,
    required Map<String, bool> expansion,
    this.presentation,
    this.preparationIdentity,
    this.resourceIdentity,
  }) : expansion = Map.unmodifiable(expansion);

  static const sliceHeight = 768.0;
  static const limits = ForumBodyTextPageSessionLimits(
    maxPages: 10000,
    maxFragments: 100000,
    maxParagraphs: 16384,
    maxTextCodeUnits: 1024 * 1024,
    maxRuns: 100000,
    maxIssuedLeases: 256,
  );
  static var _layoutSerial = 0;

  final ForumBodyDocument document;
  final ForumHtmlPreparedRenderDocument prepared;
  final double width;
  final double? compactMinWidth;
  final TextStyle textStyle;
  final String fontRevision;
  final TextScaler textScaler;
  final TextDirection direction;
  final double paragraphAfter;
  final ForumHtmlThemeContext theme;
  final ForumBodyParagraphCache cache;
  final ForumHtmlImageHost? host;
  final Map<String, bool> expansion;
  final ForumHtmlBodyPresentation? presentation;
  final Object? preparationIdentity;
  final Object? resourceIdentity;

  Object get identity => (
    document.identity,
    prepared.preparedHtml,
    width,
    compactMinWidth,
    textStyle,
    fontRevision,
    textScaler,
    direction,
    paragraphAfter,
    theme.signature,
    cache,
    host,
    preparationIdentity,
    resourceIdentity,
    presentation,
  );

  bool matches(ForumNativeBodyFlowInput other) =>
      identity == other.identity && mapEquals(expansion, other.expansion);

  FutureOr<ForumNativeBodyPreparedSource> open({
    required bool Function() isCurrent,
    Map<String, ForumNativeBodyImageLayoutHint> learned = const {},
    ForumNativeBodyImages? previousImages,
  }) {
    void guard() {
      if (!isCurrent() || cache.isClosed || presentation?.isActive == false) {
        throw const ForumBodyFlowPreparationCancelled();
      }
    }

    guard();
    final body = document;
    final collapses = ForumBodyCollapseLayout(
      body,
      expansionOverrides: expansion,
    );
    final reader = ForumBodyReaderStyle(
      textStyle: textStyle,
      fontRevision: fontRevision,
      linkColor: theme.link,
      textDirection: direction,
      paragraphAfter: paragraphAfter,
      theme: theme,
    );
    final images = ForumNativeBodyImages(body, presentation: presentation);
    final clock = Stopwatch()..start();
    final iterator = body.imageElements.iterator;
    ForumBodyElement? pending;
    var exhausted = false, batchCount = 0;
    bool advanceImages() {
      final imageHost = host;
      if (imageHost == null) return true;
      while (!exhausted) {
        if (pending == null) {
          if (!iterator.moveNext()) {
            exhausted = true;
            break;
          }
          pending = iterator.current;
        }
        if (batchCount >= 48 ||
            (batchCount > 0 && clock.elapsedMicroseconds >= 3000)) {
          return false;
        }
        final element = pending!;
        pending = null;
        batchCount++;
        if (!const ForumBodyStyleResolver().isVisibleAt(
          body,
          reader,
          element,
          collapses: collapses,
        )) {
          continue;
        }
        images.add(
          element: element,
          sequence: prepared.sequence,
          host: imageHost,
          learnedLayout:
              learned[element.path] ?? previousImages?.layoutHintFor(element),
        );
      }
      return true;
    }

    ForumNativeBodyPreparedSource finish() {
      guard();
      final nativeCache = cache;
      final scaler = textScaler;
      final availableWidth = width;
      final layoutId = 'forum-flow-${++_layoutSerial}';
      final source = ForumBodyFlowSource(
        width: availableWidth,
        compactMinWidth: compactMinWidth,
        openSession: (bodyWidth, {required probe}) => ForumBodyTextPageSession(
          document: body,
          width: bodyWidth,
          height: sliceHeight,
          layoutId: layoutId,
          reader: reader,
          textScaler: scaler,
          cache: nativeCache,
          limits: limits,
          collapses: collapses,
          tableExtent: ForumBodyTableExtent.natural,
          intrinsicAvailableWidth: probe ? availableWidth : null,
          captureFloats: true,
          imageResolver: images.block,
          inlineImageResolver: (identity, element, style) =>
              images.inline(identity, element, style, scaler, sliceHeight),
        ),
      );
      return ForumNativeBodyPreparedSource(this, images, source);
    }

    // Keep the common path synchronous: an artificial Future here moves a
    // post-frame source start into idle and would impose another frame wait.
    if (advanceImages()) return finish();
    return (() async {
      while (true) {
        final binding = WidgetsBinding.instance;
        binding.ensureVisualUpdate();
        await binding.endOfFrame;
        guard();
        clock.reset();
        batchCount = 0;
        if (advanceImages()) return finish();
      }
    })();
  }
}

final class ForumNativeBodyPreparedSource {
  ForumNativeBodyPreparedSource(this.input, this.images, this.source);
  final ForumNativeBodyFlowInput input;
  final ForumNativeBodyImages images;
  final ForumBodyFlowSource source;

  void close() => source.close();
}
