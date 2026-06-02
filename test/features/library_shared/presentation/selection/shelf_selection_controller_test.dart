import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_controller.dart';

void main() {
  group('ShelfSelectionController', () {
    late ShelfSelectionController controller;
    late int notifications;

    setUp(() {
      controller = ShelfSelectionController();
      notifications = 0;
      controller.addListener(() => notifications++);
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts idle with no selection', () {
      expect(controller.isSelecting, isFalse);
      expect(controller.selectedCount, 0);
      expect(controller.selectedWorkIds, isEmpty);
    });

    test('enter starts selecting and selects the first item', () {
      controller.enter('w1');

      expect(controller.isSelecting, isTrue);
      expect(controller.selectedWorkIds, <String>{'w1'});
      expect(notifications, 1);
    });

    test('enter again only appends and notifies once per new item', () {
      controller.enter('w1');
      controller.enter('w2');

      expect(controller.selectedWorkIds, <String>{'w1', 'w2'});
      expect(notifications, 2);
    });

    test('enter with an already-selected item does not notify again', () {
      controller.enter('w1');
      controller.enter('w1');

      expect(controller.selectedWorkIds, <String>{'w1'});
      expect(notifications, 1);
    });

    test('toggle adds then removes an item', () {
      controller.toggle('w1');
      expect(controller.isSelected('w1'), isTrue);
      expect(controller.isSelecting, isTrue);

      controller.toggle('w1');
      expect(controller.isSelected('w1'), isFalse);
      expect(controller.selectedCount, 0);
      // Toggling to empty does not auto-exit; UI owns that decision.
      expect(controller.isSelecting, isTrue);
    });

    test('selectAll adds the whole visible set', () {
      controller.enter('w1');
      controller.selectAll(<String>['w1', 'w2', 'w3']);

      expect(controller.selectedWorkIds, <String>{'w1', 'w2', 'w3'});
    });

    test('invert keeps unselected and clears selected within the range', () {
      controller.enter('w1');
      controller.toggle('w3');

      controller.invert(<String>['w1', 'w2', 'w3', 'w4']);

      expect(controller.selectedWorkIds, <String>{'w2', 'w4'});
    });

    test('exit clears selection and leaves selecting mode', () {
      controller.enter('w1');
      controller.toggle('w2');

      controller.exit();

      expect(controller.isSelecting, isFalse);
      expect(controller.selectedCount, 0);
    });

    test('exit while already idle does not notify', () {
      controller.exit();
      expect(notifications, 0);
    });
  });
}
