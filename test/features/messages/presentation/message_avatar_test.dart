import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/image_loading/data/app_image_providers.dart';
import 'package:y300/features/image_loading/data/app_image_cache_manager.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/presentation/message_center_page.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/private_conversation_page.dart';
import 'package:y300/features/messages/presentation/widgets/message_avatar.dart';
import 'package:y300/features/messages/presentation/widgets/message_surface.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

import '../../../test_support/localized_test_app.dart';
import '../support/message_avatar_test_cache.dart';
import '../support/message_test_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> show(
    WidgetTester tester,
    MessageAvatarTestCache cache,
    Widget page, {
    MessageTestRepository? repository,
  }) async {
    final container = ProviderContainer.test(
      overrides: [
        imageCacheServiceProvider.overrideWithValue(cache),
        appImageCacheManagerProvider.overrideWith(
          (ref) async => CacheManagerAppImageCacheManager(cache.network),
        ),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
        messageAccountIdProvider.overrideWithValue('10'),
        if (repository != null)
          messageRepositoryProvider.overrideWithValue(repository),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(theme: AppTheme.light(), home: page),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets(
    'personal avatar uses a real cached frame and public profile ownership',
    (tester) async {
      final cache = await MessageAvatarTestCache.create(tester);
      await show(
        tester,
        cache,
        const Scaffold(
          body: MessageAvatar(
            userId: '20',
            imageUrl: MessageAvatarTestCache.aliceUrl,
          ),
        ),
      );
      await settleMessageAvatarImages(tester);
      final request = tester
          .widget<CachedLibraryImage>(find.byType(CachedLibraryImage).first)
          .request!;
      expect(request.ownerType, ImageCacheOwnerType.profile);
      expect(request.ownerId, '20');
      expect(request.role, ImageCacheRole.avatar);
      expect(request.referer, 'https://bbs.yamibo.com/');
      expect(request.cacheKey, isNot(contains('private:')));
      expect(cache.writes, isEmpty);
      expect(tester.getSize(find.byType(MessageAvatar)), const Size.square(40));
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
        isTrue,
      );
    },
  );

  testWidgets('site icons and known default are local with no cache reads', (
    tester,
  ) async {
    final cache = await MessageAvatarTestCache.create(tester);
    await show(
      tester,
      cache,
      const Scaffold(
        body: Row(
          children: [
            MessageAvatar(kind: MessageAvatarKind.group),
            MessageAvatar(kind: MessageAvatarKind.system),
            MessageAvatar(
              userId: '20',
              imageUrl: 'https://bbs.yamibo.com/uc/data/avatar/noavatar.svg',
            ),
          ],
        ),
      ),
    );
    await settleMessageAvatarImages(tester);
    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((image) => image.assetName);
    expect(
      assets,
      containsAll([
        MessageAvatar.groupAsset,
        MessageAvatar.systemAsset,
        forumDefaultAvatarAsset,
      ]),
    );
    expect(cache.reads, isEmpty);
    expect(cache.writes, isEmpty);
  });

  testWidgets('directory uses the peer avatar and keeps whole-row navigation', (
    tester,
  ) async {
    final cache = await MessageAvatarTestCache.create(tester);
    final repository = MessageTestRepository();
    final targets = <ForumConversationTarget>[];
    await show(
      tester,
      cache,
      MessageCenterPage(
        onOpenConversation: (_, target, _) => targets.add(target),
        onOpenLink: _ignoreLink,
        onOpenUser: (_, _) {},
      ),
      repository: repository,
    );
    repository.reads.single.result.complete(
      messageTestPage([
        messageTestItem(
          '1',
          sender: '10',
          senderAvatarUrl: MessageAvatarTestCache.meUrl,
          recipientAvatarUrl: MessageAvatarTestCache.aliceUrl,
        ),
      ]),
    );
    await tester.pumpAndSettle();
    final avatar = tester.widget<ForumCachedAvatar>(
      find.byType(ForumCachedAvatar),
    );
    expect(avatar.ownerId, '20');
    expect(avatar.imageUrl, MessageAvatarTestCache.aliceUrl);
    await tester.tap(find.byType(MessageAvatar));
    expect(targets, [const ForumConversationTarget.direct('20')]);
    expect(repository.notificationReads, isEmpty);
  });

  testWidgets(
    'failed avatar falls back locally without changing its geometry',
    (tester) async {
      final cache = (await MessageAvatarTestCache.create(tester))
        ..entries.clear();
      await show(
        tester,
        cache,
        const Scaffold(
          body: MessageAvatar(
            userId: '20',
            imageUrl: MessageAvatarTestCache.aliceUrl,
          ),
        ),
      );
      final before = tester.getRect(find.byType(MessageAvatar));
      await settleMessageAvatarImages(tester);
      expect(tester.getRect(find.byType(MessageAvatar)), before);
      expect(cache.writes, hasLength(1));
      expect(cache.network.reads, 1);
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .any(
              (image) =>
                  image.image is AssetImage &&
                  (image.image as AssetImage).assetName ==
                      forumDefaultAvatarAsset,
            ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending and late avatar frames do not block messages or move history',
    (tester) async {
      final cache = (await MessageAvatarTestCache.create(tester))
        ..blocked = true;
      final repository = MessageTestRepository();
      await show(
        tester,
        cache,
        const PrivateConversationPage(
          target: ForumConversationTarget.direct('20'),
          onOpenLink: _ignoreLink,
        ),
        repository: repository,
      );
      repository.reads.single.result.complete(
        messageTestPage(
          [
            for (var i = 1; i <= 16; i++)
              messageTestItem(
                '$i',
                sender: i.isEven ? '10' : '20',
                senderAvatarUrl: i.isEven
                    ? MessageAvatarTestCache.meUrl
                    : MessageAvatarTestCache.aliceUrl,
              ),
          ],
          count: 32,
          page: 2,
          perPage: 16,
        ),
      );
      await tester.pumpAndSettle();
      expect(cache.pending, isNotEmpty);
      expect(find.byType(MessageSurface), findsWidgets);
      for (final avatar in tester.widgetList<MessageAvatar>(
        find.byType(MessageAvatar),
      )) {
        final avatarFinder = find.byWidget(avatar);
        final row = find
            .ancestor(of: avatarFinder, matching: find.byType(Row))
            .first;
        final bubble = find.descendant(
          of: row,
          matching: find.byType(MessageSurface),
        );
        final avatarRect = tester.getRect(avatarFinder);
        final bubbleRect = tester.getRect(bubble);
        expect(avatarRect.size, const Size.square(36));
        expect(
          avatar.userId == '10'
              ? avatarRect.left - bubbleRect.right
              : bubbleRect.left - avatarRect.right,
          8,
        );
      }
      await tester.drag(
        find.byKey(const Key('private-conversation-list')),
        const Offset(0, 280),
      );
      await tester.pumpAndSettle();
      final list = tester.widget<CustomScrollView>(
        find.byKey(const Key('private-conversation-list')),
      );
      final offset = list.controller!.offset;
      final cards = find
          .byType(MessageSurface)
          .evaluate()
          .map((element) => element.widget)
          .toList();
      final positions = [
        for (final card in cards) tester.getRect(find.byWidget(card)),
      ];
      cache.release();
      await settleMessageAvatarImages(tester);
      expect(list.controller!.offset, closeTo(offset, .01));
      for (var i = 0; i < cards.length; i++) {
        expect(tester.getRect(find.byWidget(cards[i])), positions[i]);
      }
      expect(repository.reads, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account changes remove pending avatars before late completion', (
    tester,
  ) async {
    final cache = (await MessageAvatarTestCache.create(tester))..blocked = true;
    final repository = MessageTestRepository();
    final container = await show(
      tester,
      cache,
      const PrivateConversationPage(
        target: ForumConversationTarget.direct('20'),
        onOpenLink: _ignoreLink,
      ),
      repository: repository,
    );
    repository.reads.single.result.complete(
      messageTestPage([
        messageTestItem('1', senderAvatarUrl: MessageAvatarTestCache.aliceUrl),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ForumCachedAvatar), findsOneWidget);
    container.updateOverrides([
      imageCacheServiceProvider.overrideWithValue(cache),
      appImageCacheManagerProvider.overrideWith(
        (ref) async => CacheManagerAppImageCacheManager(cache.network),
      ),
      forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      messageAccountIdProvider.overrideWithValue(null),
      messageRepositoryProvider.overrideWithValue(repository),
    ]);
    await tester.pumpAndSettle();
    cache.release();
    await tester.pumpAndSettle();
    expect(find.byType(ForumCachedAvatar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'notification avatar opens the author with a 48 pixel tap target',
    (tester) async {
      final cache = await MessageAvatarTestCache.create(tester);
      final repository = MessageTestRepository();
      final users = <String>[];
      await show(
        tester,
        cache,
        MessageCenterPage(
          initialTab: MessageCenterTab.notifications,
          onOpenConversation: (_, _, _) {},
          onOpenLink: _ignoreLink,
          onOpenUser: (_, user) => users.add(user),
        ),
        repository: repository,
      );
      repository.notificationReads.single.result.complete(
        notificationTestPage([
          notificationTestItem('1', avatarUrl: MessageAvatarTestCache.aliceUrl),
          notificationTestItem('2', authorId: '0'),
        ]),
      );
      await tester.pumpAndSettle();
      final avatar = find.byKey(const ValueKey('notification-avatar:1'));
      expect(tester.getSize(avatar), const Size.square(48));
      await tester.tap(avatar);
      expect(users, ['20']);
      expect(find.byKey(const ValueKey('notification-avatar:2')), findsNothing);
      expect(repository.reads, isEmpty);
    },
  );
}

void _ignoreLink(BuildContext context, String url) {}
