import 'package:y300/features/comic/domain/models/comic_models.dart';

/// A normalized comic parsing request.
///
/// `messageHtml` keeps the legacy post-body parsing path, while
/// `attachmentImageUrls` carries images that Discuz exposes only through
/// `postlist.attachments`.
class ComicPostParseInput {
  const ComicPostParseInput({
    required this.messageHtml,
    this.attachmentImageUrls = const <String>[],
  });

  final String messageHtml;
  final List<String> attachmentImageUrls;
}

/// 首楼漫画语义解析接口，输入原始 HTML，输出结构化结果。
abstract class ComicParserService {
  ParsedComicPost parse({required String message});

  ParsedComicPost parseInput(ComicPostParseInput input);
}
