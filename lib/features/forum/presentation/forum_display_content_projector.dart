import 'package:y300/features/forum/domain/models/forum_display_models.dart';
import 'package:y300/features/forum/presentation/forum_content_projection_support.dart';
import 'package:y300/features/forum/presentation/forum_display_content_projection.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

final class ForumDisplayContentProjector {
  ForumDisplayContentProjector({
    required PlainTextBatchConversionService plainTextBatchConversionService,
    required TextConversionDiagnosticRecorder diagnosticRecorder,
  }) : _executor = ForumContentProjectionExecutor(
         plainTextBatchConversionService: plainTextBatchConversionService,
         diagnosticRecorder: diagnosticRecorder,
       );

  final ForumContentProjectionExecutor _executor;

  Future<ForumDisplayContentProjection> project(
    ForumDisplayPageState source, {
    required TextConverter converter,
  }) async {
    if (converter.mode == TextConversionMode.none) {
      return ForumDisplayContentProjection.raw(source, mode: converter.mode);
    }
    final revision = sourceRevisionFor(source);
    final texts = <String>[];
    texts.add(source.title);
    _addFilterTexts(texts, source.primaryFilters);
    _addFilterTexts(texts, source.typeFilters);
    texts.addAll(source.subForums.map((item) => item.title));
    for (final item in source.topEntries) {
      texts
        ..add(item.title)
        ..add(item.badgeLabel);
    }
    for (final item in source.threads) {
      texts
        ..add(item.subject)
        ..add(item.excerpt)
        ..add(item.sourceTagName ?? '')
        ..add(item.badgeLabel ?? '')
        ..add(item.dateline);
    }

    final result = await _executor.convertAll(
      sources: texts,
      converter: converter,
      surface: TextConversionSurface.forumDisplay,
      sourceRevision: revision,
    );
    if (!result.isConverted) {
      return ForumDisplayContentProjection.raw(source, mode: converter.mode);
    }

    var index = 0;
    final displayTitle = result.values[index++];
    final primaryFilters = _projectFilters(
      source.primaryFilters,
      () => result.values[index++],
    );
    final typeFilters = _projectFilters(
      source.typeFilters,
      () => result.values[index++],
    );

    final subForums = <ForumDisplaySubForumProjection>[];
    for (final item in source.subForums) {
      subForums.add(
        ForumDisplaySubForumProjection(
          source: item,
          displayTitle: result.values[index++],
        ),
      );
    }

    final topEntries = <ForumDisplayTopEntryProjection>[];
    for (final item in source.topEntries) {
      topEntries.add(
        ForumDisplayTopEntryProjection(
          source: item,
          displayTitle: result.values[index++],
          displayBadgeLabel: result.values[index++],
        ),
      );
    }

    final threads = <ForumDisplayThreadProjection>[];
    for (final item in source.threads) {
      final displaySubject = result.values[index++];
      final displayExcerpt = result.values[index++];
      final displaySourceTagName = result.values[index++];
      final displayBadgeLabel = result.values[index++];
      final displayDateline = result.values[index++];
      threads.add(
        ForumDisplayThreadProjection(
          source: item,
          displaySubject: displaySubject,
          displayExcerpt: displayExcerpt,
          displaySourceTagName: item.sourceTagName == null
              ? null
              : displaySourceTagName,
          displayBadgeLabel: item.badgeLabel == null ? null : displayBadgeLabel,
          displayDateline: displayDateline,
        ),
      );
    }
    if (index != result.values.length) {
      return ForumDisplayContentProjection.raw(source, mode: converter.mode);
    }

    return ForumDisplayContentProjection(
      sourceState: source,
      displayTitle: displayTitle,
      primaryFilters: List<ForumDisplayFilterProjection>.unmodifiable(
        primaryFilters,
      ),
      typeFilters: List<ForumDisplayFilterProjection>.unmodifiable(typeFilters),
      subForums: List<ForumDisplaySubForumProjection>.unmodifiable(subForums),
      topEntries: List<ForumDisplayTopEntryProjection>.unmodifiable(topEntries),
      threads: List<ForumDisplayThreadProjection>.unmodifiable(threads),
      mode: converter.mode,
      sourceRevision: revision,
      isConverted: true,
    );
  }

  void _addFilterTexts(
    List<String> output,
    List<ForumDisplayFilterItem> items,
  ) {
    output.addAll(items.map((item) => item.label));
  }

  List<ForumDisplayFilterProjection> _projectFilters(
    List<ForumDisplayFilterItem> source,
    String Function() nextValue,
  ) {
    return [
      for (final item in source)
        ForumDisplayFilterProjection(source: item, displayLabel: nextValue()),
    ];
  }

  static String sourceRevisionFor(ForumDisplayPageState source) {
    return ForumDisplayContentProjection.sourceRevisionFor(source);
  }
}
