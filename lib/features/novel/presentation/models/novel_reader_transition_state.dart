class NovelReaderTransitionState {
  const NovelReaderTransitionState({
    required this.kind,
    required this.targetEpisodeId,
  });

  final NovelReaderTransitionKind kind;
  final String targetEpisodeId;
}

enum NovelReaderTransitionKind { switchingEpisode, updatingWork }
