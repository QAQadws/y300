import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/library_task_notification_service_impl.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_client.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

void main() {
  group('FlutterLocalLibraryTaskNotificationService', () {
    test('maps notification keys to fixed Android ids', () {
      expect(
        FlutterLocalLibraryTaskNotificationService.notificationIdFor(
          LibraryTaskNotificationKey.favoriteSync,
        ),
        3001,
      );
      expect(
        FlutterLocalLibraryTaskNotificationService.notificationIdFor(
          LibraryTaskNotificationKey.comicSearchQueue,
        ),
        3002,
      );
    });

    test('initialize is idempotent', () async {
      final client = _FakeNotificationClient();
      final service =
          FlutterLocalLibraryTaskNotificationService(client: client);

      await service.initialize();
      await service.initialize();

      expect(client.initializeCalls, 1);
    });

    test('shows a determinate progress notification when total is provided',
        () async {
      final client = _FakeNotificationClient();
      final service =
          FlutterLocalLibraryTaskNotificationService(client: client);

      await service.showOrUpdate(
        const LibraryTaskNotification(
          key: LibraryTaskNotificationKey.favoriteSync,
          title: '收藏同步',
          body: '正在解析: 收藏帖',
          current: 3,
          total: 10,
        ),
      );

      final request = client.shownRequests.single;
      expect(request.id, 3001);
      expect(request.title, '收藏同步');
      expect(request.body, '正在解析: 收藏帖');
      expect(request.ongoing, isTrue);
      expect(request.showProgress, isTrue);
      expect(request.indeterminate, isFalse);
      expect(request.maxProgress, 10);
      expect(request.progress, 3);
    });

    test('shows an indeterminate progress notification without a total',
        () async {
      final client = _FakeNotificationClient();
      final service =
          FlutterLocalLibraryTaskNotificationService(client: client);

      await service.showOrUpdate(
        const LibraryTaskNotification(
          key: LibraryTaskNotificationKey.comicSearchQueue,
          title: '漫画搜索等待中',
          body: '《作品名》 · 预计 10.5s',
        ),
      );

      final request = client.shownRequests.single;
      expect(request.id, 3002);
      expect(request.showProgress, isTrue);
      expect(request.indeterminate, isTrue);
      expect(request.maxProgress, 0);
      expect(request.progress, 0);
    });

    test('treats a zero total as indeterminate', () async {
      final client = _FakeNotificationClient();
      final service =
          FlutterLocalLibraryTaskNotificationService(client: client);

      await service.showOrUpdate(
        const LibraryTaskNotification(
          key: LibraryTaskNotificationKey.favoriteSync,
          title: '收藏同步',
          body: '准备中',
          current: 0,
          total: 0,
        ),
      );

      expect(client.shownRequests.single.indeterminate, isTrue);
    });

    test('does not show and does not throw when permission is denied',
        () async {
      final client = _FakeNotificationClient(
        permission: LibraryTaskNotificationPermissionState.denied,
      );
      final service =
          FlutterLocalLibraryTaskNotificationService(client: client);

      await service.showOrUpdate(
        const LibraryTaskNotification(
          key: LibraryTaskNotificationKey.favoriteSync,
          title: '收藏同步',
          body: '正在解析',
        ),
      );

      expect(client.shownRequests, isEmpty);
    });

    test('caches a granted permission and only requests it once', () async {
      final client = _FakeNotificationClient();
      final service =
          FlutterLocalLibraryTaskNotificationService(client: client);

      await service.ensurePermission();
      await service.showOrUpdate(
        const LibraryTaskNotification(
          key: LibraryTaskNotificationKey.favoriteSync,
          title: '收藏同步',
          body: '正在解析',
        ),
      );

      expect(client.permissionRequests, 1);
    });

    test('clear cancels the matching notification id after initialize',
        () async {
      final client = _FakeNotificationClient();
      final service =
          FlutterLocalLibraryTaskNotificationService(client: client);

      await service.initialize();
      await service.clear(LibraryTaskNotificationKey.comicSearchQueue);

      expect(client.cancelledIds, <int>[3002]);
    });

    test('clear is a no-op before initialize', () async {
      final client = _FakeNotificationClient();
      final service =
          FlutterLocalLibraryTaskNotificationService(client: client);

      await service.clear(LibraryTaskNotificationKey.favoriteSync);

      expect(client.cancelledIds, isEmpty);
    });
  });
}

class _FakeNotificationClient implements LibraryTaskNotificationClient {
  _FakeNotificationClient({
    this.permission = LibraryTaskNotificationPermissionState.granted,
  });

  final LibraryTaskNotificationPermissionState permission;

  int initializeCalls = 0;
  int permissionRequests = 0;
  final List<LibraryTaskNotificationClientRequest> shownRequests =
      <LibraryTaskNotificationClientRequest>[];
  final List<int> cancelledIds = <int>[];

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<LibraryTaskNotificationPermissionState> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<void> show(LibraryTaskNotificationClientRequest request) async {
    shownRequests.add(request);
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
  }
}
