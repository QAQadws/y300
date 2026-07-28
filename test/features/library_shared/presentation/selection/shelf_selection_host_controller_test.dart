import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';

void main() {
  group('ShelfSelectionHostController', () {
    late ShelfSelectionHostController controller;

    setUp(() {
      controller = ShelfSelectionHostController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('active owner can register update and clear selection state', () {
      final owner = Object();
      controller.activate(
        ownerToken: owner,
        moduleKey: LibraryModuleKey.comic,
        moduleTitle: '漫画',
        activeCategoryId: 'default',
        selectedCount: 1,
        selectedWorkIds: const <String>{'comic-1'},
        selectionActions: const <SelectionAction>[
          SelectionAction(id: 'download', icon: Icons.download),
        ],
        delegate: _idleDelegate(),
      );

      expect(controller.isActive, isTrue);
      expect(controller.state?.moduleKey, LibraryModuleKey.comic);
      expect(controller.state?.selectedCount, 1);

      controller.update(
        ownerToken: owner,
        activeCategoryId: 'default',
        selectedCount: 2,
        selectedWorkIds: const <String>{'comic-1', 'comic-2'},
        selectionActions: const <SelectionAction>[
          SelectionAction(id: 'download', icon: Icons.download),
          SelectionAction(id: 'unfavorite', icon: Icons.delete),
        ],
      );

      expect(controller.state?.selectedCount, 2);
      expect(controller.selectedWorkIds, const <String>{'comic-1', 'comic-2'});
      expect(controller.state?.selectionActions.length, 2);

      controller.deactivate(owner);

      expect(controller.isActive, isFalse);
      expect(controller.state, isNull);
      expect(controller.selectedWorkIds, isEmpty);
    });

    test('stale owner update and clear do not affect active selection', () {
      final activeOwner = Object();
      final staleOwner = Object();
      controller.activate(
        ownerToken: activeOwner,
        moduleKey: LibraryModuleKey.favorite,
        moduleTitle: '收藏',
        activeCategoryId: 'default',
        selectedCount: 1,
        selectedWorkIds: const <String>{'favorite:100'},
        selectionActions: const <SelectionAction>[
          SelectionAction(id: 'unfavorite', icon: Icons.delete),
        ],
        delegate: _idleDelegate(),
      );

      controller.update(
        ownerToken: staleOwner,
        activeCategoryId: 'other',
        selectedCount: 9,
        selectedWorkIds: const <String>{'ignored'},
        selectionActions: const <SelectionAction>[
          SelectionAction(id: 'ignored', icon: Icons.info),
        ],
      );
      controller.deactivate(staleOwner);

      expect(controller.isActive, isTrue);
      expect(controller.state?.ownerToken, same(activeOwner));
      expect(controller.state?.selectedCount, 1);
      expect(controller.selectedWorkIds, const <String>{'favorite:100'});
    });

    test('changed action refreshes then exits selection', () async {
      final calls = <String>[];
      final owner = Object();
      controller.activate(
        ownerToken: owner,
        moduleKey: LibraryModuleKey.comic,
        moduleTitle: '漫画',
        activeCategoryId: 'default',
        selectedCount: 1,
        selectedWorkIds: const <String>{'comic-1'},
        selectionActions: const <SelectionAction>[
          SelectionAction(id: 'download', icon: Icons.download),
        ],
        delegate: ShelfSelectionHostDelegate(
          exitSelection: () async {
            calls.add('exit');
          },
          selectAllVisible: () async {},
          invertVisible: () async {},
          loadAvailableCategories: () async => const <LibraryCategory>[],
          createCategory: (name) async => 'created',
          runSelectionAction: (request) async {
            calls.add('run:${request.actionId}');
            return const SelectionActionResult(message: 'done', changed: true);
          },
          refreshAfterAction: () async {
            calls.add('refresh');
          },
        ),
      );

      final result = await controller.executeAction(actionId: 'download');

      expect(result.changed, isTrue);
      expect(calls, <String>['run:download', 'refresh', 'exit']);
      expect(controller.isActive, isFalse);
    });

    test('unchanged action keeps selection active', () async {
      final owner = Object();
      controller.activate(
        ownerToken: owner,
        moduleKey: LibraryModuleKey.novel,
        moduleTitle: '小说',
        activeCategoryId: 'default',
        selectedCount: 1,
        selectedWorkIds: const <String>{'novel-1'},
        selectionActions: const <SelectionAction>[
          SelectionAction(id: 'mark-all-read', icon: Icons.done_all),
        ],
        delegate: ShelfSelectionHostDelegate(
          exitSelection: () async => fail('should not exit'),
          selectAllVisible: () async {},
          invertVisible: () async {},
          loadAvailableCategories: () async => const <LibraryCategory>[],
          createCategory: (name) async => 'created',
          runSelectionAction: (request) async {
            return const SelectionActionResult(message: 'noop', changed: false);
          },
          refreshAfterAction: () async => fail('should not refresh'),
        ),
      );

      final result = await controller.executeAction(actionId: 'mark-all-read');

      expect(result.changed, isFalse);
      expect(controller.isActive, isTrue);
      expect(controller.state?.selectedCount, 1);
    });

    test('action exception keeps selection active', () async {
      final owner = Object();
      controller.activate(
        ownerToken: owner,
        moduleKey: LibraryModuleKey.favorite,
        moduleTitle: '收藏',
        activeCategoryId: 'default',
        selectedCount: 1,
        selectedWorkIds: const <String>{'favorite:100'},
        selectionActions: const <SelectionAction>[
          SelectionAction(id: 'unfavorite', icon: Icons.delete),
        ],
        delegate: ShelfSelectionHostDelegate(
          exitSelection: () async => fail('should not exit'),
          selectAllVisible: () async {},
          invertVisible: () async {},
          loadAvailableCategories: () async => const <LibraryCategory>[],
          createCategory: (name) async => 'created',
          runSelectionAction: (request) async {
            throw StateError('boom');
          },
          refreshAfterAction: () async => fail('should not refresh'),
        ),
      );

      await expectLater(
        controller.executeAction(actionId: 'unfavorite'),
        throwsA(isA<StateError>()),
      );

      expect(controller.isActive, isTrue);
      expect(controller.state?.selectedCount, 1);
    });

    test('dispose keeps deactivate as no-op', () {
      final disposedController = ShelfSelectionHostController();
      final owner = Object();
      disposedController.dispose();

      expect(() => disposedController.deactivate(owner), returnsNormally);
      expect(disposedController.isActive, isFalse);
      expect(disposedController.state, isNull);
    });

    test('dispose keeps activate and update as no-op', () {
      final disposedController = ShelfSelectionHostController();
      disposedController.dispose();

      expect(
        () => disposedController.activate(
          ownerToken: Object(),
          moduleKey: LibraryModuleKey.comic,
          moduleTitle: '漫画',
          activeCategoryId: 'default',
          selectedCount: 1,
          selectedWorkIds: const <String>{'comic-1'},
          selectionActions: const <SelectionAction>[
            SelectionAction(id: 'download', icon: Icons.download),
          ],
          delegate: _idleDelegate(),
        ),
        returnsNormally,
      );
      expect(
        () => disposedController.update(
          ownerToken: Object(),
          activeCategoryId: 'other',
          selectedCount: 2,
          selectedWorkIds: const <String>{'comic-1', 'comic-2'},
          selectionActions: const <SelectionAction>[
            SelectionAction(id: 'download', icon: Icons.download),
          ],
        ),
        returnsNormally,
      );
      expect(disposedController.isActive, isFalse);
      expect(disposedController.state, isNull);
      expect(disposedController.selectedWorkIds, isEmpty);
    });
  });
}

ShelfSelectionHostDelegate _idleDelegate() {
  return ShelfSelectionHostDelegate(
    exitSelection: () async {},
    selectAllVisible: () async {},
    invertVisible: () async {},
    loadAvailableCategories: () async => const <LibraryCategory>[],
    createCategory: (name) async => 'created',
    runSelectionAction: (request) async {
      return const SelectionActionResult(message: 'noop');
    },
    refreshAfterAction: () async {},
  );
}
