import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_detail_diagnostic_event.dart';
import 'package:y300/features/thread/domain/services/thread_detail_diagnostic_recorder.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';

class ThreadHtmlImagePreloadCoordinator {
  ThreadHtmlImagePreloadCoordinator({
    required ForumImagePrecacheService precacheService,
    ThreadDetailDiagnosticRecorder diagnosticRecorder =
        const NoopThreadDetailDiagnosticRecorder(),
    this.firstWindowImageLimit = 3,
    this.nearWindowImageLimit = 2,
    this.nearWindowPostLookAhead = 2,
  }) : _precacheService = precacheService,
       _diagnosticRecorder = diagnosticRecorder;

  final ForumImagePrecacheService _precacheService;
  final ThreadDetailDiagnosticRecorder _diagnosticRecorder;
  final int firstWindowImageLimit;
  final int nearWindowImageLimit;
  final int nearWindowPostLookAhead;
  final Set<String> _scheduledKeys = <String>{};
  var _generation = 0;

  void reset() {
    _generation += 1;
    _scheduledKeys.clear();
  }

  void dispose() {
    reset();
  }

  Future<List<ForumImagePrecacheResult>> preloadFirstWindow({
    required BuildContext context,
    required String tid,
    required List<ThreadPost> posts,
    required ThreadPostBodyRenderPlan Function(ThreadPost post) planFor,
    Size? expectedDisplaySize,
  }) {
    final specs = <ForumImageLoadSpec>[];
    for (final post in posts) {
      if (specs.length >= firstWindowImageLimit) {
        break;
      }
      specs.addAll(
        _specsForPost(
          tid: tid,
          post: post,
          plan: planFor(post),
        ).take(firstWindowImageLimit - specs.length),
      );
    }
    return _schedule(
      context: context,
      specs: specs,
      expectedDisplaySize: expectedDisplaySize,
    );
  }

  Future<List<ForumImagePrecacheResult>> preloadNearWindow({
    required BuildContext context,
    required String tid,
    required List<ThreadPost> posts,
    required int visiblePostIndex,
    required ThreadPostBodyRenderPlan Function(ThreadPost post) planFor,
    Size? expectedDisplaySize,
  }) {
    if (posts.isEmpty || visiblePostIndex < 0) {
      return Future<List<ForumImagePrecacheResult>>.value(
        const <ForumImagePrecacheResult>[],
      );
    }
    final start = visiblePostIndex.clamp(0, posts.length - 1);
    final end = (start + nearWindowPostLookAhead).clamp(0, posts.length - 1);
    final specs = <ForumImageLoadSpec>[];
    for (var index = start; index <= end; index++) {
      if (specs.length >= nearWindowImageLimit) {
        break;
      }
      final post = posts[index];
      specs.addAll(
        _specsForPost(
          tid: tid,
          post: post,
          plan: planFor(post),
        ).take(nearWindowImageLimit - specs.length),
      );
    }
    return _schedule(
      context: context,
      specs: specs,
      expectedDisplaySize: expectedDisplaySize,
    );
  }

  Iterable<ForumImageLoadSpec> _specsForPost({
    required String tid,
    required ThreadPost post,
    required ThreadPostBodyRenderPlan plan,
  }) sync* {
    for (final image in plan.images) {
      final uri = Uri.tryParse(image.url.trim());
      if (uri == null) {
        continue;
      }
      yield ForumImageLoadSpec(
        kind: ForumImageKind.threadInline,
        url: uri,
        ownerId: tid,
        imageIndex: image.index,
        htmlWidth: image.originalWidth,
        htmlHeight: image.originalHeight,
        alt: image.altText,
        allowReaderOpen: true,
      );
    }
  }

  Future<List<ForumImagePrecacheResult>> _schedule({
    required BuildContext context,
    required Iterable<ForumImageLoadSpec> specs,
    required Size? expectedDisplaySize,
  }) {
    final generation = _generation;
    final tasks = <Future<ForumImagePrecacheResult>>[];
    for (final spec in specs) {
      final key = _scheduleKey(spec);
      if (!_scheduledKeys.add(key)) {
        continue;
      }
      tasks.add(
        _precacheService
            .precacheDecoded(
              context: context,
              spec: spec,
              expectedDisplaySize: expectedDisplaySize,
            )
            .then((result) {
              if (generation != _generation) {
                return const ForumImagePrecacheResult(success: false);
              }
              _recordPrecacheResult(spec, result);
              return result;
            }),
      );
    }
    if (tasks.isEmpty) {
      return Future<List<ForumImagePrecacheResult>>.value(
        const <ForumImagePrecacheResult>[],
      );
    }
    return Future.wait(tasks);
  }

  String _scheduleKey(ForumImageLoadSpec spec) {
    final index = spec.imageIndex;
    return '${spec.ownerId ?? 'unknown'}:${spec.sourceUrl}:${index ?? '-'}';
  }

  void _recordPrecacheResult(
    ForumImageLoadSpec spec,
    ForumImagePrecacheResult result,
  ) {
    if (!_diagnosticRecorder.enabled) {
      return;
    }
    _diagnosticRecorder.record(
      type: ThreadDetailDiagnosticEventType.htmlFirstImageDiagnostics,
      message:
          'html-first-preload kind=${spec.kind.name} '
          'url=${spec.sourceUrl} success=${result.success} '
          'diskAttempted=${result.diskCacheAttempted} '
          'diskHit=${result.fromDiskCache} '
          'decodeAttempted=${result.decodePrecacheAttempted} '
          'decoded=${result.decoded} '
          'reason=${result.failureReason ?? '-'}',
    );
  }
}
