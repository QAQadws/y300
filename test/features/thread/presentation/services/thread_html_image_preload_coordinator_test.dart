import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';
import 'package:y300/features/thread/presentation/services/thread_html_image_preload_coordinator.dart';

void main() {
  testWidgets('preloadFirstWindow submits only the first 1-3 body images', (
    tester,
  ) async {
    final service = _RecordingPrecacheService();
    final coordinator = ThreadHtmlImagePreloadCoordinator(
      precacheService: service,
      firstWindowImageLimit: 3,
    );
    final posts = <ThreadPost>[_post('1'), _post('2'), _post('3'), _post('4')];
    final plans = <String, ThreadPostBodyRenderPlan>{
      '1': _plan(<ThreadPostImageBlock>[_image(0), _image(1)]),
      '2': _plan(<ThreadPostImageBlock>[_image(2), _image(3)]),
      '3': _plan(<ThreadPostImageBlock>[_image(4)]),
      '4': _plan(<ThreadPostImageBlock>[_image(5)]),
    };

    await _withContext(tester, (context) {
      return coordinator.preloadFirstWindow(
        context: context,
        tid: '573279',
        posts: posts,
        planFor: (post) => plans[post.pid]!,
        expectedDisplaySize: const Size(320, double.nan),
      );
    });

    expect(service.decodedSpecs.map((spec) => spec.imageIndex), <int>[0, 1, 2]);
    expect(
      service.decodedSpecs.map((spec) => spec.kind).toSet(),
      <ForumImageKind>{ForumImageKind.threadInline},
    );
  });

  testWidgets(
    'preloadNearWindow submits a small window from built post index',
    (tester) async {
      final service = _RecordingPrecacheService();
      final coordinator = ThreadHtmlImagePreloadCoordinator(
        precacheService: service,
        nearWindowImageLimit: 2,
        nearWindowPostLookAhead: 2,
      );
      final posts = <ThreadPost>[_post('1'), _post('2'), _post('3')];
      final plans = <String, ThreadPostBodyRenderPlan>{
        '1': _plan(<ThreadPostImageBlock>[_image(0)]),
        '2': _plan(<ThreadPostImageBlock>[_image(1), _image(2)]),
        '3': _plan(<ThreadPostImageBlock>[_image(3)]),
      };

      await _withContext(tester, (context) {
        return coordinator.preloadNearWindow(
          context: context,
          tid: '573279',
          posts: posts,
          visiblePostIndex: 1,
          planFor: (post) => plans[post.pid]!,
        );
      });

      expect(service.decodedSpecs.map((spec) => spec.imageIndex), <int>[1, 2]);
    },
  );

  testWidgets('preload skips duplicate image specs until reset', (
    tester,
  ) async {
    final service = _RecordingPrecacheService();
    final coordinator = ThreadHtmlImagePreloadCoordinator(
      precacheService: service,
      firstWindowImageLimit: 3,
    );
    final posts = <ThreadPost>[_post('1')];
    final plans = <String, ThreadPostBodyRenderPlan>{
      '1': _plan(<ThreadPostImageBlock>[_image(0), _image(1)]),
    };

    await _withContext(tester, (context) {
      return coordinator.preloadFirstWindow(
        context: context,
        tid: '573279',
        posts: posts,
        planFor: (post) => plans[post.pid]!,
      );
    });
    await _withContext(tester, (context) {
      return coordinator.preloadFirstWindow(
        context: context,
        tid: '573279',
        posts: posts,
        planFor: (post) => plans[post.pid]!,
      );
    });

    expect(service.decodedSpecs, hasLength(2));
    coordinator.reset();
    await _withContext(tester, (context) {
      return coordinator.preloadFirstWindow(
        context: context,
        tid: '573279',
        posts: posts,
        planFor: (post) => plans[post.pid]!,
      );
    });
    expect(service.decodedSpecs, hasLength(4));
  });

  testWidgets('does not preload inline smiley-only posts', (tester) async {
    final service = _RecordingPrecacheService();
    final coordinator = ThreadHtmlImagePreloadCoordinator(
      precacheService: service,
    );
    final posts = <ThreadPost>[_post('1')];
    final plan = const ThreadPostBodyRenderPlanner().plan(
      '<p>hello <img src="static/image/smiley/comcom/2.gif"></p>',
    );

    await _withContext(tester, (context) {
      return coordinator.preloadFirstWindow(
        context: context,
        tid: '573279',
        posts: posts,
        planFor: (_) => plan,
      );
    });

    expect(service.decodedSpecs, isEmpty);
  });
}

Future<List<ForumImagePrecacheResult>> _withContext(
  WidgetTester tester,
  Future<List<ForumImagePrecacheResult>> Function(BuildContext context) run,
) async {
  late Future<List<ForumImagePrecacheResult>> future;
  await tester.pumpWidget(
    LocalizedTestApp(
      home: Builder(
        builder: (context) {
          future = run(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return future;
}

ThreadPostBodyRenderPlan _plan(List<ThreadPostImageBlock> images) {
  return const ThreadPostBodyRenderPlanner().planDocument(
    ThreadPostBodyDocument(blocks: images),
  );
}

ThreadPostImageBlock _image(int index) {
  return ThreadPostImageBlock(
    url: 'https://bbs.yamibo.com/data/attachment/forum/page-$index.jpg',
    rawUrl: 'data/attachment/forum/page-$index.jpg',
    index: index,
  );
}

ThreadPost _post(String pid) {
  return ThreadPost(
    pid: pid,
    author: 'author',
    authorId: '1',
    message: '',
    number: int.parse(pid),
    isFirst: pid == '1',
    dateline: '2026-07-06',
  );
}

class _RecordingPrecacheService implements ForumImagePrecacheService {
  final decodedSpecs = <ForumImageLoadSpec>[];

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async {
    return const ForumImagePrecacheResult(success: true);
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async {
    decodedSpecs.add(spec);
    return const ForumImagePrecacheResult(success: true, decoded: true);
  }
}
