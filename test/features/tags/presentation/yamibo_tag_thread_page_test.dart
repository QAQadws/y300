import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/tags/data/repositories/yamibo_tag_thread_page_repository.dart';
import 'package:y300/features/tags/domain/models/yamibo_tag_thread_page.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page.dart';

void main() {
  testWidgets('renders native tag thread page and opens next page', (
    tester,
  ) async {
    final repository = _FakeTagThreadPageRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yamiboTagThreadPageRepositoryProvider.overrideWithValue(repository),
        ],
        child: const LocalizedTestApp(
          home: YamiboTagThreadPage(
            url:
                'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const Key('yamibo-tag-thread-page')), findsOneWidget);
    expect(find.text('きさらぎ壱吾短篇集'), findsWidgets);
    expect(find.byKey(const Key('yamibo-tag-header-card')), findsOneWidget);
    expect(find.byKey(const Key('yamibo-tag-thread-572514')), findsOneWidget);
    expect(find.text('【个人汉化】[きさらぎ壱吾]晒猫'), findsOneWidget);
    expect(find.text('中文百合漫画区'), findsOneWidget);
    expect(find.text('回复 14 · 查看 3092'), findsOneWidget);

    await tester.tap(find.byKey(const Key('yamibo-tag-next-page-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(repository.requestedUrls.last, contains('page=2'));
    expect(find.byKey(const Key('yamibo-tag-thread-572515')), findsOneWidget);
  });

  testWidgets('localizes Traditional Chinese metrics and preserves raw data', (
    tester,
  ) async {
    final repository = _FakeTagThreadPageRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yamiboTagThreadPageRepositoryProvider.overrideWithValue(repository),
        ],
        child: const LocalizedTestApp(
          locale: Locale('zh', 'TW'),
          home: YamiboTagThreadPage(
            url:
                'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('回覆 14 · 瀏覽 3092'), findsOneWidget);
    expect(find.text('【个人汉化】[きさらぎ壱吾]晒猫'), findsOneWidget);
  });
}

class _FakeTagThreadPageRepository implements YamiboTagThreadPageRepository {
  final List<String> requestedUrls = <String>[];

  @override
  Future<ApiResult<YamiboTagThreadPageData>> load(String url) async {
    requestedUrls.add(url);
    final isPageTwo = Uri.tryParse(url)?.queryParameters['page'] == '2';
    return ApiSuccess<YamiboTagThreadPageData>(
      YamiboTagThreadPageData(
        url: url,
        tagId: '21920',
        tagName: 'きさらぎ壱吾短篇集',
        pagination: YamiboTagPagePagination(
          currentPage: isPageTwo ? 2 : 1,
          totalPages: 2,
          nextPageUrl: isPageTwo
              ? null
              : 'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=2',
          previousPageUrl: isPageTwo
              ? 'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1'
              : null,
        ),
        threads: <YamiboTagThreadItem>[
          YamiboTagThreadItem(
            tid: isPageTwo ? '572515' : '572514',
            threadUrl:
                'https://bbs.yamibo.com/thread-${isPageTwo ? '572515' : '572514'}-1-1.html',
            subject: isPageTwo ? '【个人汉化】[きさらぎ壱吾]传闻中的二人' : '【个人汉化】[きさらぎ壱吾]晒猫',
            forumName: '中文百合漫画区',
            forumId: '30',
            authorName: '2440760273',
            createdAt: '2026-6-15',
            replyCount: isPageTwo ? 13 : 14,
            viewCount: isPageTwo ? 3523 : 3092,
            lastPosterName: 'hyrami',
            lastPostAt: '2026-6-18 20:55',
            hasImageAttachment: true,
          ),
        ],
      ),
    );
  }
}
