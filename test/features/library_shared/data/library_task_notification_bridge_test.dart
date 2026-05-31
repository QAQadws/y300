import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/library_task_notification_bridge_impl.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';

void main() {
  group('DefaultLibraryTaskNotificationBridge', () {
    late DefaultLibraryTaskProgressHub hub;
    late _FakeNotificationService service;
    late ValueNotifier<LibraryShelfTaskProgress?> favoriteSource;
    late ValueNotifier<LibraryShelfTaskProgress?> comicSource;
    late DefaultLibraryTaskNotificationBridge bridge;

    setUp(() {
      hub = DefaultLibraryTaskProgressHub();
      service = _FakeNotificationService();
      favoriteSource = ValueNotifier<LibraryShelfTaskProgress?>(null);
      comicSource = ValueNotifier<LibraryShelfTaskProgress?>(null);
      hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
        progress: favoriteSource,
      );
      hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
        progress: comicSource,
      );
      bridge = DefaultLibraryTaskNotificationBridge(
        hub: hub,
        notificationService: service,
      );
      bridge.start();
    });

    tearDown(() {
      bridge.dispose();
      favoriteSource.dispose();
      comicSource.dispose();
      hub.dispose();
    });

    test('favorite sync active shows favorite notification with progress', () {
      favoriteSource.value = const LibraryShelfTaskProgress(
        message: '正在解析: 收藏帖',
        current: 3,
        total: 10,
        source: LibraryMutationSource.favoriteSync,
      );

      expect(service.shown, hasLength(1));
      final notification = service.shown.single;
      expect(notification.key, LibraryTaskNotificationKey.favoriteSync);
      expect(notification.title, '收藏同步');
      expect(notification.body, '正在解析: 收藏帖');
      expect(notification.current, 3);
      expect(notification.total, 10);
    });

    test('favorite sync clearing to null clears favorite notification', () {
      favoriteSource.value = const LibraryShelfTaskProgress(
        message: '正在解析: 收藏帖',
        source: LibraryMutationSource.favoriteSync,
      );
      expect(service.shown, hasLength(1));

      favoriteSource.value = null;

      expect(service.cleared, <LibraryTaskNotificationKey>[
        LibraryTaskNotificationKey.favoriteSync,
      ]);
    });

    test('comic search queue active shows comic notification', () {
      comicSource.value = const LibraryShelfTaskProgress(
        message: '《作品名》正在等待漫画搜索 预计耗时10.5s',
        source: LibraryMutationSource.comicSearchQueue,
      );

      expect(service.shown, hasLength(1));
      final notification = service.shown.single;
      expect(notification.key, LibraryTaskNotificationKey.comicSearchQueue);
      expect(notification.title, '漫画搜索等待中');
      expect(notification.body, '《作品名》正在等待漫画搜索 预计耗时10.5s');
      // Queue waiting has no current/total, so it renders indeterminate.
      expect(notification.hasDeterminateProgress, isFalse);
    });

    test('hidden cover warmup progress does not produce a notification', () {
      // Cover warmup surfaces on the comic module but with a different source,
      // so the comic search-queue channel must ignore it.
      comicSource.value = const LibraryShelfTaskProgress(
        message: '预热封面',
        source: LibraryMutationSource.coverWarmup,
        visible: false,
      );

      expect(service.shown, isEmpty);
      expect(service.cleared, isEmpty);
    });

    test('unrelated favorite source progress does not notify', () {
      // Same module channel, but a thread favorite action rather than sync.
      favoriteSource.value = const LibraryShelfTaskProgress(
        message: '收藏中',
        source: LibraryMutationSource.threadFavoriteAction,
      );

      expect(service.shown, isEmpty);
    });

    test('repeated identical progress does not re-show', () {
      const progress = LibraryShelfTaskProgress(
        message: '正在解析: 收藏帖',
        current: 3,
        total: 10,
        source: LibraryMutationSource.favoriteSync,
      );
      favoriteSource.value = progress;
      favoriteSource.value = const LibraryShelfTaskProgress(
        message: '正在解析: 收藏帖',
        current: 3,
        total: 10,
        source: LibraryMutationSource.favoriteSync,
      );

      expect(service.shown, hasLength(1));
    });

    test('changed progress re-shows', () {
      favoriteSource.value = const LibraryShelfTaskProgress(
        message: '正在解析: 收藏帖',
        current: 3,
        total: 10,
        source: LibraryMutationSource.favoriteSync,
      );
      favoriteSource.value = const LibraryShelfTaskProgress(
        message: '正在解析: 收藏帖',
        current: 4,
        total: 10,
        source: LibraryMutationSource.favoriteSync,
      );

      expect(service.shown, hasLength(2));
      expect(service.shown.last.current, 4);
    });

    test('favorite and comic notifications use distinct keys', () {
      favoriteSource.value = const LibraryShelfTaskProgress(
        message: '正在解析',
        source: LibraryMutationSource.favoriteSync,
      );
      comicSource.value = const LibraryShelfTaskProgress(
        message: '《作品名》正在等待漫画搜索 预计耗时10.5s',
        source: LibraryMutationSource.comicSearchQueue,
      );

      expect(
        service.shown.map((n) => n.key).toSet(),
        <LibraryTaskNotificationKey>{
          LibraryTaskNotificationKey.favoriteSync,
          LibraryTaskNotificationKey.comicSearchQueue,
        },
      );
    });

    test('denied permission does not throw', () {
      service.throwOnShow = true;

      expect(
        () => favoriteSource.value = const LibraryShelfTaskProgress(
          message: '正在解析',
          source: LibraryMutationSource.favoriteSync,
        ),
        returnsNormally,
      );
    });
  });
}

class _FakeNotificationService implements LibraryTaskNotificationService {
  final List<LibraryTaskNotification> shown = <LibraryTaskNotification>[];
  final List<LibraryTaskNotificationKey> cleared =
      <LibraryTaskNotificationKey>[];
  bool throwOnShow = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<LibraryTaskNotificationPermissionState> ensurePermission() async {
    return LibraryTaskNotificationPermissionState.granted;
  }

  @override
  Future<void> showOrUpdate(LibraryTaskNotification notification) async {
    if (throwOnShow) {
      throw StateError('permission denied');
    }
    shown.add(notification);
  }

  @override
  Future<void> clear(LibraryTaskNotificationKey key) async {
    cleared.add(key);
  }
}
