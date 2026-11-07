import 'package:flutter_riverpod/flutter_riverpod.dart';

import './presentation/services/novel_reader_html_preparation_service.dart';
import './presentation/services/novel_html_chapter_render_preparer.dart';

import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';

final novelReaderHtmlPreparationServiceProvider =
    Provider<NovelReaderHtmlPreparationService>((ref) {
      return DefaultNovelReaderHtmlPreparationService(
        preparer: NovelHtmlChapterRenderPreparer(
          conversionService: ref.watch(htmlTextNodeConversionServiceProvider),
        ),
      );
    });
