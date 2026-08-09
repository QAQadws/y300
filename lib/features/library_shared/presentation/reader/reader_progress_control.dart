import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_chrome_palette.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/l10n/app_localizations.dart';

class ReaderProgressControl extends StatelessWidget {
  const ReaderProgressControl({super.key, required this.config});

  static const double _minimumSliderWidth = 96;

  final ReaderProgressConfig config;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = const ReaderChromePaletteResolver().resolve(
      Theme.of(context),
    );
    final discreteTotal = config.total;
    final isDiscrete = discreteTotal != null;
    final safeTotal = isDiscrete && discreteTotal < 1 ? 1 : discreteTotal;
    final current = isDiscrete
        ? (config.current ?? 1).clamp(1, safeTotal!).toInt()
        : null;
    final minValue = config.min;
    final configuredMax = config.max ?? ((safeTotal ?? 1) - 1).toDouble();
    final hasRange = configuredMax > minValue;
    final maxValue = hasRange ? configuredMax : minValue + 1;
    final rawValue = isDiscrete
        ? (current! - 1).toDouble()
        : (config.value ?? minValue);
    final sliderValue = rawValue.clamp(minValue, maxValue).toDouble();
    final leadingLabel =
        config.leadingLabel ?? (current ?? sliderValue).toString();
    final trailingLabel =
        config.trailingLabel ?? (safeTotal ?? maxValue).toString();
    final sliderEnabled = config.sliderEnabled && hasRange;
    final labelSlotWidth = _measureLabelSlotWidth(
      context: context,
      style: DefaultTextStyle.of(context).style,
      leadingLabel: leadingLabel,
      trailingLabel: trailingLabel,
    );

    return Row(
      children: [
        IconButton(
          key: const Key('shared-reader-prev-button'),
          tooltip: config.previousTooltip ?? l10n.readerPrevious,
          onPressed: config.previousEnabled ? config.onPrevious : null,
          icon: Icon(config.previousIcon),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.progressTrackBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maximumLabelSlotWidth = constraints.hasBoundedWidth
                      ? ((constraints.maxWidth - _minimumSliderWidth) / 2)
                            .clamp(0.0, labelSlotWidth)
                            .toDouble()
                      : labelSlotWidth;
                  final effectiveLabelSlotWidth = labelSlotWidth
                      .clamp(0.0, maximumLabelSlotWidth)
                      .toDouble();
                  return Row(
                    children: [
                      SizedBox(
                        key: const Key('shared-reader-current-label-slot'),
                        width: effectiveLabelSlotWidth,
                        child: Text(
                          leadingLabel,
                          key: const Key('shared-reader-current-label'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                        ),
                      ),
                      Expanded(
                        child: AbsorbPointer(
                          absorbing: config.interactionLocked,
                          child: Slider(
                            key: const Key('shared-reader-progress-slider'),
                            value: sliderValue,
                            min: minValue,
                            max: maxValue,
                            divisions: isDiscrete
                                ? (safeTotal! > 1 ? safeTotal - 1 : null)
                                : config.divisions,
                            semanticFormatterCallback: (_) =>
                                l10n.readerProgressSemantics(
                                  leadingLabel,
                                  trailingLabel,
                                ),
                            onChangeStart: sliderEnabled
                                ? config.onChangeStart
                                : null,
                            onChanged: sliderEnabled ? config.onChanged : null,
                            onChangeEnd: sliderEnabled
                                ? config.onChangeEnd
                                : null,
                          ),
                        ),
                      ),
                      SizedBox(
                        key: const Key('shared-reader-total-label-slot'),
                        width: effectiveLabelSlotWidth,
                        child: Text(
                          trailingLabel,
                          key: const Key('shared-reader-total-label'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('shared-reader-next-button'),
          tooltip: config.nextTooltip ?? l10n.readerNext,
          onPressed: config.nextEnabled ? config.onNext : null,
          icon: Icon(config.nextIcon),
        ),
      ],
    );
  }

  double _measureLabelSlotWidth({
    required BuildContext context,
    required TextStyle style,
    required String leadingLabel,
    required String trailingLabel,
  }) {
    final leadingWidth = _measureLabelWidth(
      context: context,
      style: style,
      label: leadingLabel,
    );
    final trailingWidth = _measureLabelWidth(
      context: context,
      style: style,
      label: trailingLabel,
    );
    return (leadingWidth > trailingWidth ? leadingWidth : trailingWidth)
        .ceilToDouble();
  }

  double _measureLabelWidth({
    required BuildContext context,
    required TextStyle style,
    required String label,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}
