import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';

class ForumWebViewState {
  const ForumWebViewState({
    required this.currentUri,
    required this.pageKind,
    required this.fid,
    required this.tid,
    required this.boardName,
    required this.pageTitle,
    required this.canGoBack,
    required this.favoriteForums,
    required this.currentFavoriteForum,
    required this.isFavoriteMutationLoading,
    required this.isLoading,
    required this.loadingProgress,
  });

  final Uri currentUri;
  final ForumWebViewPageKind pageKind;
  final String? fid;
  final String? tid;
  final String? boardName;
  final String? pageTitle;
  final bool canGoBack;
  final List<FavoriteForum> favoriteForums;
  final FavoriteForum? currentFavoriteForum;
  final bool isFavoriteMutationLoading;
  final bool isLoading;
  final int loadingProgress;

  ForumWebViewState copyWith({
    Uri? currentUri,
    ForumWebViewPageKind? pageKind,
    String? fid,
    bool clearFid = false,
    String? tid,
    bool clearTid = false,
    String? boardName,
    bool clearBoardName = false,
    String? pageTitle,
    bool clearPageTitle = false,
    bool? canGoBack,
    List<FavoriteForum>? favoriteForums,
    FavoriteForum? currentFavoriteForum,
    bool clearCurrentFavoriteForum = false,
    bool? isFavoriteMutationLoading,
    bool? isLoading,
    int? loadingProgress,
  }) {
    return ForumWebViewState(
      currentUri: currentUri ?? this.currentUri,
      pageKind: pageKind ?? this.pageKind,
      fid: clearFid ? null : (fid ?? this.fid),
      tid: clearTid ? null : (tid ?? this.tid),
      boardName: clearBoardName ? null : (boardName ?? this.boardName),
      pageTitle: clearPageTitle ? null : (pageTitle ?? this.pageTitle),
      canGoBack: canGoBack ?? this.canGoBack,
      favoriteForums: favoriteForums ?? this.favoriteForums,
      currentFavoriteForum: clearCurrentFavoriteForum
          ? null
          : (currentFavoriteForum ?? this.currentFavoriteForum),
      isFavoriteMutationLoading:
          isFavoriteMutationLoading ?? this.isFavoriteMutationLoading,
      isLoading: isLoading ?? this.isLoading,
      loadingProgress: loadingProgress ?? this.loadingProgress,
    );
  }
}
