import 'package:y300/features/comic/domain/models/comic_models.dart';

/// 首楼漫画语义解析接口，输入原始 HTML，输出结构化结果。
abstract class ComicParserService {
  ParsedComicPost parse({required String message});
}
