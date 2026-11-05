import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../models/novel_reader_native_prepared_chapter.dart';
import '../models/novel_reader_pagination_exception.dart';
import 'novel_reader_native_work_scheduler.dart';
import 'novel_reader_pagination_cancellation.dart';

/// A layout request's synchronous resource adapter. It borrows the existing
/// Host/policy; no transport, dimension lookup, image cache or native owner is
/// created here. Only immutable values enter the sequential Session.
final class NovelReaderNativeImageResources {
  const NovelReaderNativeImageResources({
    required this.chapter,
    required this.host,
    required this.policy,
    this.threadId,
    this.cacheOwnerId,
  });
  final NovelReaderNativePreparedChapter chapter;
  final ForumHtmlImageHost? host;
  final ForumHtmlPreparationImagePolicy policy;
  final String? threadId, cacheOwnerId;

  /// Freeze the synchronous Host hints, not image bytes or dimension I/O.
  /// Later Session work cannot pick up a different hint under the same key.
  Future<NovelReaderNativeImageCatalog> capture({
    required NovelReaderPaginationCancellationToken cancellation,
    required int maxCodeUnits,
    Map<String, ForumHtmlImageLayout> resolvedLayouts = const {},
    NovelReaderNativeWorkScheduler scheduler =
        const NovelReaderNativeWorkScheduler(),
  }) async {
    if (maxCodeUnits < 0) throw ArgumentError.value(maxCodeUnits);
    final layouts = Map<String, ForumHtmlImageLayout>.of(resolvedLayouts);
    final inputs = <String, ForumBodyImageInput?>{};
    final digest = _ImageGeometryDigest();
    final hashing = sha256.startChunkedConversion(digest);
    var retained = 0, batch = 0;
    final watch = Stopwatch()..start();
    for (final source in chapter.anchors.images) {
      cancellation.throwIfCancelled();
      final element = chapter.document.nodeAtPath(source.path);
      if (element is! ForumBodyElement) {
        throw StateError('Native image source disappeared');
      }
      final original = resolve(chapter.identity, element);
      cancellation.throwIfCancelled();
      ForumBodyImageInput? input;
      if (original != null) {
        input = ForumBodyImageInput(
          identity: original.identity,
          element: original.element,
          entry: original.entry,
          layout: layouts[source.path] ?? original.layout,
        );
        // Block geometry needs one ratio, not widget fallback/display state.
        input = ForumBodyImageInput(
          identity: input.identity,
          element: input.element,
          entry: input.entry,
          layout: ForumHtmlImageLayout(aspectRatio: input.aspectRatio),
        );
      }
      retained += source.path.length + (input?.retainedCodeUnits ?? 0);
      if (retained > maxCodeUnits) {
        throw const NovelReaderPaginationException(
          code: 'nativeImageBudgetExceeded',
          message: 'Native image catalog exceeds its retained input budget.',
        );
      }
      inputs[source.path] = input;
      hashing.add(
        utf8.encode(
          jsonEncode([source.path, input?.entry.cacheKey, input?.aspectRatio]),
        ),
      );
      if (++batch == 64 || watch.elapsedMicroseconds >= 3000) {
        await scheduler.nextFrame(cancellation);
        batch = 0;
        watch.reset();
      }
    }
    cancellation.throwIfCancelled();
    hashing.close();
    return NovelReaderNativeImageCatalog._(
      chapter.identity,
      inputs,
      digest.value!.toString(),
      chapter.episodeId,
    );
  }

  ForumBodyImageInput? resolve(
    ForumBodyIdentity identity,
    ForumBodyElement element,
  ) {
    if (identity != chapter.identity ||
        !identical(chapter.document.nodeAtPath(element.path), element)) {
      throw StateError('Native image source request changed');
    }
    final source = chapter.anchors.imageAtPath(element.path), imageHost = host;
    final reference = element.resource;
    if (source == null ||
        imageHost == null ||
        reference == null ||
        reference.rawSource != source.rawSource) {
      return null;
    }
    final uri = Uri.tryParse(source.url);
    if (uri == null) return null;
    final resource = policy.prepareInline(
      url: uri,
      threadId: threadId,
      imageCacheOwnerId: cacheOwnerId ?? threadId ?? chapter.identity.sourceId,
      imageIndex: source.imageIndex,
      htmlWidth: reference.width,
      htmlHeight: reference.height,
      alt: reference.alt,
      title: reference.title,
    );
    if (resource == null) return null;
    final display = imageHost.resolveImage(
      url: uri,
      imageIndex: source.imageIndex,
      isSticker: false,
      htmlSize: reference.width != null && reference.height != null
          ? Size(reference.width!, reference.height!)
          : null,
    );
    if (display == null ||
        display.sourceUrl != source.url ||
        display.cacheKey != resource.cacheKey ||
        display.isSticker) {
      return null;
    }
    return ForumBodyImageInput(
      identity: identity,
      element: element,
      layout: display.initialLayout,
      entry: ForumHtmlReadableImageEntry(
        index: source.imageIndex,
        url: source.url,
        rawSrc: source.rawSource,
        resource: resource,
        attachmentId: reference.attachmentId,
        alt: reference.alt,
        title: reference.title,
        htmlWidth: reference.width,
        htmlHeight: reference.height,
      ),
    );
  }
}

/// Immutable resource values for exactly one layout. No Host, request runner,
/// Context or image cache is retained. Source ordering gives a stable identity.
final class NovelReaderNativeImageCatalog {
  NovelReaderNativeImageCatalog._(
    this.identity,
    Map<String, ForumBodyImageInput?> inputs,
    this.geometryIdentity,
    String episodeId,
  ) : _inputs = Map.unmodifiable(inputs),
      sequence = ForumHtmlReadableImageSequence(
        sourceId: episodeId,
        entries: List.unmodifiable([
          for (final input in inputs.values)
            if (input != null) input.entry,
        ]),
      );
  final ForumBodyIdentity identity;
  final Map<String, ForumBodyImageInput?> _inputs;
  final String geometryIdentity;
  final ForumHtmlReadableImageSequence sequence;

  ForumBodyImageInput? resolve(
    ForumBodyIdentity identity,
    ForumBodyElement element,
  ) {
    final input = _inputs[element.path];
    if (identity != this.identity ||
        (input != null && !identical(input.element, element))) {
      throw StateError('Native image catalog source changed');
    }
    return input;
  }

  bool owns(ForumBodyImageInput input) =>
      input.identity == identity &&
      identical(_inputs[input.element.path], input);
}

final class _ImageGeometryDigest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
