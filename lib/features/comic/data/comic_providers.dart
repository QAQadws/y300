import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local_comic_repository.dart';

final comicRepositoryProvider = Provider<ComicRepository>((ref) {
  return LocalComicRepository(ComicLocalDb.open());
});

