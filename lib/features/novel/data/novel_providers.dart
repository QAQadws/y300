import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/local_novel_repository.dart';
import 'package:y300/features/novel/data/novel_repository.dart';

final novelRepositoryProvider = Provider<NovelRepository>((ref) {
  return const LocalNovelRepository();
});
