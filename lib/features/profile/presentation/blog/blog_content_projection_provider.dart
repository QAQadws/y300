import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_projection.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_content_projection_batch_executor.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';

/// The account epoch also changes on A -> B -> A. A matching display string
/// must never make an old asynchronous result eligible in a new session.
final class BlogContentProjection {
  const BlogContentProjection({
    required this.owner,
    required this.converterId,
    required this.display,
  });
  final Object owner;
  final String converterId;
  final BlogDisplayText display;
}

final blogContentProjectionProvider = FutureProvider.autoDispose
    .family<BlogContentProjection, BlogContentSource>((ref, source) async {
      final owner = ref.watch(blogMutationBusProvider);
      final mode = ref.watch(appServerContentConversionModeProvider);
      final converter = ref.watch(textConverterProvider(mode));
      final projector = BlogContentProjector(
        TextContentProjectionBatchExecutor(
          plainTextBatchConversionService: ref.watch(
            plainTextBatchConversionServiceProvider,
          ),
          htmlTextNodeConversionService: ref.watch(
            htmlTextNodeConversionServiceProvider,
          ),
          diagnosticRecorder: ref.watch(
            textConversionDiagnosticRecorderProvider,
          ),
        ),
      );
      return BlogContentProjection(
        owner: owner,
        converterId: converter.id,
        display: await projector.project(source, converter),
      );
    });

BlogDisplayText watchBlogDisplayText(WidgetRef ref, BlogContentSource source) {
  final mode = ref.watch(appServerContentConversionModeProvider);
  if (mode == TextConversionMode.none) return const BlogDisplayText.raw();
  final owner = ref.watch(blogMutationBusProvider);
  final converter = ref.watch(textConverterProvider(mode));
  final result = ref.watch(blogContentProjectionProvider(source)).asData?.value;
  return result != null &&
          identical(result.owner, owner) &&
          result.converterId == converter.id
      ? result.display
      : const BlogDisplayText.raw();
}
