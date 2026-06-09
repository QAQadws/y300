import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';

class ReaderProgressControl extends StatelessWidget {
  const ReaderProgressControl({
    super.key,
    required this.config,
  });

  final ReaderProgressConfig config;

  @override
  Widget build(BuildContext context) {
    final safeTotal = config.total < 1 ? 1 : config.total;
    final current = config.current.clamp(1, safeTotal).toInt();
    final sliderValue = (current - 1).toDouble();
    final maxValue = (safeTotal - 1).toDouble();

    return Row(
      children: [
        IconButton(
          key: const Key('shared-reader-prev-button'),
          tooltip: config.previousTooltip,
          onPressed:
              config.previousEnabled ? config.onPrevious : null,
          icon: Icon(config.previousIcon),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$current',
                      key: const Key('shared-reader-current-label'),
                      textAlign: TextAlign.left,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('shared-reader-progress-slider'),
                      value: sliderValue,
                      min: 0,
                      max: maxValue,
                      divisions: safeTotal > 1 ? safeTotal - 1 : null,
                      onChangeStart: config.interactionLocked
                          ? null
                          : config.onChangeStart,
                      onChanged: config.interactionLocked
                          ? null
                          : config.onChanged,
                      onChangeEnd: config.interactionLocked
                          ? null
                          : config.onChangeEnd,
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$safeTotal',
                      key: const Key('shared-reader-total-label'),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('shared-reader-next-button'),
          tooltip: config.nextTooltip,
          onPressed: config.nextEnabled ? config.onNext : null,
          icon: Icon(config.nextIcon),
        ),
      ],
    );
  }
}
