import 'package:flutter/widgets.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_paged_turn_motion.dart';

import '../models/novel_reader_paragraph_clock.dart';

import 'novel_reader_paragraph_motion.dart';
import 'novel_reader_paper_turn.dart';
import 'novel_reader_sheet_motion.dart';

abstract final class NovelReaderPageMotion {
  static int _baseMilliseconds(NovelReaderPageEffect effect) =>
      switch (effect) {
        NovelReaderPageEffect.paper => 420,
        NovelReaderPageEffect.staggered => 620,
        NovelReaderPageEffect.fade => 300,
        NovelReaderPageEffect.cover => 340,
        _ => 260,
      };

  static double snapDurationScale(
    NovelReaderPageEffect effect,
    NovelReaderPageSpeed speed,
  ) =>
      // These effects have their own click clock; release springs use only the
      // selected speed, as in Wenku8, without multiplying the click time again.
      (effect == NovelReaderPageEffect.staggered ||
              effect == NovelReaderPageEffect.fade ||
              effect == NovelReaderPageEffect.cover
          ? 1
          : _baseMilliseconds(effect) / 260) *
      speed.durationScale;
  static Curve curve(NovelReaderPageEffect effect) => switch (effect) {
    NovelReaderPageEffect.fade ||
    NovelReaderPageEffect.cover ||
    NovelReaderPageEffect.staggered => Curves.linear,
    _ => ReaderPagedTurnMotion.animationCurve,
  };

  static bool isFullSheet(NovelReaderPageEffect effect) =>
      effect == NovelReaderPageEffect.paper ||
      effect == NovelReaderPageEffect.fade ||
      effect == NovelReaderPageEffect.cover;
  static Duration duration(
    NovelReaderPageEffect effect,
    NovelReaderPageSpeed speed,
  ) => Duration(
    milliseconds: (_baseMilliseconds(effect) * speed.durationScale).round(),
  );
}

/// PageView adds its own snap physics unless pageSnapping is false. This owns
/// that snap and reads live settings because Scrollable retains same-type physics.
class NovelReaderPageScrollPhysics extends PageScrollPhysics {
  const NovelReaderPageScrollPhysics({
    required this.durationScale,
    super.parent,
  });
  final double Function() durationScale;
  @override
  NovelReaderPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      NovelReaderPageScrollPhysics(
        durationScale: durationScale,
        parent: buildParent(ancestor),
      );
  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final scale = durationScale();
    final simulation = super.createBallisticSimulation(position, velocity);
    return simulation == null ? null : _ScaledPageSimulation(simulation, scale);
  }
}

class _ScaledPageSimulation extends Simulation {
  _ScaledPageSimulation(this.source, this.scale)
    : super(tolerance: source.tolerance);
  final Simulation source;
  final double scale;
  @override
  double x(double time) => source.x(time / scale);
  @override
  double dx(double time) => source.dx(time / scale) / scale;
  @override
  bool isDone(double time) => source.isDone(time / scale);
}

/// Retained page bodies share one navigation rail. Paper extends the visual
/// sheet through the margins without changing the measured HTML content box.
class NovelReaderPageTransition extends StatelessWidget {
  const NovelReaderPageTransition({
    super.key,
    required this.controller,
    required this.index,
    required this.effect,
    required this.reverse,
    required this.paperColor,
    required this.child,
    this.paperClock,
    this.paragraphClock,
    this.paperInsets = EdgeInsets.zero,
  });
  final PageController controller;
  final int index;
  final NovelReaderPageEffect effect;
  final bool reverse;
  final Color paperColor;
  final Widget child;
  final NovelReaderPaperClock? paperClock;
  final NovelReaderParagraphClock? paragraphClock;
  final EdgeInsets paperInsets;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final insets = NovelReaderPageMotion.isFullSheet(effect)
          ? paperInsets
          : EdgeInsets.zero;
      return AnimatedBuilder(
        animation: controller,
        child: Transform.translate(
          offset: Offset(-insets.left, -insets.top),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: constraints.maxWidth + insets.horizontal,
            maxWidth: constraints.maxWidth + insets.horizontal,
            minHeight: constraints.maxHeight + insets.vertical,
            maxHeight: constraints.maxHeight + insets.vertical,
            child: NovelReaderPaperTurn(
              clock: paperClock,
              controller: controller,
              index: index,
              reverse:
                  reverse != (Directionality.of(context) == TextDirection.rtl),
              enabled: effect == NovelReaderPageEffect.paper,
              paperColor: paperColor,
              child: NovelReaderSheetMotion(
                controller: controller,
                index: index,
                effect: effect,
                reverse:
                    reverse !=
                    (Directionality.of(context) == TextDirection.rtl),
                child: ColoredBox(
                  color: effect == NovelReaderPageEffect.staggered
                      ? const Color(0x00000000)
                      : paperColor,
                  child: Padding(
                    padding: insets,
                    child: NovelReaderParagraphTurnPage(
                      controller: controller,
                      clock: paragraphClock,
                      travelWidth:
                          constraints.maxWidth + paperInsets.horizontal,
                      index: index,
                      reverse: reverse,
                      enabled: effect == NovelReaderPageEffect.staggered,
                      child: RepaintBoundary(child: child),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        builder: (context, body) {
          final physicalReverse =
              reverse != (Directionality.of(context) == TextDirection.rtl);
          final page =
              controller.hasClients && controller.position.hasContentDimensions
              ? controller.page ?? controller.initialPage.toDouble()
              : controller.initialPage.toDouble();
          final offset = index - page;
          final stationary = effect != NovelReaderPageEffect.slide;
          return Transform.translate(
            offset: Offset(
              stationary
                  ? -offset * constraints.maxWidth * (physicalReverse ? -1 : 1)
                  : 0,
              0,
            ),
            child: IgnorePointer(ignoring: offset.abs() > 0.001, child: body),
          );
        },
      );
    },
  );
}
