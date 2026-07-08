import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';

/// 回归防护：收藏同步 / 漫画发现必须走 JSON（[ApiThreadRepository]），
/// 阅读页才走 HTML-first（[ThreadDetailHtmlRepository]）。
///
/// 根因回顾：`5f886aac` 把共享的 [threadRepositoryProvider] 从 JSON 翻成移动端
/// HTML，移动端 HTML 没有 `typeid`，导致收藏入队策略与 tagName 反查全部失效。
/// 修复方式是新增 [threadJsonRepositoryProvider] 让同步/发现回到 JSON。
/// 本测试锁定这一分工，防止再次被 HTML 数据源顶替。
void main() {
  test('threadJsonRepositoryProvider resolves to JSON ApiThreadRepository', () {
    final container = ProviderContainer(
      overrides: [
        // 用纯 Dart 构造的 ApiClient 覆盖，避免拉起 WAF / 平台通道；
        // 构造期不发起任何网络请求。
        apiClientProvider.overrideWithValue(
          ApiClient(cookieStore: CookieStore(), logger: Logger()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final repository = container.read(threadJsonRepositoryProvider);

    expect(
      repository,
      isA<ApiThreadRepository>(),
      reason: '同步/发现必须走 JSON viewthread（带 typeid），不能退回 HTML。',
    );
  });
}
