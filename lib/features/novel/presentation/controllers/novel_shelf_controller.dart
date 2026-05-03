import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';

class NovelShelfViewState {
  const NovelShelfViewState({
    required this.selectedFid,
    required this.items,
    this.hint,
  });

  final String selectedFid;
  final List<NovelItem> items;
  final String? hint;

  NovelShelfViewState copyWith({
    String? selectedFid,
    List<NovelItem>? items,
    String? hint,
    bool clearHint = false,
  }) {
    return NovelShelfViewState(
      selectedFid: selectedFid ?? this.selectedFid,
      items: items ?? this.items,
      hint: clearHint ? null : (hint ?? this.hint),
    );
  }
}

final novelShelfControllerProvider =
    AsyncNotifierProvider.autoDispose<NovelShelfController, NovelShelfViewState>(
  NovelShelfController.new,
);

class NovelShelfController extends AsyncNotifier<NovelShelfViewState> {
  static const String fidAll = 'all';
  static const String fidLiterature = '49';
  static const String fidLightNovel = '55';

  @override
  FutureOr<NovelShelfViewState> build() async {
    return _load(selectedFid: fidAll);
  }

  Future<void> selectFid(String fid) async {
    final current = state.value;
    if (current == null || current.selectedFid == fid) {
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(selectedFid: fid));
  }

  Future<void> refresh() async {
    final current = state.value;
    final selected = current?.selectedFid ?? fidAll;
    state = await AsyncValue.guard(() => _load(selectedFid: selected));
  }

  Future<String> addByTid({
    required String fid,
    required String tid,
  }) async {
    final repository = ref.read(novelRepositoryProvider);
    final normalizedFid = fid.trim();
    final normalizedTid = tid.trim();
    final novelId = 'novel:$normalizedFid:$normalizedTid';

    await repository.upsertNovelBySeed(
      seed: NovelRefreshSeed(fid: normalizedFid, tid: normalizedTid),
    );
    await repository.refreshEpisodes(novelId: novelId);

    final reloaded = await _load(selectedFid: state.value?.selectedFid ?? fidAll);
    state = AsyncData(reloaded.copyWith(hint: '已加入小说书架并完成首轮章节刷新'));
    return novelId;
  }

  Future<NovelShelfViewState> _load({required String selectedFid}) async {
    final repository = ref.read(novelRepositoryProvider);
    final items = await repository.getShelfItems(
      sourceFid: selectedFid == fidAll ? null : selectedFid,
    );
    return NovelShelfViewState(
      selectedFid: selectedFid,
      items: items,
      hint: null,
    );
  }
}
