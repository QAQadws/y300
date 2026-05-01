import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';

final comicShelfControllerProvider =
    AsyncNotifierProvider.autoDispose<ComicShelfController, List<ComicShelfItem>>(
      ComicShelfController.new,
    );

/// 书架控制器：负责读取默认分类下漫画列表。
class ComicShelfController extends AsyncNotifier<List<ComicShelfItem>> {
  @override
  FutureOr<List<ComicShelfItem>> build() {
    return _load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<List<ComicShelfItem>> _load() {
    final repository = ref.read(comicRepositoryProvider);
    return repository.getShelfItems();
  }
}
