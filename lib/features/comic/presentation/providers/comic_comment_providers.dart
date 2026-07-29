import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projector.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_content_projection_controller.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_tail_surface.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';

final comicCommentSessionControllerProvider = Provider.autoDispose
    .family<ComicCommentSessionController, ComicCommentSessionKey>((ref, key) {
      final controller = ComicCommentSessionController(
        key: key,
        loader: ref.watch(comicCommentLoaderProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final comicCommentContentProjectionControllerProvider = Provider.autoDispose
    .family<ComicCommentContentProjectionController, ComicCommentSessionKey>((
      ref,
      key,
    ) {
      final initialMode = ref.read(appServerContentConversionModeProvider);
      final controller = ComicCommentContentProjectionController(
        session: ref.watch(comicCommentSessionControllerProvider(key)),
        projector: ComicCommentContentProjector(
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
        initialMode: initialMode,
        initialConverter: ref.read(textConverterProvider(initialMode)),
      );
      ref.listen(appServerContentConversionModeProvider, (previous, next) {
        controller.updateConversion(
          mode: next,
          converter: ref.read(textConverterProvider(next)),
        );
      });
      ref.onDispose(controller.dispose);
      return controller;
    });

final comicCommentTailSurfaceProvider = Provider.autoDispose
    .family<ComicCommentTailSurface, ComicCommentSessionKey>((ref, key) {
      final session = ref.watch(comicCommentSessionControllerProvider(key));
      final surface = ComicCommentTailSurface(
        session: session,
        contentProjectionController: ref.watch(
          comicCommentContentProjectionControllerProvider(key),
        ),
        imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
      );
      ref.onDispose(surface.dispose);
      return surface;
    });
