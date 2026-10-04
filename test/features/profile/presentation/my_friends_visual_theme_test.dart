import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/data/providers/friend_read_providers.dart';
import 'package:y300/features/profile/presentation/friends/my_friends_page.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/friend_read_fixture.dart';

const _output = String.fromEnvironment('FRIENDS_VISUAL_OUTPUT');
const _font = String.fromEnvironment('FRIENDS_VISUAL_FONT');
const _capture = Key('my-friends-visual-capture');

void main() {
  setUpAll(() async {
    if (_output.isEmpty) return;
    if (_font.isNotEmpty) {
      await (FontLoader(
        'FriendsVisual',
      )..addFont(File(_font).readAsBytes().then(ByteData.sublistView))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      for (final compact in [false, true]) {
        final name =
            '${family.name}-${brightness.name}-${compact ? 'large' : 'normal'}';
        testWidgets('$name friend page preview', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(compact ? 300 : 390, 844);
          addTearDown(tester.view.reset);
          final repository = FriendFeedFixture(autoComplete: true)
            ..items = [
              friendFeedItem(
                '202',
                username: '一位名字很长很长的好友',
                note: '雨后的空气很清新，在街角读了一会儿书。',
                isOnline: true,
              ),
              friendFeedItem(
                '303',
                username: 'Yamibo 读者',
                note: '最近重读了一部喜欢的漫画。',
              ),
              friendFeedItem('404', username: '晨光', note: '记录生活中值得记住的小事。'),
            ];
          final theme = AppTheme.build(family: family, brightness: brightness);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                verifiedSessionOwnerProvider.overrideWithValue((
                  uid: '101',
                  revision: 0,
                )),
                friendFeedRepositoryProvider.overrideWithValue(repository),
                friendRemovalCommandProvider.overrideWithValue(
                  FriendRemovalFixture(),
                ),
                forumImageRefererProvider.overrideWithValue(
                  'https://example.test/',
                ),
              ],
              child: RepaintBoundary(
                key: _capture,
                child: LocalizedTestApp(
                  debugShowCheckedModeBanner: false,
                  theme: _font.isEmpty
                      ? theme
                      : theme.copyWith(
                          textTheme: theme.textTheme.apply(
                            fontFamily: 'FriendsVisual',
                          ),
                        ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(compact ? 1.8 : 1),
                    ),
                    child: child!,
                  ),
                  home: MyFriendsPage(
                    onOpenLink: (_, _) {},
                    onOpenConversation: (_, _, _) {},
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(
            () => precacheImage(
              const AssetImage(forumDefaultAvatarAsset),
              tester.element(find.byType(Scaffold)),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _save(tester, name);
          final card = tester.getRect(
            find.byKey(const Key('my-friends-user-202')),
          );
          await tester.longPressAt(Offset(card.right - 5, card.center.dy));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('my-friends-actions-sheet')),
            findsOneWidget,
          );
          await _save(tester, '$name-actions');
          if (brightness == Brightness.light && !compact) {
            Navigator.of(
              tester.element(find.byKey(const Key('my-friends-actions-sheet'))),
            ).pop();
            await tester.pumpAndSettle();
            repository
              ..totalPages = null
              ..items = repository.items
                  .map(
                    (item) => friendFeedItem(
                      item.userId,
                      username: item.username,
                      profileUrl: item.profileUrl,
                      note: item.note,
                      isOnline: true,
                      canRemove: false,
                    ),
                  )
                  .toList();
            final l10n = AppLocalizations.of(
              tester.element(find.byType(MyFriendsPage)),
            );
            await tester.tap(find.text(l10n.profileFriendsOnlineTab));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await _save(tester, '$name-online');
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }, skip: _output.isEmpty);
      }
    }
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = await Directory(_output).create(recursive: true);
      await File(
        '${output.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
