import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/features/forum/presentation/forum_display_content_projection.dart';
import 'package:y300/features/forum/presentation/forum_display_content_projector.dart';
import 'package:y300/features/forum/presentation/forum_display_controller.dart';
import 'package:y300/features/forum/presentation/forum_home_content_projection.dart';
import 'package:y300/features/forum/presentation/forum_home_content_projector.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';

final forumHomeContentProjectionProvider =
    FutureProvider.autoDispose<ForumHomeContentProjection?>((ref) async {
      final source = ref.watch(forumHomeControllerProvider).value;
      if (source == null) {
        return null;
      }
      final mode = ref.watch(appServerContentConversionModeProvider);
      final converter = ref.watch(textConverterProvider(mode));
      return ForumHomeContentProjector(
        plainTextBatchConversionService: ref.watch(
          plainTextBatchConversionServiceProvider,
        ),
        diagnosticRecorder: ref.watch(textConversionDiagnosticRecorderProvider),
      ).project(source.viewData, converter: converter);
    });

final forumDisplayContentProjectionProvider = FutureProvider.autoDispose
    .family<ForumDisplayContentProjection?, ForumDisplayArgs>((
      ref,
      args,
    ) async {
      final source = ref.watch(forumDisplayControllerProvider(args)).value;
      if (source == null) {
        return null;
      }
      final mode = ref.watch(appServerContentConversionModeProvider);
      final converter = ref.watch(textConverterProvider(mode));
      return ForumDisplayContentProjector(
        plainTextBatchConversionService: ref.watch(
          plainTextBatchConversionServiceProvider,
        ),
        diagnosticRecorder: ref.watch(textConversionDiagnosticRecorderProvider),
      ).project(source, converter: converter);
    });
