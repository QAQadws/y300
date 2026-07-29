import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_content_projection_batch_executor.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

/// Executes the two batches owned by one Thread detail revision.
///
/// Results are exposed only when both batches succeed and preserve
/// cardinality. This prevents mixed raw/converted pages.
final class ThreadContentProjectionExecutor {
  const ThreadContentProjectionExecutor({
    required this.plainTextBatchConversionService,
    required this.htmlTextNodeConversionService,
    required this.diagnosticRecorder,
  });

  final PlainTextBatchConversionService plainTextBatchConversionService;
  final HtmlTextNodeConversionService htmlTextNodeConversionService;
  final TextConversionDiagnosticRecorder diagnosticRecorder;

  Future<ThreadContentBatchResult> convert({
    required List<String> plainSources,
    required List<String> htmlFragments,
    required TextConverter converter,
    required String sourceRevision,
  }) async {
    final result =
        await TextContentProjectionBatchExecutor(
          plainTextBatchConversionService: plainTextBatchConversionService,
          htmlTextNodeConversionService: htmlTextNodeConversionService,
          diagnosticRecorder: diagnosticRecorder,
        ).convert(
          surface: TextConversionSurface.threadDetail,
          plainSources: plainSources,
          htmlFragments: htmlFragments,
          converter: converter,
          sourceRevision: sourceRevision,
        );
    return result.succeeded
        ? ThreadContentBatchResult.success(
            plainValues: result.plainValues,
            htmlValues: result.htmlValues,
          )
        : const ThreadContentBatchResult.failure();
  }
}

final class ThreadContentBatchResult {
  const ThreadContentBatchResult._({
    required this.plainValues,
    required this.htmlValues,
    required this.succeeded,
  });

  factory ThreadContentBatchResult.success({
    required List<String> plainValues,
    required List<HtmlTextNodeConversionResult> htmlValues,
  }) {
    return ThreadContentBatchResult._(
      plainValues: List<String>.unmodifiable(plainValues),
      htmlValues: List<HtmlTextNodeConversionResult>.unmodifiable(htmlValues),
      succeeded: true,
    );
  }

  const ThreadContentBatchResult.failure()
    : this._(
        plainValues: const <String>[],
        htmlValues: const <HtmlTextNodeConversionResult>[],
        succeeded: false,
      );

  final List<String> plainValues;
  final List<HtmlTextNodeConversionResult> htmlValues;
  final bool succeeded;
}
