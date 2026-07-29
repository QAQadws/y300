import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projection.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projector.dart';
import 'package:y300/features/thread/presentation/thread_detail_controller.dart';

final threadDetailContentProjectionProvider = FutureProvider.autoDispose
    .family<ThreadDetailContentProjection?, ThreadDetailArgs>((
      ref,
      args,
    ) async {
      final controllerProvider = threadDetailControllerProvider(args);
      final watchedRevision = ref.watch(
        controllerProvider.select((value) {
          final source = value.value;
          return source == null
              ? null
              : ThreadDetailContentProjector.sourceRevisionFor(source);
        }),
      );
      if (watchedRevision == null) {
        return null;
      }
      // Transient poll/rating state is intentionally excluded from the
      // selector, so it cannot start another OpenCC batch for this revision.
      final source = ref.read(controllerProvider).value;
      if (source == null) {
        return null;
      }
      final mode = ref.watch(appServerContentConversionModeProvider);
      final converter = ref.watch(textConverterProvider(mode));
      return ThreadDetailContentProjector(
        plainTextBatchConversionService: ref.watch(
          plainTextBatchConversionServiceProvider,
        ),
        htmlTextNodeConversionService: ref.watch(
          htmlTextNodeConversionServiceProvider,
        ),
        diagnosticRecorder: ref.watch(textConversionDiagnosticRecorderProvider),
      ).project(source, converter: converter);
    });
