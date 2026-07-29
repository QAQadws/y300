import 'package:y300/features/forum/presentation/forum_content_projection_support.dart';
import 'package:y300/features/forum/presentation/forum_home_content_projection.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

final class ForumHomeContentProjector {
  ForumHomeContentProjector({
    required PlainTextBatchConversionService plainTextBatchConversionService,
    required TextConversionDiagnosticRecorder diagnosticRecorder,
  }) : _executor = ForumContentProjectionExecutor(
         plainTextBatchConversionService: plainTextBatchConversionService,
         diagnosticRecorder: diagnosticRecorder,
       );

  final ForumContentProjectionExecutor _executor;

  Future<ForumHomeContentProjection> project(
    ForumHomeViewData source, {
    required TextConverter converter,
  }) async {
    if (converter.mode == TextConversionMode.none) {
      return ForumHomeContentProjection.raw(source, mode: converter.mode);
    }
    final revision = sourceRevisionFor(source);
    final texts = <String>[];
    for (final section in source.sections) {
      if (section.type == ForumSectionType.regular) {
        texts.add(section.title);
      }
      for (final item in section.items) {
        texts
          ..add(item.title)
          ..add(item.description);
      }
    }

    final result = await _executor.convertAll(
      sources: texts,
      converter: converter,
      surface: TextConversionSurface.forumHome,
      sourceRevision: revision,
    );
    if (!result.isConverted) {
      return ForumHomeContentProjection.raw(source, mode: converter.mode);
    }

    var index = 0;
    final sections = <ForumHomeSectionProjection>[];
    for (final section in source.sections) {
      final displayTitle = section.type == ForumSectionType.regular
          ? result.values[index++]
          : null;
      final items = <ForumHomeForumProjection>[];
      for (final item in section.items) {
        items.add(
          ForumHomeForumProjection(
            source: item,
            displayTitle: result.values[index++],
            displayDescription: result.values[index++],
          ),
        );
      }
      sections.add(
        ForumHomeSectionProjection(
          source: section,
          displayTitle: displayTitle,
          items: List<ForumHomeForumProjection>.unmodifiable(items),
        ),
      );
    }
    if (index != result.values.length) {
      return ForumHomeContentProjection.raw(source, mode: converter.mode);
    }

    return ForumHomeContentProjection(
      source: source,
      sections: List<ForumHomeSectionProjection>.unmodifiable(sections),
      mode: converter.mode,
      sourceRevision: revision,
      isConverted: true,
    );
  }

  static String sourceRevisionFor(ForumHomeViewData source) {
    return ForumHomeContentProjection.sourceRevisionFor(source);
  }
}
