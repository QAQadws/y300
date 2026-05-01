import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_repository.dart';

final comicRepositoryProvider = Provider<ComicRepository>((ref) {
  return InMemoryComicRepository();
});
