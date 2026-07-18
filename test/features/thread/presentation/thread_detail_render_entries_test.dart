import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/domain/models/thread_detail_diagnostic_event.dart';
import 'package:y300/features/thread/domain/services/thread_detail_diagnostic_recorder.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_display_transformer.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_parser.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';
import 'package:y300/features/thread/domain/services/thread_post_resource_layout_hint_resolver.dart';
import 'package:y300/features/thread/presentation/thread_detail_render_entries.dart';

void main() {
  group('ThreadDetailRenderEntryPlanner', () {
    test('builds one body entry for short text posts', () {
      final parser = _CountingThreadPostBodyParser();
      final planner = ThreadDetailRenderEntryPlanner(
        bodyRenderPlanner: ThreadPostBodyRenderPlanner(parser: parser),
      );

      final entries = planner.buildEntries(
        posts: <ThreadPost>[
          ThreadPost(
            pid: 'p1',
            author: 'alice',
            authorId: '1',
            message: '<p>普通正文</p>',
            number: 1,
            isFirst: true,
            dateline: 'today',
          ),
        ],
      );

      expect(entries.map((entry) => entry.kind), <ThreadDetailRenderEntryKind>[
        ThreadDetailRenderEntryKind.postCard,
        ThreadDetailRenderEntryKind.pagination,
      ]);
      expect(entries[0].key, 'thread-post-card-entry-p1');
      expect(entries[0].requirePlan().usesListSegments, isFalse);
      expect(parser.parseCount, 1);
    });

    test('keeps long text posts as one production body entry', () {
      final parser = _CountingThreadPostBodyParser();
      final planner = ThreadDetailRenderEntryPlanner(
        bodyRenderPlanner: ThreadPostBodyRenderPlanner(
          parser: parser,
          maxSegmentTextLength: 6,
        ),
      );

      final entries = planner.buildEntries(
        posts: <ThreadPost>[
          ThreadPost(
            pid: 'p-long',
            author: 'alice',
            authorId: '1',
            message: '<p>abcdefghijklmnop</p>',
            number: 1,
            isFirst: true,
            dateline: 'today',
          ),
        ],
      );

      expect(entries.map((entry) => entry.kind), <ThreadDetailRenderEntryKind>[
        ThreadDetailRenderEntryKind.postCard,
        ThreadDetailRenderEntryKind.pagination,
      ]);
      expect(entries[0].key, 'thread-post-card-entry-p-long');
      expect(entries[0].requirePlan().usesListSegments, isTrue);
      expect(parser.parseCount, 1);
    });

    test('production planner keeps each post as one stable entry', () {
      final planner = ThreadDetailRenderEntryPlanner(
        bodyRenderPlanner: const ThreadPostBodyRenderPlanner(
          maxSegmentTextLength: 6,
        ),
      );

      final entries = planner.buildEntries(
        posts: <ThreadPost>[
          ThreadPost(
            pid: 'p-html',
            author: 'alice',
            authorId: '1',
            message: '<p>abcdefghijklmnop</p>',
            number: 1,
            isFirst: true,
            dateline: 'today',
          ),
        ],
      );

      expect(entries.map((entry) => entry.kind), <ThreadDetailRenderEntryKind>[
        ThreadDetailRenderEntryKind.postCard,
        ThreadDetailRenderEntryKind.pagination,
      ]);
      expect(entries[0].requirePlan().usesListSegments, isTrue);
    });

    test('keeps image bodies as one production body entry', () {
      final planner = ThreadDetailRenderEntryPlanner();

      final entries = planner.buildEntries(
        posts: <ThreadPost>[
          ThreadPost(
            pid: 'p2',
            author: 'alice',
            authorId: '1',
            message:
                '<p>开头</p>'
                '<img file="data/attachment/forum/1.jpg">'
                '<img file="data/attachment/forum/2.jpg">'
                '<p>结尾</p>',
            number: 1,
            isFirst: true,
            dateline: 'today',
          ),
        ],
        targetPid: 'p2',
      );

      expect(entries.map((entry) => entry.kind), <ThreadDetailRenderEntryKind>[
        ThreadDetailRenderEntryKind.postCard,
        ThreadDetailRenderEntryKind.pagination,
        ThreadDetailRenderEntryKind.targetSpacer,
      ]);
      expect(entries[0].key, 'thread-post-card-entry-p2');
      expect(entries[0].requirePlan().usesListSegments, isTrue);
      expect(entries.last.kind, ThreadDetailRenderEntryKind.targetSpacer);
    });

    test('render plans expose resource layout hints', () {
      final planner = ThreadDetailRenderEntryPlanner();
      final post = ThreadPost(
        pid: 'p-hint',
        author: 'alice',
        authorId: '1',
        message:
            '<img file="data/attachment/forum/1.jpg" width="120" height="80">',
        number: 1,
        isFirst: true,
        dateline: 'today',
      );

      final plan = planner.planFor(post);
      final image = plan.images.single;
      final hint = plan.resourceLayoutHints.blockImage(image);

      expect(hint?.aspectRatio, 1.5);
      expect(hint?.source, ThreadPostResourceLayoutHintSource.htmlAttribute);
    });

    test('reuses render plans across repeated entry builds', () {
      final parser = _CountingThreadPostBodyParser();
      final planner = ThreadDetailRenderEntryPlanner(
        bodyRenderPlanner: ThreadPostBodyRenderPlanner(parser: parser),
      );
      final post = ThreadPost(
        pid: 'p-cached',
        author: 'alice',
        authorId: '1',
        message: '<p>开头</p><img file="data/attachment/forum/1.jpg">',
        number: 1,
        isFirst: true,
        dateline: 'today',
      );

      planner.buildEntries(posts: <ThreadPost>[post]);
      planner.buildEntries(posts: <ThreadPost>[post]);

      expect(parser.parseCount, 1);
    });

    test('keeps short smiley-only text in one body entry', () {
      final parser = _CountingThreadPostBodyParser();
      final planner = ThreadDetailRenderEntryPlanner(
        bodyRenderPlanner: ThreadPostBodyRenderPlanner(parser: parser),
      );
      final smileys = List.filled(
        12,
        '<img src="static/image/smiley/comcom/2.gif" class="vm">',
      ).join();

      final entries = planner.buildEntries(
        posts: <ThreadPost>[
          ThreadPost(
            pid: 'p-smiley',
            author: 'alice',
            authorId: '1',
            message: '<p>正文 $smileys</p>',
            number: 1,
            isFirst: true,
            dateline: 'today',
          ),
        ],
      );

      expect(entries.map((entry) => entry.kind), <ThreadDetailRenderEntryKind>[
        ThreadDetailRenderEntryKind.postCard,
        ThreadDetailRenderEntryKind.pagination,
      ]);
      expect(entries[0].requirePlan().usesListSegments, isFalse);
      expect(parser.parseCount, 1);
    });

    test('reuses render plans until the post message changes', () {
      final planner = ThreadDetailRenderEntryPlanner();
      final post = ThreadPost(
        pid: 'p3',
        author: 'alice',
        authorId: '1',
        message: '<p>旧正文</p>',
        number: 1,
        isFirst: true,
        dateline: 'today',
      );

      final firstPlan = planner.planFor(post);
      final secondPlan = planner.planFor(post);
      final changedPlan = planner.planFor(
        ThreadPost(
          pid: 'p3',
          author: 'alice',
          authorId: '1',
          message: '<p>新正文</p>',
          number: 1,
          isFirst: true,
          dateline: 'today',
        ),
      );

      expect(identical(firstPlan, secondPlan), isTrue);
      expect(identical(firstPlan, changedPlan), isFalse);
    });

    test('cache keys use message hash instead of raw message', () {
      final planner = ThreadDetailRenderEntryPlanner();
      final post = ThreadPost(
        pid: 'p-key',
        author: 'alice',
        authorId: '1',
        message: '<p>非常长的正文内容</p>',
        number: 1,
        isFirst: true,
        dateline: 'today',
      );

      final key = planner.cacheKeyForPost(post);

      expect(key.pid, 'p-key');
      expect(key.messageHash, isNot(post.message));
      expect(key.messageHash.length, 16);
      expect(
        key.renderSettingsSignature,
        ThreadPostBodyRenderSettings.defaults.signature,
      );
      expect(
        key.resourceHintResolverSignature,
        const ThreadPostResourceLayoutHintResolver().signature,
      );
      expect(key.displayTransformerSignature, 'identity');
    });

    test('render settings participate in render plan cache keys', () {
      final post = ThreadPost(
        pid: 'p-settings',
        author: 'alice',
        authorId: '1',
        message: '<p>正文</p>',
        number: 1,
        isFirst: true,
        dateline: 'today',
      );
      final defaultPlanner = ThreadDetailRenderEntryPlanner();
      final largeTextPlanner = ThreadDetailRenderEntryPlanner(
        renderSettings: ThreadPostBodyRenderSettings.defaults.copyWith(
          fontSize: 20,
        ),
      );

      final defaultKey = defaultPlanner.cacheKeyForPost(post);
      final largeTextKey = largeTextPlanner.cacheKeyForPost(post);

      expect(defaultKey.messageHash, largeTextKey.messageHash);
      expect(
        defaultKey.renderSettingsSignature,
        isNot(largeTextKey.renderSettingsSignature),
      );
      expect(defaultKey, isNot(largeTextKey));
    });

    test('resource hint resolver signature participates in cache keys', () {
      final post = ThreadPost(
        pid: 'p-resource-hint',
        author: 'alice',
        authorId: '1',
        message: '<img file="data/attachment/forum/1.jpg">',
        number: 1,
        isFirst: true,
        dateline: 'today',
      );
      final defaultPlanner = ThreadDetailRenderEntryPlanner();
      final alternateHintPlanner = ThreadDetailRenderEntryPlanner(
        bodyRenderPlanner: const ThreadPostBodyRenderPlanner(
          resourceLayoutHintResolver: ThreadPostResourceLayoutHintResolver(
            defaultBlockImageAspectRatio: 1.0,
          ),
        ),
      );

      final defaultKey = defaultPlanner.cacheKeyForPost(post);
      final alternateKey = alternateHintPlanner.cacheKeyForPost(post);

      expect(defaultKey.messageHash, alternateKey.messageHash);
      expect(
        defaultKey.resourceHintResolverSignature,
        isNot(alternateKey.resourceHintResolverSignature),
      );
      expect(defaultKey, isNot(alternateKey));
    });

    test('display transformer signature participates in cache keys', () {
      final post = ThreadPost(
        pid: 'p-display',
        author: 'alice',
        authorId: '1',
        message: '<p>正文</p>',
        number: 1,
        isFirst: true,
        dateline: 'today',
      );
      final defaultPlanner = ThreadDetailRenderEntryPlanner();
      final transformedPlanner = ThreadDetailRenderEntryPlanner(
        bodyRenderPlanner: const ThreadPostBodyRenderPlanner(
          displayTransformer: ThreadPostBodyDisplayTransformer(
            textTransformer: _replaceBodyText,
            signature: 'replace-body-text',
          ),
        ),
      );

      final defaultKey = defaultPlanner.cacheKeyForPost(post);
      final transformedKey = transformedPlanner.cacheKeyForPost(post);
      final transformedPlan = transformedPlanner.planFor(post);

      expect(defaultKey.messageHash, transformedKey.messageHash);
      expect(
        defaultKey.displayTransformerSignature,
        isNot(transformedKey.displayTransformerSignature),
      );
      expect(defaultKey, isNot(transformedKey));
      expect(transformedPlan.displayTransformerSignature, 'replace-body-text');
      expect(
        (transformedPlan.displayDocument.blocks.single as ThreadPostTextBlock)
            .plainText,
        '显示正文',
      );
      expect(
        (transformedPlan.document.blocks.single as ThreadPostTextBlock)
            .plainText,
        '正文',
      );
    });

    test('records render plan creation diagnostics', () {
      final recorder = InMemoryThreadDetailDiagnosticRecorder(enabled: true);
      final planner = ThreadDetailRenderEntryPlanner(
        diagnosticRecorder: recorder,
      );
      final post = ThreadPost(
        pid: 'p-diagnostic',
        author: 'alice',
        authorId: '1',
        message: '<p>正文</p>',
        number: 1,
        isFirst: true,
        dateline: 'today',
      );

      planner.planFor(post);
      planner.planFor(post);

      final events = recorder.snapshot();
      expect(
        events.where(
          (event) =>
              event.type == ThreadDetailDiagnosticEventType.renderPlanCreate,
        ),
        hasLength(1),
      );
      expect(events.single.pid, 'p-diagnostic');
    });
  });
}

class _CountingThreadPostBodyParser extends ThreadPostBodyParser {
  var parseCount = 0;

  @override
  ThreadPostBodyDocument parse(String html) {
    parseCount += 1;
    return super.parse(html);
  }
}

String _replaceBodyText(String text) {
  return text.replaceAll('正文', '显示正文');
}
