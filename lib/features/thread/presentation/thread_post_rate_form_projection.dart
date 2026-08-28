import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/thread/presentation/thread_post_interaction_models.dart';

final class ThreadRateReasonPresentation {
  const ThreadRateReasonPresentation({
    required this.rawValue,
    required this.displayLabel,
  });

  final String rawValue;
  final String displayLabel;
}

final class ThreadPostRateFormProjection {
  ThreadPostRateFormProjection({
    required this.sourceForm,
    required List<ThreadRateReasonPresentation> reasons,
    required this.mode,
    required this.isConverted,
  }) : reasons = List<ThreadRateReasonPresentation>.unmodifiable(reasons);

  factory ThreadPostRateFormProjection.raw(
    ThreadPostRateForm source, {
    required TextConversionMode mode,
  }) {
    return ThreadPostRateFormProjection(
      sourceForm: source,
      reasons: [
        for (final reason in source.reasonOptions)
          ThreadRateReasonPresentation(rawValue: reason, displayLabel: reason),
      ],
      mode: mode,
      isConverted: false,
    );
  }

  final ThreadPostRateForm sourceForm;
  final List<ThreadRateReasonPresentation> reasons;
  final TextConversionMode mode;
  final bool isConverted;
}

final class ThreadPostRateFormProjector {
  const ThreadPostRateFormProjector({
    required this.plainTextBatchConversionService,
  });

  final PlainTextBatchConversionService plainTextBatchConversionService;

  Future<ThreadPostRateFormProjection> project(
    ThreadPostRateForm source, {
    required TextConverter converter,
  }) async {
    if (converter.mode == TextConversionMode.none ||
        source.reasonOptions.isEmpty) {
      return ThreadPostRateFormProjection.raw(source, mode: converter.mode);
    }
    try {
      final converted = await plainTextBatchConversionService.convertAll(
        sources: source.reasonOptions,
        converter: converter,
      );
      if (converted.length != source.reasonOptions.length) {
        return ThreadPostRateFormProjection.raw(source, mode: converter.mode);
      }
      return ThreadPostRateFormProjection(
        sourceForm: source,
        reasons: [
          for (var index = 0; index < source.reasonOptions.length; index += 1)
            ThreadRateReasonPresentation(
              rawValue: source.reasonOptions[index],
              displayLabel: converted[index],
            ),
        ],
        mode: converter.mode,
        isConverted: true,
      );
    } catch (_) {
      return ThreadPostRateFormProjection.raw(source, mode: converter.mode);
    }
  }
}
