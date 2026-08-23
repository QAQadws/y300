import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';
import 'package:y300/features/favorites/domain/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';

class ForumWebViewState {
  const ForumWebViewState({
    required this.currentUri,
    required this.pageKind,
    required this.searchScope,
    required this.fid,
    required this.tid,
    required this.boardName,
    required this.pageTitle,
    required this.canGoBack,
    required this.favoriteForums,
    required this.favoriteForumCapabilities,
    required this.favoriteForumMetadata,
    required this.currentFavoriteForum,
    required this.isFavoriteMutationLoading,
    required this.threadDetailMenu,
    required this.isLoading,
    required this.loadingProgress,
  });

  final Uri currentUri;
  final ForumWebViewPageKind pageKind;
  final ForumWebViewSearchScope? searchScope;
  final String? fid;
  final String? tid;
  final String? boardName;
  final String? pageTitle;
  final bool canGoBack;
  final List<FavoriteForumEntry> favoriteForums;
  final FavoriteForumDirectoryReadCapabilities? favoriteForumCapabilities;
  final DataReadMetadata? favoriteForumMetadata;
  final FavoriteForumEntry? currentFavoriteForum;
  final bool isFavoriteMutationLoading;
  final ForumThreadDetailMenuState? threadDetailMenu;
  final bool isLoading;
  final int loadingProgress;

  ForumWebViewState copyWith({
    Uri? currentUri,
    ForumWebViewPageKind? pageKind,
    ForumWebViewSearchScope? searchScope,
    bool clearSearchScope = false,
    String? fid,
    bool clearFid = false,
    String? tid,
    bool clearTid = false,
    String? boardName,
    bool clearBoardName = false,
    String? pageTitle,
    bool clearPageTitle = false,
    bool? canGoBack,
    List<FavoriteForumEntry>? favoriteForums,
    FavoriteForumDirectoryReadCapabilities? favoriteForumCapabilities,
    DataReadMetadata? favoriteForumMetadata,
    FavoriteForumEntry? currentFavoriteForum,
    bool clearCurrentFavoriteForum = false,
    bool? isFavoriteMutationLoading,
    ForumThreadDetailMenuState? threadDetailMenu,
    bool clearThreadDetailMenu = false,
    bool? isLoading,
    int? loadingProgress,
  }) {
    return ForumWebViewState(
      currentUri: currentUri ?? this.currentUri,
      pageKind: pageKind ?? this.pageKind,
      searchScope: clearSearchScope ? null : (searchScope ?? this.searchScope),
      fid: clearFid ? null : (fid ?? this.fid),
      tid: clearTid ? null : (tid ?? this.tid),
      boardName: clearBoardName ? null : (boardName ?? this.boardName),
      pageTitle: clearPageTitle ? null : (pageTitle ?? this.pageTitle),
      canGoBack: canGoBack ?? this.canGoBack,
      favoriteForums: favoriteForums ?? this.favoriteForums,
      favoriteForumCapabilities:
          favoriteForumCapabilities ?? this.favoriteForumCapabilities,
      favoriteForumMetadata:
          favoriteForumMetadata ?? this.favoriteForumMetadata,
      currentFavoriteForum: clearCurrentFavoriteForum
          ? null
          : (currentFavoriteForum ?? this.currentFavoriteForum),
      isFavoriteMutationLoading:
          isFavoriteMutationLoading ?? this.isFavoriteMutationLoading,
      threadDetailMenu: clearThreadDetailMenu
          ? null
          : (threadDetailMenu ?? this.threadDetailMenu),
      isLoading: isLoading ?? this.isLoading,
      loadingProgress: loadingProgress ?? this.loadingProgress,
    );
  }
}
