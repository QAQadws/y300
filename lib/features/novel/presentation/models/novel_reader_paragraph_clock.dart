import 'package:flutter/widgets.dart';

/// Keeps the gesture's origin until it lands. Crossing halfway or reversing an
/// unfinished drag must not swap the outgoing and incoming paragraph clocks.
class NovelReaderParagraphClock extends ChangeNotifier {
  NovelReaderParagraphClock(this.controller)
    : _resting = controller.initialPage,
      _page = controller.initialPage.toDouble() {
    controller.addListener(_tick);
    _tick();
  }

  final PageController controller;
  int _resting;
  int? _origin;
  double _page;
  int _source = 0, _target = 0;
  double _progress = 0;
  double get page => _page;
  int get source => _source;
  int get target => _target;
  double get progress => _progress;
  bool get turning => _origin != null;

  void _tick() {
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return;
    }
    _page = controller.page ?? controller.initialPage.toDouble();
    if ((page - page.round()).abs() < 0.000001) {
      _resting = page.round();
      _origin = null;
      _progress = 0;
    } else {
      _origin ??= _resting;
      final forward = page > _origin!;
      _source = forward ? page.floor() : page.ceil();
      _target = forward ? page.ceil() : page.floor();
      _progress = (forward ? page - source : source - page).clamp(0.0, 1.0);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_tick);
    super.dispose();
  }
}

/// Matches Wenku8 ReaderTurnScope's relay interval, applied once to a linear
/// page clock. Bounds order unequal paragraphs by their actual shared rows.
abstract final class NovelReaderParagraphMotion {
  static double progress(double turn, double rank) {
    final start = 0.02 + 0.18 * rank.clamp(0.0, 1.0);
    return Interval(
      start,
      start + 0.80,
      curve: Curves.easeInOutSine,
    ).transform(turn.clamp(0.0, 1.0));
  }
}
