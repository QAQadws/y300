import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_notification_service.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_client.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

void main() {
  group('FlutterLocalComposerUploadNotificationService', () {
    test('showProgress posts deterministic upload notification', () async {
      final client = _FakeNotificationClient();
      final service = FlutterLocalComposerUploadNotificationService(
        client: client,
      );

      await service.showProgress(current: 2, total: 5);
      await service.showProgress(current: 3, total: 5);

      expect(client.initializeCallCount, 1);
      expect(client.permissionCallCount, 1);
      expect(client.requests.last.id, 3101);
      expect(client.requests.last.title, '正在上传回复图片');
      expect(client.requests.last.body, '第 3/5 张');
      expect(client.requests.last.ongoing, isTrue);
      expect(client.requests.last.maxProgress, 5);
      expect(client.requests.last.progress, 3);
    });

    test('clear cancels composer upload notification', () async {
      final client = _FakeNotificationClient();
      final service = FlutterLocalComposerUploadNotificationService(
        client: client,
      );

      await service.showProgress(current: 1, total: 1);
      await service.clear();

      expect(client.cancelledIds, [3101]);
    });

    test('showFailure posts failure and clears after delay', () async {
      final client = _FakeNotificationClient();
      final service = FlutterLocalComposerUploadNotificationService(
        client: client,
        failureClearDelay: Duration.zero,
      );

      await service.showFailure(failedCount: 1, total: 3);

      expect(client.requests.single.title, '回复图片上传失败');
      expect(client.requests.single.body, '有 1/3 张图片上传失败');
      expect(client.requests.single.ongoing, isFalse);
      expect(client.cancelledIds, [3101]);
    });

    test('notification client errors are swallowed', () async {
      final client = _FakeNotificationClient(throwOnShow: true);
      final service = FlutterLocalComposerUploadNotificationService(
        client: client,
        failureClearDelay: Duration.zero,
      );

      await service.showProgress(current: 1, total: 2);
      await service.showFailure(failedCount: 1, total: 2);
      await service.clear();

      expect(client.requests, isEmpty);
    });

    test('notification permission denial is swallowed', () async {
      final client = _FakeNotificationClient(
        permissionState: LibraryTaskNotificationPermissionState.denied,
      );
      final service = FlutterLocalComposerUploadNotificationService(
        client: client,
      );

      await service.showProgress(current: 1, total: 2);

      expect(client.permissionCallCount, 1);
      expect(client.requests, isEmpty);
    });
  });
}

class _FakeNotificationClient implements LibraryTaskNotificationClient {
  _FakeNotificationClient({
    this.permissionState = LibraryTaskNotificationPermissionState.granted,
    this.throwOnShow = false,
  });

  final LibraryTaskNotificationPermissionState permissionState;
  final bool throwOnShow;
  int initializeCallCount = 0;
  int permissionCallCount = 0;
  final List<LibraryTaskNotificationClientRequest> requests =
      <LibraryTaskNotificationClientRequest>[];
  final List<int> cancelledIds = <int>[];

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> initialize() async {
    initializeCallCount += 1;
  }

  @override
  Future<LibraryTaskNotificationPermissionState> requestPermission() async {
    permissionCallCount += 1;
    return permissionState;
  }

  @override
  Future<void> show(LibraryTaskNotificationClientRequest request) async {
    if (throwOnShow) {
      throw StateError('notification failed');
    }
    requests.add(request);
  }
}
