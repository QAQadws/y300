import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/forum/data/services/forum_favorite_action_service.dart';

import '../../../support/favorite_command_test_support.dart';

void main() {
  group('ForumFavoriteActionService', () {
    test('maps favorite action to the source-neutral target state', () async {
      final command = FakeFavoriteForumCommand();
      final service = ForumFavoriteActionService(command: command);

      final result = await service.apply(
        fid: ' 33 ',
        action: ForumDisplayFavoriteAction.favorite,
      );

      expect(result, isA<DataCommandApplied<ForumFavoriteReceipt>>());
      expect(command.requests, hasLength(1));
      expect(command.requests.single.fid, '33');
      expect(
        command.requests.single.targetState,
        FavoriteTargetState.favorited,
      );
    });

    test('maps unfavorite action to the source-neutral target state', () async {
      final command = FakeFavoriteForumCommand();
      final service = ForumFavoriteActionService(command: command);

      final result = await service.apply(
        fid: '33',
        action: ForumDisplayFavoriteAction.unfavorite,
      );

      expect(result, isA<DataCommandApplied<ForumFavoriteReceipt>>());
      expect(
        command.requests.single.targetState,
        FavoriteTargetState.unfavorited,
      );
    });

    test('fails closed before command when target is invalid', () async {
      final command = FakeFavoriteForumCommand();
      final service = ForumFavoriteActionService(command: command);

      final result = await service.apply(
        fid: '33',
        action: ForumDisplayFavoriteAction.unknown,
      );

      expect(result, isA<DataCommandNotSent<ForumFavoriteReceipt>>());
      expect(command.requests, isEmpty);
    });

    test('preserves structured command failure', () async {
      final failure = fixtureFavoriteFailure(
        kind: DataCommandFailureKind.unauthenticated,
      );
      final command = FakeFavoriteForumCommand(
        handler: (_) async =>
            DataCommandRejected<ForumFavoriteReceipt>(failure),
      );
      final service = ForumFavoriteActionService(command: command);

      final result = await service.apply(
        fid: '33',
        action: ForumDisplayFavoriteAction.favorite,
      );

      expect(result, isA<DataCommandRejected<ForumFavoriteReceipt>>());
      expect(result.failureOrNull, same(failure));
    });
  });
}
