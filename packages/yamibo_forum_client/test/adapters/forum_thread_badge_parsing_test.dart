import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/adapters/forum_display_api_mapper.dart';
import 'package:yamibo_forum_client/src/adapters/forum_display_html_parser.dart';
import 'package:yamibo_forum_client/src/adapters/forum_display_snapshot_codec.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  final parser = ForumDisplayHtmlParser(
    siteOrigin: Uri.parse('https://example.test'),
  );

  test(
    'HTML retains every independent marker without mixing it into the title',
    () {
      final item = parser
          .parse(
            _forumHtml('''
<span class="micon">投票</span><span class="micon">图</span>
<span class="micon top">置顶</span><span class="micon digest">精华</span>
<span class="micon">Custom marker</span><em>Title &amp; punctuation</em>
'''),
            fallbackFid: '30',
            fallbackPage: 1,
          )
          .threads
          .single;

      expect(item.subject, 'Title & punctuation');
      expect(item.badgeLabel, '投票');
      expect(item.badges.map((badge) => badge.kind), [
        ForumThreadBadgeKind.poll,
        ForumThreadBadgeKind.image,
        ForumThreadBadgeKind.sticky,
        ForumThreadBadgeKind.digest,
        ForumThreadBadgeKind.unknown,
      ]);
      expect(item.badges.map((badge) => badge.sourceLabel), [
        '投票',
        '图',
        '置顶',
        '精华',
        'Custom marker',
      ]);
      expect(
        item.copyWith(subject: 'Translated title').badges,
        same(item.badges),
      );
    },
  );

  test(
    'lock class overrides an unknown label and keeps sticky/digest markers',
    () {
      final item = parser
          .parse(
            _forumHtml('''
<span class="micon lock">Source closure text</span>
<span class="micon top">Pinned source text</span>
<span class="micon digest">Digest source text</span><em>Title</em>
'''),
            fallbackFid: '30',
            fallbackPage: 1,
          )
          .threads
          .single;

      expect(item.isLocked, isTrue);
      expect(item.badges.map((badge) => badge.kind), [
        ForumThreadBadgeKind.closed,
        ForumThreadBadgeKind.sticky,
        ForumThreadBadgeKind.digest,
      ]);
      expect(item.badges.first.sourceLabel, 'Source closure text');
    },
  );

  test('title fallback removes marker nodes without stripping title words', () {
    final item = parser
        .parse(
          _forumHtml('''
<span class="micon">Poll</span><span class="micon top">Pinned</span>
Poll is part of this title
'''),
          fallbackFid: '30',
          fallbackPage: 1,
        )
        .threads
        .single;

    expect(item.subject, 'Poll is part of this title');
    expect(item.badges, hasLength(2));
  });

  test('API special topics retain image, sticky, and digest independently', () {
    final item = _apiThread({
      'special': '1',
      'attachment': '2',
      'displayorder': '3',
      'digest': '2',
    });

    expect(item.badges.map((badge) => badge.kind), [
      ForumThreadBadgeKind.poll,
      ForumThreadBadgeKind.image,
      ForumThreadBadgeKind.sticky,
      ForumThreadBadgeKind.digest,
    ]);
    expect(item.badges.every((badge) => badge.sourceLabel.isEmpty), isTrue);
  });

  for (final closed in ['0', '2', '100']) {
    test(
      'API closed=$closed does not turn redirect threads into closed topics',
      () {
        final item = _apiThread({'closed': closed, 'special': '1'});
        expect(item.isLocked, isFalse);
        expect(item.badges.single.kind, ForumThreadBadgeKind.poll);
      },
    );
  }

  for (final fields in [
    <String, Object?>{'closed': '1'},
    <String, Object?>{'closed': true},
    <String, Object?>{'folder': 'lock'},
  ]) {
    test(
      'API closure evidence $fields retains the independent sticky marker',
      () {
        final item = _apiThread({
          ...fields,
          'displayorder': '1',
          'digest': '1',
        });
        expect(item.isLocked, isTrue);
        expect(item.badges.map((badge) => badge.kind), [
          ForumThreadBadgeKind.closed,
          ForumThreadBadgeKind.sticky,
          ForumThreadBadgeKind.digest,
        ]);
      },
    );
  }

  test(
    'API redirect evidence overrides folder lock and retains a special topic',
    () {
      final item = _apiThread({
        'closed': '100',
        'folder': 'lock',
        'special': '1',
      });
      expect(item.isLocked, isFalse);
      expect(item.badges.single.kind, ForumThreadBadgeKind.poll);
    },
  );

  test(
    'legacy source labels remain typed and unknown marker text is preserved',
    () {
      expect(
        _summary(badgeLabel: '投票').effectiveBadges.single.kind,
        ForumThreadBadgeKind.poll,
      );
      final unknown = _summary(
        badgeLabel: 'Custom marker',
      ).effectiveBadges.single;
      expect(unknown.kind, ForumThreadBadgeKind.unknown);
      expect(unknown.sourceLabel, 'Custom marker');
      expect(
        _summary(
          badgeLabel: '投票',
          isLocked: true,
        ).effectiveBadges.map((badge) => badge.kind),
        [ForumThreadBadgeKind.closed, ForumThreadBadgeKind.poll],
      );
      final typed = _summary(
        badgeLabel: 'Legacy marker',
        badges: const [
          ForumThreadBadge(
            kind: ForumThreadBadgeKind.digest,
            sourceLabel: '精华',
          ),
        ],
      );
      expect(typed.effectiveBadges, same(typed.badges));
    },
  );

  test(
    'snapshot round trip retains independent marker kinds and original labels',
    () {
      const codec = ForumDisplaySnapshotCodec();
      final data = parser.parse(
        _forumHtml(
          '<span class="micon top">置顶</span><span class="micon digest">精华</span><em>Title</em>',
        ),
        fallbackFid: '30',
        fallbackPage: 1,
      );
      final restored = codec.decode(codec.encode(data)).threads.single;

      expect(restored.badges.map((badge) => badge.kind), [
        ForumThreadBadgeKind.sticky,
        ForumThreadBadgeKind.digest,
      ]);
      expect(restored.badges.map((badge) => badge.sourceLabel), ['置顶', '精华']);
      expect(
        codec.canDecodeVersion(codecVersion: 1, parserVersion: 1),
        isFalse,
      );
      expect(codec.canDecodeVersion(codecVersion: 2, parserVersion: 2), isTrue);
    },
  );

  test('incompatible old snapshots fall back to reparsed cached HTML', () async {
    final documents = MemoryForumDocumentStore();
    final snapshots = MemoryForumSnapshotStore();
    final network = _UnavailableNetwork();
    final origin = Uri.parse('https://example.test');
    final config = ForumClientConfig(siteOrigin: origin, userAgent: 'test');
    final keys = ForumCacheKeyCanonicalizer(siteOrigin: origin);
    const query = ForumDisplayQuery(fid: '30');
    const profile = ForumDocumentRequestProfile.anonymous;
    final parameters = query.toRequestParameters();
    final descriptor = keys.forumDisplay(
      fid: '30',
      page: 1,
      queryParameters: parameters,
      requestProfile: profile,
    );
    final snapshotDescriptor = keys.forumDisplaySnapshot(
      fid: '30',
      page: 1,
      queryParameters: parameters,
      requestProfile: profile,
    );
    final now = DateTime.now();
    await documents.put(
      ForumCachedDocument(
        descriptor: descriptor,
        body: _forumHtml(
          '<span class="micon">投票</span><span class="micon digest">精华</span><em>Title</em>',
        ),
        fetchedAt: now,
        updatedAt: now,
      ),
    );
    await snapshots.put(
      snapshotDescriptor,
      ForumDisplayData(
        fid: '30',
        forumName: 'Forum',
        currentPage: 1,
        perPage: 20,
        totalThreads: 1,
        threads: [_summary(badgeLabel: '投票')],
      ),
      const _LegacySnapshotCodec(),
      policy: const ForumSnapshotPolicy(
        freshFor: Duration(days: 1),
        keepStaleFor: Duration(days: 2),
      ),
    );

    final result = await ForumClientAdapterFactory(
      config: config,
      network: network,
      documentStore: documents,
      snapshotStore: snapshots,
    ).createHtmlForumDisplay().getForumDisplayByQuery(query);

    expect(network.reads, 1);
    expect(
      (result
              as DataReadSuccess<
                ForumDisplayData,
                ForumDisplayReadCapabilities
              >)
          .metadata
          .origin,
      DataReadOrigin.cachedDocumentFallback,
    );
    expect(
      result.dataOrNull!.threads.single.badges.map((badge) => badge.kind),
      [ForumThreadBadgeKind.poll, ForumThreadBadgeKind.digest],
    );
    final refreshed = await snapshots.get(
      snapshotDescriptor,
      const ForumDisplaySnapshotCodec(),
    );
    expect(refreshed!.parserVersion, 2);
    expect(refreshed.value.threads.single.badges, hasLength(2));
  });
}

String _forumHtml(String heading) =>
    '''
<html><body><div class="threadlist"><ul><li class="list">
<a href="forum.php?mod=viewthread&amp;tid=42"><div class="threadlist_tit">$heading</div></a>
</li></ul></div></body></html>
''';

ForumThreadSummary _apiThread(Map<String, Object?> fields) =>
    const ForumDisplayApiMapper()
        .mapVariables({
          'fid': '30',
          'forum_threadlist': [
            {'tid': '42', ...fields},
          ],
        }, page: 1)
        .threads
        .single;

ForumThreadSummary _summary({
  String? badgeLabel,
  bool isLocked = false,
  List<ForumThreadBadge> badges = const [],
}) => ForumThreadSummary(
  tid: '42',
  subject: 'Title',
  author: '',
  replies: 0,
  views: 0,
  dateline: '',
  badgeLabel: badgeLabel,
  isLocked: isLocked,
  badges: badges,
);

class _LegacySnapshotCodec extends ForumDisplaySnapshotCodec {
  const _LegacySnapshotCodec();
  @override
  int get codecVersion => 1;
  @override
  int get parserVersion => 1;
}

class _UnavailableNetwork implements ForumClientNetwork {
  int reads = 0;
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    reads++;
    return const ForumTransportError(
      ForumTransportFailure(
        kind: ForumTransportFailureKind.network,
        code: 'offline',
      ),
    );
  }
}
