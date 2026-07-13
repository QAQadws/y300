import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';

abstract interface class NovelChapterSourceRouteResolver {
  Future<NovelChapterSourceRoute> resolve(
    NovelChapterSourceReference reference,
  );
}
