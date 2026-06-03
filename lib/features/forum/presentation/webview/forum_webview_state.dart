import 'package:y300/features/forum/domain/models/forum_webview_models.dart';

class ForumWebViewState {
  const ForumWebViewState({
    required this.currentUri,
    required this.pageKind,
    required this.isLoading,
    required this.loadingProgress,
  });

  final Uri currentUri;
  final ForumWebViewPageKind pageKind;
  final bool isLoading;
  final int loadingProgress;

  ForumWebViewState copyWith({
    Uri? currentUri,
    ForumWebViewPageKind? pageKind,
    bool? isLoading,
    int? loadingProgress,
  }) {
    return ForumWebViewState(
      currentUri: currentUri ?? this.currentUri,
      pageKind: pageKind ?? this.pageKind,
      isLoading: isLoading ?? this.isLoading,
      loadingProgress: loadingProgress ?? this.loadingProgress,
    );
  }
}
