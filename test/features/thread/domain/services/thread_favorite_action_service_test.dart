import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';
import 'package:y300/features/thread/domain/services/thread_favorite_action_service.dart';

import '../../../../support/favorite_command_test_support.dart';

void main() {
  group('DefaultThreadFavoriteActionService', () {
    test('confirms favorite before refreshing the local module', () async {
      final command = FakeFavoriteThreadCommand();
      var refreshCalled = false;
      final reasons = <String>[];
      final service = DefaultThreadFavoriteActionService(
        command: command,
        refreshFavoriteModule: ({required String tid}) async {
          refreshCalled = true;
          expect(tid, '570617');
        },
        notifyFavoriteModule: ({required String reason, required String tid}) {
          reasons.add(reason);
        },
      );

      final result = await service.favoriteThread(tid: '570617');

      expect(result, isA<DataCommandApplied<ThreadFavoriteActionResult>>());
      expect(
        (result as DataCommandApplied<ThreadFavoriteActionResult>)
            .receipt
            .refreshedFavoriteModule,
        isTrue,
      );
      expect(command.requests.single.tid, '570617');
      expect(
        command.requests.single.targetState,
        FavoriteTargetState.favorited,
      );
      expect(refreshCalled, isTrue);
      expect(reasons, <String>['thread_favorite_added']);
    });

    test('keeps confirmed remote success when local refresh fails', () async {
      final command = FakeFavoriteThreadCommand();
      final reasons = <String>[];
      final service = DefaultThreadFavoriteActionService(
        command: command,
        refreshFavoriteModule: ({required String tid}) async {
          throw StateError('fixture sync failure');
        },
        notifyFavoriteModule: ({required String reason, required String tid}) {
          reasons.add(reason);
        },
      );

      final result = await service.favoriteThread(tid: '570617');

      expect(result, isA<DataCommandApplied<ThreadFavoriteActionResult>>());
      expect(
        (result as DataCommandApplied<ThreadFavoriteActionResult>)
            .receipt
            .refreshedFavoriteModule,
        isFalse,
      );
      expect(reasons, <String>['thread_favorite_added_sync_failed']);
    });

    test(
      'does not touch local state when remote state is unconfirmed',
      () async {
        final command = FakeFavoriteThreadCommand(
          handler: (_) async =>
              DataCommandOutcomeUnknown<ThreadFavoriteReceipt>(
                fixtureFavoriteFailure(),
              ),
        );
        var refreshCalled = false;
        final reasons = <String>[];
        final service = DefaultThreadFavoriteActionService(
          command: command,
          refreshFavoriteModule: ({required String tid}) async {
            refreshCalled = true;
          },
          notifyFavoriteModule:
              ({required String reason, required String tid}) {
                reasons.add(reason);
              },
        );

        final result = await service.favoriteThread(tid: '570617');

        expect(
          result,
          isA<DataCommandOutcomeUnknown<ThreadFavoriteActionResult>>(),
        );
        expect(refreshCalled, isFalse);
        expect(reasons, isEmpty);
      },
    );
  });
}
