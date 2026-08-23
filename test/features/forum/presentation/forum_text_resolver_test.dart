import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';
import 'package:y300/features/forum/presentation/forum_text_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_state.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations zhTw = AppLocalizationsZhTw();

  test('maps stable forum concepts through the active locale', () {
    expect(
      ForumTextResolver.forumShellModeLabel(zh, ForumShellMode.native),
      '解析模式',
    );
    expect(
      ForumTextResolver.forumShellModeLabel(zhTw, ForumShellMode.webview),
      zhTw.forumShellWebView,
    );
    expect(ForumTextResolver.forumDisplayTitle(zh, ''), zh.forumDisplayTitle);
    expect(ForumTextResolver.forumDisplayTitle(zh, '服务器版块名称'), '服务器版块名称');
  });

  test('keeps raw board names while localizing dynamic webview context', () {
    final state = _webViewState(
      pageKind: ForumWebViewPageKind.search,
      searchScope: ForumWebViewSearchScope.curForum,
      boardName: '服务器版块名称',
    );

    expect(
      ForumTextResolver.webViewTitle(zhTw, state),
      zhTw.forumWebViewForumSearch('服务器版块名称'),
    );
    expect(ForumTextResolver.searchTooltip(zh, state), zh.forumHomeSearch);
  });

  test('maps structured failures and empty details to localized messages', () {
    final notice = ForumHomeNotice(
      code: ForumHomeNoticeCode.refreshFailed,
      detail: 'network unavailable',
    );
    final failure = ForumDisplayFailure(
      code: ForumDisplayFailureCode.loadFailed,
      detail: '',
    );

    expect(
      ForumTextResolver.homeNotice(zh, notice),
      zh.forumHomeRefreshFailed('network unavailable'),
    );
    expect(
      ForumTextResolver.displayFailure(zhTw, failure),
      zhTw.forumDisplayLoadFailed(zhTw.commonUnknownError),
    );
  });

  test('redacts sensitive error details before presentation', () {
    final summary = ForumTextResolver.safeErrorSummary(
      'Cookie=secret-token https://bbs.yamibo.com/forum.php\nnext line',
    );

    expect(summary, isNot(contains('secret-token')));
    expect(summary, isNot(contains('https://')));
    expect(summary, isNot(contains('\n')));
    expect(summary.length, lessThanOrEqualTo(160));
  });
}

ForumWebViewState _webViewState({
  required ForumWebViewPageKind pageKind,
  ForumWebViewSearchScope? searchScope,
  String? boardName,
}) {
  return ForumWebViewState(
    currentUri: Uri.parse('https://bbs.yamibo.com/'),
    pageKind: pageKind,
    searchScope: searchScope,
    fid: null,
    tid: null,
    boardName: boardName,
    pageTitle: null,
    canGoBack: false,
    favoriteForums: const [],
    favoriteForumCapabilities: null,
    favoriteForumMetadata: null,
    currentFavoriteForum: null,
    isFavoriteMutationLoading: false,
    threadDetailMenu: null,
    isLoading: false,
    loadingProgress: 100,
  );
}
