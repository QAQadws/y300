import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_paged_navigation_controller.dart';

class _Target implements NovelReaderPagedNavigationTarget {
  final calls = <String>[];
  bool accepts = true;
  @override
  bool turnPrevious() {
    calls.add('previous');
    return accepts;
  }

  @override
  bool turnNext() {
    calls.add('next');
    return accepts;
  }

  @override
  bool confirmChapterEndNavigation() {
    calls.add('confirm');
    return accepts;
  }

  @override
  void cancelChapterTurn() {
    calls.add('cancel');
  }
}

void main() {
  test('commands reach only the current target and retain its acceptance', () {
    final controller = NovelReaderPagedNavigationController();
    expect(controller.turnNext(), isFalse);
    final first = _Target();
    final firstBinding = controller.bind(first);
    expect(controller.turnPrevious(), isTrue);
    first.accepts = false;
    expect(controller.confirmChapterEndNavigation(), isFalse);
    final next = _Target();
    final nextBinding = controller.bind(next);
    firstBinding.dispose();
    expect(controller.turnNext(), isTrue);
    controller.cancelChapterTurn();
    expect(first.calls, ['previous', 'confirm']);
    expect(next.calls, ['next', 'cancel']);
    nextBinding.dispose();
    nextBinding.dispose();
    expect(controller.confirmChapterEndNavigation(), isFalse);
    controller.dispose();
  });

  test('an earlier binding cannot detach the same target rebound later', () {
    final controller = NovelReaderPagedNavigationController();
    final target = _Target();
    final old = controller.bind(target);
    final current = controller.bind(target);
    old.dispose();
    expect(controller.turnNext(), isTrue);
    current.dispose();
    expect(controller.turnNext(), isFalse);
    controller.dispose();
  });

  test(
    'terminal chrome disposal rejects late bindings and releases commands',
    () {
      final controller = NovelReaderPagedNavigationController();
      final target = _Target();
      final binding = controller.bind(target);
      controller.dispose();
      binding.dispose();
      final late = controller.bind(target);
      expect(controller.turnPrevious(), isFalse);
      expect(controller.turnNext(), isFalse);
      expect(controller.confirmChapterEndNavigation(), isFalse);
      controller.cancelChapterTurn();
      expect(target.calls, isEmpty);
      late.dispose();
    },
  );
}
