import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';
import 'package:y300/features/favorites/domain/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/forum/presentation/widgets/forum_favorite_forum_picker.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('renders a compact flat list without technical fid labels', (
    tester,
  ) async {
    final removedFavids = <String>[];
    var didSucceed = false;

    await tester.pumpWidget(
      LocalizedTestApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => ForumFavoriteForumPicker(
                      loadFavoriteForums: () async => DataReadSuccess(
                        data: FavoriteForumDirectoryData(
                          items: [
                            _forum(
                              remoteFavoriteId: 'fav-16',
                              fid: '16',
                              title: '管理版',
                              description: '论坛管理与公告',
                            ),
                            _forum(
                              remoteFavoriteId: 'fav-30',
                              fid: '30',
                              title: '中文百合漫画区',
                            ),
                          ],
                        ),
                        capabilities: _supportedCapabilities,
                        metadata: const DataReadMetadata.network(),
                      ),
                      onUnfavorite: (forum) async {
                        removedFavids.add(forum.remoteFavoriteId!);
                        return const ApiSuccess(ForumFavoriteMutationResult());
                      },
                      onSuccess: (_, _) {
                        didSucceed = true;
                      },
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final picker = find.byKey(const Key('forum-favorite-forum-picker'));
    expect(picker, findsOneWidget);
    expect(tester.getSize(picker).height, lessThan(360));
    expect(find.text('取消收藏'), findsOneWidget);
    expect(find.text('我收藏的版块'), findsNothing);
    expect(find.text('fid=16'), findsNothing);
    expect(find.text('论坛管理与公告'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.byIcon(Icons.remove_circle_outline_rounded), findsNWidgets(2));

    final material = tester.widget<Material>(picker);
    expect(material.color, AppTheme.light().colorScheme.surface);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.color == AppTheme.light().colorScheme.surfaceContainerLow,
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('forum-favorite-forum-item-fav-16')));
    await tester.pumpAndSettle();

    expect(removedFavids, <String>['fav-16']);
    expect(didSucceed, isTrue);
    expect(picker, findsNothing);
  });

  testWidgets('disables removal without remote identity capability', (
    tester,
  ) async {
    var unfavoriteCallCount = 0;

    await tester.pumpWidget(
      LocalizedTestApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => ForumFavoriteForumPicker(
                      loadFavoriteForums: () async => DataReadSuccess(
                        data: FavoriteForumDirectoryData(
                          items: [
                            _forum(
                              remoteFavoriteId: 'fav-16',
                              fid: '16',
                              title: '管理版',
                            ),
                          ],
                        ),
                        capabilities: _unsupportedRemoteIdentityCapabilities,
                        metadata: const DataReadMetadata.network(),
                      ),
                      onUnfavorite: (_) async {
                        unfavoriteCallCount += 1;
                        return const ApiSuccess(ForumFavoriteMutationResult());
                      },
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final removeButton = tester.widget<IconButton>(
      find.byKey(const Key('forum-favorite-forum-remove-fav-16')),
    );
    expect(removeButton.onPressed, isNull);

    await tester.tap(
      find.byKey(const Key('forum-favorite-forum-item-fav-16')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(unfavoriteCallCount, 0);
    expect(
      find.byKey(const Key('forum-favorite-forum-picker')),
      findsOneWidget,
    );
  });
}

FavoriteForumEntry _forum({
  required String remoteFavoriteId,
  required String fid,
  required String title,
  String description = '',
}) {
  return FavoriteForumEntry(
    remoteFavoriteId: remoteFavoriteId,
    fid: fid,
    title: title,
    description: description,
  );
}

final _supportedCapabilities = FavoriteForumDirectoryReadCapabilities(
  values: DataCapabilitySet<FavoriteForumDirectoryCapability>.supported(
    FavoriteForumDirectoryCapability.values,
  ),
);

final _unsupportedRemoteIdentityCapabilities =
    FavoriteForumDirectoryReadCapabilities(
      values: DataCapabilitySet<FavoriteForumDirectoryCapability>.from(
        supported: FavoriteForumDirectoryCapability.values.where(
          (capability) =>
              capability !=
              FavoriteForumDirectoryCapability.stableRemoteFavoriteIdentity,
        ),
        unsupported: const <FavoriteForumDirectoryCapability>[
          FavoriteForumDirectoryCapability.stableRemoteFavoriteIdentity,
        ],
      ),
    );
