import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// 应用设置中的界面语言分区标题
  ///
  /// In zh, this message translates to:
  /// **'界面语言'**
  String get appLanguageSectionTitle;

  /// 跟随设备系统语言
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get appLanguageSystem;

  /// 将应用界面设置为简体中文
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get appLanguageSimplifiedChinese;

  /// 将应用界面设置为繁体中文
  ///
  /// In zh, this message translates to:
  /// **'繁体中文'**
  String get appLanguageTraditionalChinese;

  /// 保存界面语言失败时显示的错误提示
  ///
  /// In zh, this message translates to:
  /// **'语言设置保存失败：{error}'**
  String appLanguageSaveFailed(String error);

  /// No description provided for @appLanguageSystemContentDescription.
  ///
  /// In zh, this message translates to:
  /// **'界面语言跟随设备，服务器内容保持原文'**
  String get appLanguageSystemContentDescription;

  /// No description provided for @appLanguageSimplifiedContentDescription.
  ///
  /// In zh, this message translates to:
  /// **'界面使用简体，原生解析内容转换为简体'**
  String get appLanguageSimplifiedContentDescription;

  /// No description provided for @appLanguageTraditionalContentDescription.
  ///
  /// In zh, this message translates to:
  /// **'界面使用繁体，原生解析内容转换为繁体'**
  String get appLanguageTraditionalContentDescription;

  /// No description provided for @appLanguageContentNote.
  ///
  /// In zh, this message translates to:
  /// **'用户名和网页模式内容保持原样'**
  String get appLanguageContentNote;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get commonConfirm;

  /// No description provided for @commonClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get commonClose;

  /// No description provided for @commonClear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get commonClear;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @commonApply.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get commonApply;

  /// No description provided for @commonSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @commonRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get commonRemove;

  /// No description provided for @commonUnknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get commonUnknownError;

  /// No description provided for @forumHomeTitle.
  ///
  /// In zh, this message translates to:
  /// **'论坛首页'**
  String get forumHomeTitle;

  /// No description provided for @forumHomeSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索论坛'**
  String get forumHomeSearch;

  /// No description provided for @forumHomeRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新论坛首页'**
  String get forumHomeRefresh;

  /// No description provided for @forumHomeEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无论坛版块'**
  String get forumHomeEmpty;

  /// 论坛首页首屏加载失败；error 是 presentation 层清理后的安全摘要
  ///
  /// In zh, this message translates to:
  /// **'论坛首页加载失败：{error}'**
  String forumHomeLoadFailed(String error);

  /// 论坛首页刷新失败；error 是 presentation 层清理后的安全摘要
  ///
  /// In zh, this message translates to:
  /// **'刷新论坛首页失败：{error}'**
  String forumHomeRefreshFailed(String error);

  /// No description provided for @forumHomeFavoriteForums.
  ///
  /// In zh, this message translates to:
  /// **'我收藏的版块'**
  String get forumHomeFavoriteForums;

  /// No description provided for @forumHomeUncategorized.
  ///
  /// In zh, this message translates to:
  /// **'未分类'**
  String get forumHomeUncategorized;

  /// No description provided for @forumDisplayTitle.
  ///
  /// In zh, this message translates to:
  /// **'帖子列表'**
  String get forumDisplayTitle;

  /// No description provided for @forumDisplaySearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索本版'**
  String get forumDisplaySearch;

  /// No description provided for @forumDisplayCreateThread.
  ///
  /// In zh, this message translates to:
  /// **'发帖'**
  String get forumDisplayCreateThread;

  /// No description provided for @forumDisplayToday.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get forumDisplayToday;

  /// No description provided for @forumDisplayThreads.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get forumDisplayThreads;

  /// No description provided for @forumDisplayRank.
  ///
  /// In zh, this message translates to:
  /// **'排名'**
  String get forumDisplayRank;

  /// No description provided for @forumDisplaySubForum.
  ///
  /// In zh, this message translates to:
  /// **'子版块'**
  String get forumDisplaySubForum;

  /// No description provided for @forumDisplayAnnouncements.
  ///
  /// In zh, this message translates to:
  /// **'公告'**
  String get forumDisplayAnnouncements;

  /// No description provided for @forumDisplayPinned.
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get forumDisplayPinned;

  /// No description provided for @forumDisplayAnonymous.
  ///
  /// In zh, this message translates to:
  /// **'匿名'**
  String get forumDisplayAnonymous;

  /// No description provided for @forumDisplayPreviousPage.
  ///
  /// In zh, this message translates to:
  /// **'上一页'**
  String get forumDisplayPreviousPage;

  /// No description provided for @forumDisplayNextPage.
  ///
  /// In zh, this message translates to:
  /// **'下一页'**
  String get forumDisplayNextPage;

  /// No description provided for @forumDisplayNoMore.
  ///
  /// In zh, this message translates to:
  /// **'没有更多'**
  String get forumDisplayNoMore;

  /// 论坛列表当前页按钮；page 是当前页码
  ///
  /// In zh, this message translates to:
  /// **'第{page}页'**
  String forumDisplayPage(int page);

  /// No description provided for @forumDisplayEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无帖子'**
  String get forumDisplayEmpty;

  /// 论坛列表加载失败；error 是 presentation 层清理后的安全摘要
  ///
  /// In zh, this message translates to:
  /// **'帖子列表加载失败：{error}'**
  String forumDisplayLoadFailed(String error);

  /// No description provided for @forumDisplayCopiedLink.
  ///
  /// In zh, this message translates to:
  /// **'已复制帖子链接'**
  String get forumDisplayCopiedLink;

  /// No description provided for @forumShellNative.
  ///
  /// In zh, this message translates to:
  /// **'解析模式'**
  String get forumShellNative;

  /// No description provided for @forumShellWebView.
  ///
  /// In zh, this message translates to:
  /// **'WebView 模式'**
  String get forumShellWebView;

  /// No description provided for @forumWebViewLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在加载论坛页面'**
  String get forumWebViewLoading;

  /// 受管论坛 WebView 加载失败；error 是安全摘要
  ///
  /// In zh, this message translates to:
  /// **'论坛页面加载失败：{error}'**
  String forumWebViewLoadFailed(String error);

  /// No description provided for @forumWebViewRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试加载'**
  String get forumWebViewRetry;

  /// No description provided for @forumWebViewOpenExternal.
  ///
  /// In zh, this message translates to:
  /// **'在外部打开'**
  String get forumWebViewOpenExternal;

  /// No description provided for @forumWebViewOpenExternalFailed.
  ///
  /// In zh, this message translates to:
  /// **'打开外部链接失败'**
  String get forumWebViewOpenExternalFailed;

  /// No description provided for @forumWebViewClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭论坛页面'**
  String get forumWebViewClose;

  /// No description provided for @forumWebViewReplyThread.
  ///
  /// In zh, this message translates to:
  /// **'回复帖子'**
  String get forumWebViewReplyThread;

  /// No description provided for @forumWebViewRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新页面'**
  String get forumWebViewRefresh;

  /// No description provided for @forumWebViewBackHome.
  ///
  /// In zh, this message translates to:
  /// **'返回首页'**
  String get forumWebViewBackHome;

  /// No description provided for @forumWebViewFeatureInProgress.
  ///
  /// In zh, this message translates to:
  /// **'功能开发中'**
  String get forumWebViewFeatureInProgress;

  /// No description provided for @forumWebViewProcessing.
  ///
  /// In zh, this message translates to:
  /// **'处理中'**
  String get forumWebViewProcessing;

  /// No description provided for @forumWebViewFavoriteForum.
  ///
  /// In zh, this message translates to:
  /// **'收藏本版'**
  String get forumWebViewFavoriteForum;

  /// No description provided for @forumWebViewUnfavoriteForum.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get forumWebViewUnfavoriteForum;

  /// No description provided for @forumWebViewCancelFavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get forumWebViewCancelFavorite;

  /// No description provided for @forumWebViewFavoriteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已收藏本版'**
  String get forumWebViewFavoriteSuccess;

  /// No description provided for @forumWebViewUnfavoriteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已取消收藏本版'**
  String get forumWebViewUnfavoriteSuccess;

  /// WebView 论坛操作失败；error 是安全摘要
  ///
  /// In zh, this message translates to:
  /// **'操作失败，请稍后重试：{error}'**
  String forumWebViewActionFailed(String error);

  /// No description provided for @forumWebViewFavoriteForumsTitle.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get forumWebViewFavoriteForumsTitle;

  /// 收藏版块列表加载失败；error 是安全摘要
  ///
  /// In zh, this message translates to:
  /// **'加载收藏版块失败：{error}'**
  String forumWebViewFavoriteForumsLoadFailed(String error);

  /// No description provided for @forumWebViewNoFavoriteForums.
  ///
  /// In zh, this message translates to:
  /// **'暂无收藏版块'**
  String get forumWebViewNoFavoriteForums;

  /// No description provided for @forumWebViewAuthorOnly.
  ///
  /// In zh, this message translates to:
  /// **'只看楼主'**
  String get forumWebViewAuthorOnly;

  /// No description provided for @forumWebViewAllPosts.
  ///
  /// In zh, this message translates to:
  /// **'看全部'**
  String get forumWebViewAllPosts;

  /// No description provided for @forumWebViewNormalOrder.
  ///
  /// In zh, this message translates to:
  /// **'正序浏览'**
  String get forumWebViewNormalOrder;

  /// No description provided for @forumWebViewReverseOrder.
  ///
  /// In zh, this message translates to:
  /// **'倒序浏览'**
  String get forumWebViewReverseOrder;

  /// No description provided for @forumWebViewLocationFallback.
  ///
  /// In zh, this message translates to:
  /// **'楼层定位失败，已打开帖子'**
  String get forumWebViewLocationFallback;

  /// No description provided for @forumWebViewPostLinkFallback.
  ///
  /// In zh, this message translates to:
  /// **'帖子链接解析失败，已在网页中打开'**
  String get forumWebViewPostLinkFallback;

  /// No description provided for @forumWebViewReplySuccess.
  ///
  /// In zh, this message translates to:
  /// **'回复成功'**
  String get forumWebViewReplySuccess;

  /// No description provided for @forumWebViewPostSuccess.
  ///
  /// In zh, this message translates to:
  /// **'发布成功'**
  String get forumWebViewPostSuccess;

  /// 当前版块搜索页标题；board 是服务器返回的版块名
  ///
  /// In zh, this message translates to:
  /// **'{board}搜索'**
  String forumWebViewForumSearch(String board);

  /// No description provided for @forumWebViewSearchForum.
  ///
  /// In zh, this message translates to:
  /// **'论坛搜索'**
  String get forumWebViewSearchForum;

  /// 无法解析版块名称时的安全标题；fid 是原始版块 ID
  ///
  /// In zh, this message translates to:
  /// **'fid={fid}'**
  String forumWebViewForumByFid(String fid);

  /// No description provided for @historyTitle.
  ///
  /// In zh, this message translates to:
  /// **'记录'**
  String get historyTitle;

  /// No description provided for @historySearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索记录'**
  String get historySearchHint;

  /// No description provided for @historySearchOpen.
  ///
  /// In zh, this message translates to:
  /// **'搜索记录'**
  String get historySearchOpen;

  /// No description provided for @historySearchClose.
  ///
  /// In zh, this message translates to:
  /// **'退出搜索'**
  String get historySearchClose;

  /// No description provided for @historySearchClear.
  ///
  /// In zh, this message translates to:
  /// **'清除搜索'**
  String get historySearchClear;

  /// No description provided for @historyClearAll.
  ///
  /// In zh, this message translates to:
  /// **'清空记录'**
  String get historyClearAll;

  /// No description provided for @historyDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除记录'**
  String get historyDelete;

  /// No description provided for @historyOpenSourceThread.
  ///
  /// In zh, this message translates to:
  /// **'打开原帖'**
  String get historyOpenSourceThread;

  /// No description provided for @historyOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'打开失败，请稍后重试'**
  String get historyOpenFailed;

  /// 打开历史目标失败的安全摘要；error 已由 presentation 层清理
  ///
  /// In zh, this message translates to:
  /// **'打开失败：{error}'**
  String historyOpenFailedDetail(String error);

  /// No description provided for @historyDeleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除记录失败'**
  String get historyDeleteFailed;

  /// No description provided for @historyClearAllFailed.
  ///
  /// In zh, this message translates to:
  /// **'清空记录失败'**
  String get historyClearAllFailed;

  /// No description provided for @historyClearAllTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空全部记录'**
  String get historyClearAllTitle;

  /// No description provided for @historyClearAllBody.
  ///
  /// In zh, this message translates to:
  /// **'浏览记录将被清空，但不会删除收藏、书架作品或下载内容。'**
  String get historyClearAllBody;

  /// No description provided for @historyNoResults.
  ///
  /// In zh, this message translates to:
  /// **'没有搜索结果'**
  String get historyNoResults;

  /// No description provided for @historyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有浏览记录'**
  String get historyEmpty;

  /// No description provided for @historyLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'记录加载失败'**
  String get historyLoadFailed;

  /// No description provided for @historyLoadMoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败，点击重试'**
  String get historyLoadMoreFailed;

  /// No description provided for @historyTypeThread.
  ///
  /// In zh, this message translates to:
  /// **'帖子'**
  String get historyTypeThread;

  /// No description provided for @historyTypeComic.
  ///
  /// In zh, this message translates to:
  /// **'漫画'**
  String get historyTypeComic;

  /// No description provided for @historyTypeNovel.
  ///
  /// In zh, this message translates to:
  /// **'小说'**
  String get historyTypeNovel;

  /// No description provided for @historySourceThread.
  ///
  /// In zh, this message translates to:
  /// **'来源原帖'**
  String get historySourceThread;

  /// No description provided for @historyToday.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get historyToday;

  /// 历史日期分组相对今天的天数
  ///
  /// In zh, this message translates to:
  /// **'{days, plural, =1 {1 天前} other {{days} 天前}}'**
  String historyDaysAgo(int days);

  /// No description provided for @historyTargetInvalid.
  ///
  /// In zh, this message translates to:
  /// **'记录目标无效'**
  String get historyTargetInvalid;

  /// No description provided for @historyPageClosed.
  ///
  /// In zh, this message translates to:
  /// **'当前页面已关闭'**
  String get historyPageClosed;

  /// No description provided for @historyThreadExpired.
  ///
  /// In zh, this message translates to:
  /// **'帖子记录已失效'**
  String get historyThreadExpired;

  /// 历史中的漫画或小说作品不再存在时显示；type 是本地化类型名称
  ///
  /// In zh, this message translates to:
  /// **'该{type}作品已从本地移除'**
  String historyWorkUnavailable(String type);

  /// No description provided for @historyNativeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前无法打开原生页面'**
  String get historyNativeUnavailable;

  /// No description provided for @historyLoginRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先登录后再打开此记录'**
  String get historyLoginRequired;

  /// No description provided for @appNavigationForum.
  ///
  /// In zh, this message translates to:
  /// **'论坛'**
  String get appNavigationForum;

  /// No description provided for @appNavigationFavorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get appNavigationFavorites;

  /// No description provided for @appNavigationComic.
  ///
  /// In zh, this message translates to:
  /// **'漫画'**
  String get appNavigationComic;

  /// No description provided for @appNavigationNovel.
  ///
  /// In zh, this message translates to:
  /// **'小说'**
  String get appNavigationNovel;

  /// No description provided for @appNavigationHistory.
  ///
  /// In zh, this message translates to:
  /// **'记录'**
  String get appNavigationHistory;

  /// No description provided for @appNavigationMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get appNavigationMore;

  /// 多选主壳标题；count 是当前选中的项目数量
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {未选择项目} other {已选 {count} 项}}'**
  String librarySelectionSelectedCount(int count);

  /// No description provided for @librarySelectionExit.
  ///
  /// In zh, this message translates to:
  /// **'退出多选'**
  String get librarySelectionExit;

  /// No description provided for @librarySelectionSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选当前分类'**
  String get librarySelectionSelectAll;

  /// No description provided for @librarySelectionInvert.
  ///
  /// In zh, this message translates to:
  /// **'反选当前分类'**
  String get librarySelectionInvert;

  /// No description provided for @librarySelectionActionAssignCategory.
  ///
  /// In zh, this message translates to:
  /// **'设置分类'**
  String get librarySelectionActionAssignCategory;

  /// No description provided for @librarySelectionActionMarkAllRead.
  ///
  /// In zh, this message translates to:
  /// **'全部已读'**
  String get librarySelectionActionMarkAllRead;

  /// No description provided for @librarySelectionActionMarkAllUnread.
  ///
  /// In zh, this message translates to:
  /// **'全部未读'**
  String get librarySelectionActionMarkAllUnread;

  /// No description provided for @librarySelectionActionDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get librarySelectionActionDownload;

  /// No description provided for @librarySelectionActionUnfavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get librarySelectionActionUnfavorite;

  /// No description provided for @librarySelectionActionGeneric.
  ///
  /// In zh, this message translates to:
  /// **'执行操作'**
  String get librarySelectionActionGeneric;

  /// 批量操作异常提示；error 是经过清理的安全错误摘要
  ///
  /// In zh, this message translates to:
  /// **'批量操作失败：{error}'**
  String librarySelectionActionFailed(String error);

  /// No description provided for @librarySelectionConfirmUnfavoriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认取消收藏'**
  String get librarySelectionConfirmUnfavoriteTitle;

  /// No description provided for @librarySelectionConfirmActionTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认执行操作'**
  String get librarySelectionConfirmActionTitle;

  /// 取消收藏确认正文；count 是选中项目数量
  ///
  /// In zh, this message translates to:
  /// **'将取消已选 {count, plural, =0 {0 项} other {{count} 项}}收藏。若作品已无其它活跃收藏来源，相关本地作品、章节、封面缓存和下载也会被清除。是否继续？'**
  String librarySelectionConfirmUnfavoriteBody(int count);

  /// 普通多选动作确认正文；action 是由稳定 action id 映射的本地化名称
  ///
  /// In zh, this message translates to:
  /// **'将对已选 {count, plural, =0 {0 项} other {{count} 项}}执行“{action}”，是否继续？'**
  String librarySelectionConfirmActionBody(int count, String action);

  /// No description provided for @librarySelectionSelectCategory.
  ///
  /// In zh, this message translates to:
  /// **'选择分类'**
  String get librarySelectionSelectCategory;

  /// No description provided for @librarySelectionCreateCategory.
  ///
  /// In zh, this message translates to:
  /// **'新建分类'**
  String get librarySelectionCreateCategory;

  /// No description provided for @librarySelectionCategoryNameHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入分类名称'**
  String get librarySelectionCategoryNameHint;

  /// 批量设置分类成功提示；count 是成功处理的项目数量
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {没有项目设置分类} other {已为 {count} 项设置分类}}'**
  String librarySelectionCategoryAssigned(int count);

  /// 批量设置分类部分失败提示
  ///
  /// In zh, this message translates to:
  /// **'{succeededCount, plural, =0 {没有项目设置分类} other {已为 {succeededCount} 项设置分类}}；{failedCount, plural, =0 {没有失败项目} other {失败 {failedCount} 项}}'**
  String librarySelectionCategoryAssignedPartial(
    int succeededCount,
    int failedCount,
  );

  /// 批量阅读状态修改成功提示；state 是已读或未读的本地化名称
  ///
  /// In zh, this message translates to:
  /// **'已将 {count, plural, =0 {0 项} other {{count} 项}}标记为{state}'**
  String librarySelectionReadStateChanged(int count, String state);

  /// 批量阅读状态修改部分失败提示
  ///
  /// In zh, this message translates to:
  /// **'已将 {succeededCount, plural, =0 {0 项} other {{succeededCount} 项}}标记为{state}；{failedCount, plural, =0 {没有失败项目} other {失败 {failedCount} 项}}'**
  String librarySelectionReadStateChangedPartial(
    int succeededCount,
    int failedCount,
    String state,
  );

  /// No description provided for @librarySelectionRead.
  ///
  /// In zh, this message translates to:
  /// **'已读'**
  String get librarySelectionRead;

  /// No description provided for @librarySelectionUnread.
  ///
  /// In zh, this message translates to:
  /// **'未读'**
  String get librarySelectionUnread;

  /// 批量下载入队提示；count 是新加入队列的章节数量
  ///
  /// In zh, this message translates to:
  /// **'已将 {count, plural, =0 {0 个章节} other {{count} 个章节}}加入下载队列'**
  String librarySelectionDownloadQueued(int count);

  /// 批量下载入队部分失败提示
  ///
  /// In zh, this message translates to:
  /// **'已将 {count, plural, =0 {0 个章节} other {{count} 个章节}}加入下载队列；{failedCount, plural, =0 {没有失败项目} other {失败 {failedCount} 项}}'**
  String librarySelectionDownloadQueuedPartial(int count, int failedCount);

  /// No description provided for @librarySelectionDownloadAlreadyQueued.
  ///
  /// In zh, this message translates to:
  /// **'所选章节已在下载队列中'**
  String get librarySelectionDownloadAlreadyQueued;

  /// No description provided for @librarySelectionNothingToDownload.
  ///
  /// In zh, this message translates to:
  /// **'没有需要下载的章节'**
  String get librarySelectionNothingToDownload;

  /// 批量取消收藏成功提示；count 是成功取消的项目数量
  ///
  /// In zh, this message translates to:
  /// **'已取消 {count, plural, =0 {0 项} other {{count} 项}}收藏'**
  String librarySelectionUnfavorite(int count);

  /// 批量取消收藏部分失败提示
  ///
  /// In zh, this message translates to:
  /// **'已取消 {succeededCount, plural, =0 {0 项} other {{succeededCount} 项}}收藏；{failedCount, plural, =0 {没有失败项目} other {失败 {failedCount} 项}}'**
  String librarySelectionUnfavoritePartial(int succeededCount, int failedCount);

  /// 当前书架不支持某个批量动作；action 是本地化动作名称
  ///
  /// In zh, this message translates to:
  /// **'当前不支持批量{action}'**
  String librarySelectionUnsupported(String action);

  /// No description provided for @librarySelectionMissingTargetCategory.
  ///
  /// In zh, this message translates to:
  /// **'请选择目标分类'**
  String get librarySelectionMissingTargetCategory;

  /// No description provided for @librarySelectionNoValidItems.
  ///
  /// In zh, this message translates to:
  /// **'没有可处理的项目'**
  String get librarySelectionNoValidItems;

  /// 批量动作没有产生变化；action 是本地化动作名称
  ///
  /// In zh, this message translates to:
  /// **'没有可执行的{action}'**
  String librarySelectionNoChange(String action);

  /// 统一书架标题；module 是稳定 LibraryModuleKey 名称
  ///
  /// In zh, this message translates to:
  /// **'{module, select, comic {漫画} novel {小说} favorite {收藏} other {书架}}'**
  String libraryShelfTitle(String module);

  /// 统一书架加载失败；error 是 presentation 层清理后的安全摘要
  ///
  /// In zh, this message translates to:
  /// **'加载书架失败：{error}'**
  String libraryShelfLoadFailed(String error);

  /// No description provided for @libraryShelfEmpty.
  ///
  /// In zh, this message translates to:
  /// **'书架为空'**
  String get libraryShelfEmpty;

  /// No description provided for @libraryShelfSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索书架'**
  String get libraryShelfSearch;

  /// No description provided for @libraryShelfSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索作品'**
  String get libraryShelfSearchHint;

  /// No description provided for @libraryShelfFilterAndSort.
  ///
  /// In zh, this message translates to:
  /// **'筛选与排序'**
  String get libraryShelfFilterAndSort;

  /// No description provided for @libraryShelfCreateCategory.
  ///
  /// In zh, this message translates to:
  /// **'新建分类'**
  String get libraryShelfCreateCategory;

  /// No description provided for @libraryShelfRenameCategory.
  ///
  /// In zh, this message translates to:
  /// **'重命名当前分类'**
  String get libraryShelfRenameCategory;

  /// No description provided for @libraryShelfDeleteCategory.
  ///
  /// In zh, this message translates to:
  /// **'删除当前分类'**
  String get libraryShelfDeleteCategory;

  /// No description provided for @libraryShelfDeleteCategoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除分类'**
  String get libraryShelfDeleteCategoryTitle;

  /// No description provided for @libraryShelfDeleteCategoryBody.
  ///
  /// In zh, this message translates to:
  /// **'删除后，该分类中的作品会移动到默认分类。是否继续？'**
  String get libraryShelfDeleteCategoryBody;

  /// No description provided for @libraryShelfDefaultCategory.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get libraryShelfDefaultCategory;

  /// No description provided for @libraryShelfDefaultCategoryCannotRename.
  ///
  /// In zh, this message translates to:
  /// **'默认分类不支持重命名'**
  String get libraryShelfDefaultCategoryCannotRename;

  /// No description provided for @libraryShelfDefaultCategoryCannotDelete.
  ///
  /// In zh, this message translates to:
  /// **'默认分类不支持删除'**
  String get libraryShelfDefaultCategoryCannotDelete;

  /// No description provided for @libraryShelfCategoryNameHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入分类名称'**
  String get libraryShelfCategoryNameHint;

  /// 搜索时的分类标签；name 是数据库中的原始分类名
  ///
  /// In zh, this message translates to:
  /// **'{name} {count, plural, =0 {0} other {{count}}}'**
  String libraryShelfCategoryMatchCount(String name, int count);

  /// No description provided for @libraryShelfUpdate.
  ///
  /// In zh, this message translates to:
  /// **'更新书架'**
  String get libraryShelfUpdate;

  /// No description provided for @libraryShelfRandomOpen.
  ///
  /// In zh, this message translates to:
  /// **'随机打开作品'**
  String get libraryShelfRandomOpen;

  /// No description provided for @libraryShelfNoRandomWork.
  ///
  /// In zh, this message translates to:
  /// **'当前分类没有可打开的作品'**
  String get libraryShelfNoRandomWork;

  /// No description provided for @libraryShelfFilter.
  ///
  /// In zh, this message translates to:
  /// **'筛选'**
  String get libraryShelfFilter;

  /// No description provided for @libraryShelfSort.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get libraryShelfSort;

  /// No description provided for @libraryShelfDisplayMode.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get libraryShelfDisplayMode;

  /// No description provided for @libraryShelfGrid.
  ///
  /// In zh, this message translates to:
  /// **'网格'**
  String get libraryShelfGrid;

  /// No description provided for @libraryShelfList.
  ///
  /// In zh, this message translates to:
  /// **'列表'**
  String get libraryShelfList;

  /// No description provided for @libraryShelfColumnsPerRow.
  ///
  /// In zh, this message translates to:
  /// **'每行个数'**
  String get libraryShelfColumnsPerRow;

  /// No description provided for @libraryShelfFilterDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'已下载'**
  String get libraryShelfFilterDownloaded;

  /// No description provided for @libraryShelfFilterUnread.
  ///
  /// In zh, this message translates to:
  /// **'未读'**
  String get libraryShelfFilterUnread;

  /// No description provided for @libraryShelfFilterRead.
  ///
  /// In zh, this message translates to:
  /// **'阅读过'**
  String get libraryShelfFilterRead;

  /// No description provided for @libraryShelfFilterBookmarked.
  ///
  /// In zh, this message translates to:
  /// **'有书签'**
  String get libraryShelfFilterBookmarked;

  /// No description provided for @libraryShelfSortName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get libraryShelfSortName;

  /// No description provided for @libraryShelfSortChapterCount.
  ///
  /// In zh, this message translates to:
  /// **'章节数'**
  String get libraryShelfSortChapterCount;

  /// No description provided for @libraryShelfSortLastReadAt.
  ///
  /// In zh, this message translates to:
  /// **'最近阅读'**
  String get libraryShelfSortLastReadAt;

  /// No description provided for @libraryShelfSortLastCheckedAt.
  ///
  /// In zh, this message translates to:
  /// **'最近检查'**
  String get libraryShelfSortLastCheckedAt;

  /// No description provided for @libraryShelfSortUnreadCount.
  ///
  /// In zh, this message translates to:
  /// **'未读章节数'**
  String get libraryShelfSortUnreadCount;

  /// No description provided for @libraryShelfSortWorkUpdatedAt.
  ///
  /// In zh, this message translates to:
  /// **'作品更新时间'**
  String get libraryShelfSortWorkUpdatedAt;

  /// No description provided for @libraryShelfSortFetchedAt.
  ///
  /// In zh, this message translates to:
  /// **'获取时间'**
  String get libraryShelfSortFetchedAt;

  /// No description provided for @libraryShelfSortFavoriteAddedAt.
  ///
  /// In zh, this message translates to:
  /// **'收藏日期'**
  String get libraryShelfSortFavoriteAddedAt;

  /// No description provided for @libraryShelfMergeDuplicates.
  ///
  /// In zh, this message translates to:
  /// **'合并重复'**
  String get libraryShelfMergeDuplicates;

  /// 漫画书架合并重复项成功提示
  ///
  /// In zh, this message translates to:
  /// **'已合并 {count, plural, =0 {0 个重复作品} other {{count} 个重复作品}}'**
  String libraryShelfMergeDuplicatesSuccess(int count);

  /// No description provided for @libraryShelfMergeDuplicatesNoChange.
  ///
  /// In zh, this message translates to:
  /// **'没有可合并的重复作品'**
  String get libraryShelfMergeDuplicatesNoChange;

  /// No description provided for @libraryShelfActionUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前书架不支持此操作'**
  String get libraryShelfActionUnsupported;

  /// No description provided for @libraryTaskCoverWarmup.
  ///
  /// In zh, this message translates to:
  /// **'正在准备封面'**
  String get libraryTaskCoverWarmup;

  /// No description provided for @libraryTaskFavoriteSyncFetching.
  ///
  /// In zh, this message translates to:
  /// **'正在获取收藏列表'**
  String get libraryTaskFavoriteSyncFetching;

  /// No description provided for @libraryTaskFavoriteSyncSaving.
  ///
  /// In zh, this message translates to:
  /// **'正在保存收藏数据'**
  String get libraryTaskFavoriteSyncSaving;

  /// No description provided for @libraryTaskFavoriteSyncLoadingDetails.
  ///
  /// In zh, this message translates to:
  /// **'正在读取收藏详情'**
  String get libraryTaskFavoriteSyncLoadingDetails;

  /// 收藏同步读取详情；subject 是原始作品标题
  ///
  /// In zh, this message translates to:
  /// **'正在读取《{subject}》'**
  String libraryTaskFavoriteSyncLoadingDetailsSubject(String subject);

  /// No description provided for @libraryTaskFavoriteSyncFinishing.
  ///
  /// In zh, this message translates to:
  /// **'正在完成收藏同步'**
  String get libraryTaskFavoriteSyncFinishing;

  /// No description provided for @libraryTaskComicSearchWaiting.
  ///
  /// In zh, this message translates to:
  /// **'漫画搜索正在等待'**
  String get libraryTaskComicSearchWaiting;

  /// 漫画搜索队列等待；subject 是原始作品标题
  ///
  /// In zh, this message translates to:
  /// **'《{subject}》正在等待搜索'**
  String libraryTaskComicSearchWaitingSubject(String subject);

  /// 漫画搜索队列等待；subject 原样显示，duration 已本地化
  ///
  /// In zh, this message translates to:
  /// **'《{subject}》正在等待搜索，预计 {duration}'**
  String libraryTaskComicSearchWaitingDuration(String subject, String duration);

  /// No description provided for @libraryTaskDurationSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =1 {1 秒} other {{count} 秒}}'**
  String libraryTaskDurationSeconds(int count);

  /// No description provided for @libraryTaskDurationMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =1 {1 分钟} other {{count} 分钟}}'**
  String libraryTaskDurationMinutes(int count);

  /// No description provided for @libraryTaskFavoriteSyncNotificationTitle.
  ///
  /// In zh, this message translates to:
  /// **'收藏同步'**
  String get libraryTaskFavoriteSyncNotificationTitle;

  /// No description provided for @libraryTaskComicSearchNotificationTitle.
  ///
  /// In zh, this message translates to:
  /// **'漫画搜索'**
  String get libraryTaskComicSearchNotificationTitle;

  /// No description provided for @libraryTaskNotificationTitle.
  ///
  /// In zh, this message translates to:
  /// **'书架任务'**
  String get libraryTaskNotificationTitle;

  /// No description provided for @libraryDetailDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get libraryDetailDownload;

  /// No description provided for @libraryDetailFilterAndSort.
  ///
  /// In zh, this message translates to:
  /// **'筛选与排序'**
  String get libraryDetailFilterAndSort;

  /// No description provided for @libraryDetailRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get libraryDetailRefresh;

  /// No description provided for @libraryDetailChangeCategory.
  ///
  /// In zh, this message translates to:
  /// **'修改分类'**
  String get libraryDetailChangeCategory;

  /// No description provided for @libraryDetailEditMetadata.
  ///
  /// In zh, this message translates to:
  /// **'编辑作品信息'**
  String get libraryDetailEditMetadata;

  /// No description provided for @libraryDetailConfigureCatalog.
  ///
  /// In zh, this message translates to:
  /// **'配置目录'**
  String get libraryDetailConfigureCatalog;

  /// No description provided for @libraryDetailManageChapters.
  ///
  /// In zh, this message translates to:
  /// **'管理章节'**
  String get libraryDetailManageChapters;

  /// No description provided for @libraryDetailSetCustomCover.
  ///
  /// In zh, this message translates to:
  /// **'自定义封面'**
  String get libraryDetailSetCustomCover;

  /// No description provided for @libraryDetailRemoveCustomCover.
  ///
  /// In zh, this message translates to:
  /// **'取消封面'**
  String get libraryDetailRemoveCustomCover;

  /// No description provided for @libraryDetailEditIntro.
  ///
  /// In zh, this message translates to:
  /// **'编辑简介'**
  String get libraryDetailEditIntro;

  /// No description provided for @libraryDetailIntroHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入简介'**
  String get libraryDetailIntroHint;

  /// No description provided for @libraryDetailNoIntro.
  ///
  /// In zh, this message translates to:
  /// **'暂无简介'**
  String get libraryDetailNoIntro;

  /// No description provided for @libraryDetailContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get libraryDetailContinue;

  /// No description provided for @libraryDetailIntro.
  ///
  /// In zh, this message translates to:
  /// **'简介'**
  String get libraryDetailIntro;

  /// 统一详情加载失败；error 是 presentation 层清理后的安全摘要
  ///
  /// In zh, this message translates to:
  /// **'加载详情失败：{error}'**
  String libraryDetailLoadFailed(String error);

  /// No description provided for @libraryDetailInShelf.
  ///
  /// In zh, this message translates to:
  /// **'在书架中'**
  String get libraryDetailInShelf;

  /// No description provided for @libraryDetailAddToShelf.
  ///
  /// In zh, this message translates to:
  /// **'添加到书架'**
  String get libraryDetailAddToShelf;

  /// No description provided for @libraryDetailUpdate.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get libraryDetailUpdate;

  /// No description provided for @libraryDetailSourceThread.
  ///
  /// In zh, this message translates to:
  /// **'原帖'**
  String get libraryDetailSourceThread;

  /// No description provided for @libraryDetailNoNovelCover.
  ///
  /// In zh, this message translates to:
  /// **'小说无封面'**
  String get libraryDetailNoNovelCover;

  /// No description provided for @libraryDetailAuthor.
  ///
  /// In zh, this message translates to:
  /// **'作者'**
  String get libraryDetailAuthor;

  /// No description provided for @libraryDetailTranslator.
  ///
  /// In zh, this message translates to:
  /// **'翻译者'**
  String get libraryDetailTranslator;

  /// No description provided for @libraryDetailTranslationGroup.
  ///
  /// In zh, this message translates to:
  /// **'汉化组'**
  String get libraryDetailTranslationGroup;

  /// No description provided for @libraryDetailPublisher.
  ///
  /// In zh, this message translates to:
  /// **'发布者'**
  String get libraryDetailPublisher;

  /// 详情头部元数据语义；value 是原始作者或发布者名称
  ///
  /// In zh, this message translates to:
  /// **'{label}：{value}'**
  String libraryDetailMetadataSemantics(String label, String value);

  /// No description provided for @libraryDetailDownloadUnread.
  ///
  /// In zh, this message translates to:
  /// **'下载未读章节'**
  String get libraryDetailDownloadUnread;

  /// No description provided for @libraryDetailDownloadAll.
  ///
  /// In zh, this message translates to:
  /// **'下载全部章节'**
  String get libraryDetailDownloadAll;

  /// No description provided for @libraryDetailDeleteDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除下载失败：{error}'**
  String libraryDetailDeleteDownloadFailed(String error);

  /// No description provided for @libraryDetailDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败：{error}'**
  String libraryDetailDownloadFailed(String error);

  /// No description provided for @libraryDetailReadStateUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'阅读状态更新失败'**
  String get libraryDetailReadStateUpdateFailed;

  /// No description provided for @libraryDetailAllChapters.
  ///
  /// In zh, this message translates to:
  /// **'全部章节'**
  String get libraryDetailAllChapters;

  /// No description provided for @libraryDetailDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'已下载'**
  String get libraryDetailDownloaded;

  /// No description provided for @libraryDetailUnread.
  ///
  /// In zh, this message translates to:
  /// **'未读'**
  String get libraryDetailUnread;

  /// No description provided for @libraryDetailBookmarked.
  ///
  /// In zh, this message translates to:
  /// **'已加书签'**
  String get libraryDetailBookmarked;

  /// No description provided for @libraryDetailExcludeFilter.
  ///
  /// In zh, this message translates to:
  /// **'排除{label}'**
  String libraryDetailExcludeFilter(String label);

  /// No description provided for @libraryDetailFilter.
  ///
  /// In zh, this message translates to:
  /// **'筛选'**
  String get libraryDetailFilter;

  /// No description provided for @libraryDetailSort.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get libraryDetailSort;

  /// No description provided for @libraryDetailSortBySource.
  ///
  /// In zh, this message translates to:
  /// **'按来源'**
  String get libraryDetailSortBySource;

  /// No description provided for @libraryDetailAddBookmark.
  ///
  /// In zh, this message translates to:
  /// **'添加书签'**
  String get libraryDetailAddBookmark;

  /// No description provided for @libraryDetailRemoveBookmark.
  ///
  /// In zh, this message translates to:
  /// **'移除书签'**
  String get libraryDetailRemoveBookmark;

  /// No description provided for @libraryDetailResetWorkReading.
  ///
  /// In zh, this message translates to:
  /// **'重置本作品阅读'**
  String get libraryDetailResetWorkReading;

  /// No description provided for @libraryDetailDeleteChapterDownload.
  ///
  /// In zh, this message translates to:
  /// **'删除该章节下载'**
  String get libraryDetailDeleteChapterDownload;

  /// No description provided for @libraryDetailManageChaptersDescription.
  ///
  /// In zh, this message translates to:
  /// **'显示或隐藏章节，手动添加或移除章节'**
  String get libraryDetailManageChaptersDescription;

  /// No description provided for @libraryDetailResetReadingTitle.
  ///
  /// In zh, this message translates to:
  /// **'重置本作品阅读？'**
  String get libraryDetailResetReadingTitle;

  /// No description provided for @libraryDetailResetReadingBody.
  ///
  /// In zh, this message translates to:
  /// **'全部章节将变为未读，所有阅读进度和上次阅读位置都会被清除。书签和下载不会受影响。'**
  String get libraryDetailResetReadingBody;

  /// No description provided for @libraryDetailResetReadingConfirm.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get libraryDetailResetReadingConfirm;

  /// No description provided for @libraryDetailResetReadingFailed.
  ///
  /// In zh, this message translates to:
  /// **'重置作品阅读失败'**
  String get libraryDetailResetReadingFailed;

  /// No description provided for @libraryDetailRefreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新失败：{error}'**
  String libraryDetailRefreshFailed(String error);

  /// No description provided for @libraryDetailRefreshUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新'**
  String get libraryDetailRefreshUpdated;

  /// 详情刷新后的章节增删统计
  ///
  /// In zh, this message translates to:
  /// **'{insertedCount, plural, =0 {未新增章节} other {已新增 {insertedCount} 章}}，{updatedCount, plural, =0 {未更新章节} other {更新 {updatedCount} 章}}'**
  String libraryDetailRefreshChaptersChanged(
    int insertedCount,
    int updatedCount,
  );

  /// No description provided for @libraryDetailRefreshAlreadyCurrent.
  ///
  /// In zh, this message translates to:
  /// **'已是最新章节'**
  String get libraryDetailRefreshAlreadyCurrent;

  /// No description provided for @libraryDetailRefreshNoUpdates.
  ///
  /// In zh, this message translates to:
  /// **'未发现新的章节'**
  String get libraryDetailRefreshNoUpdates;

  /// No description provided for @libraryDetailRefreshQueued.
  ///
  /// In zh, this message translates to:
  /// **'已加入更新队列，预计 {duration}'**
  String libraryDetailRefreshQueued(String duration);

  /// No description provided for @libraryDetailRefreshQueuedAtPosition.
  ///
  /// In zh, this message translates to:
  /// **'已加入更新队列，前方 {position, plural, =0 {没有等待任务} other {有 {position} 个任务}}，预计 {duration}'**
  String libraryDetailRefreshQueuedAtPosition(int position, String duration);

  /// No description provided for @libraryDetailRefreshUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂无可更新内容'**
  String get libraryDetailRefreshUnavailable;

  /// No description provided for @libraryDetailCatalogLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取目录配置失败：{error}'**
  String libraryDetailCatalogLoadFailed(String error);

  /// No description provided for @libraryDetailMetadataTitle.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get libraryDetailMetadataTitle;

  /// No description provided for @libraryDetailMetadataSearchTitle.
  ///
  /// In zh, this message translates to:
  /// **'更新搜索关键词'**
  String get libraryDetailMetadataSearchTitle;

  /// No description provided for @libraryDetailMetadataSearchHelp.
  ///
  /// In zh, this message translates to:
  /// **'留空时优先使用自定义标题，否则使用当前作品标题'**
  String get libraryDetailMetadataSearchHelp;

  /// No description provided for @libraryDetailMetadataSourceTitle.
  ///
  /// In zh, this message translates to:
  /// **'来源标题'**
  String get libraryDetailMetadataSourceTitle;

  /// No description provided for @libraryDetailMetadataSourceAuthor.
  ///
  /// In zh, this message translates to:
  /// **'来源作者'**
  String get libraryDetailMetadataSourceAuthor;

  /// No description provided for @libraryDetailMetadataSourceTranslationGroup.
  ///
  /// In zh, this message translates to:
  /// **'来源汉化组'**
  String get libraryDetailMetadataSourceTranslationGroup;

  /// 只读来源字段；value 是原始服务器或用户内容
  ///
  /// In zh, this message translates to:
  /// **'{label}：{value}'**
  String libraryDetailSourceValue(String label, String value);

  /// No description provided for @libraryDetailSourceEmpty.
  ///
  /// In zh, this message translates to:
  /// **'{label}：无'**
  String libraryDetailSourceEmpty(String label);

  /// No description provided for @libraryDetailCatalogUrl.
  ///
  /// In zh, this message translates to:
  /// **'目录 URL'**
  String get libraryDetailCatalogUrl;

  /// 目录来源；url 是原始 URL，仅展示不改写
  ///
  /// In zh, this message translates to:
  /// **'来源目录：{url}'**
  String libraryDetailCatalogSource(String url);

  /// No description provided for @libraryDetailCatalogSourceEmpty.
  ///
  /// In zh, this message translates to:
  /// **'来源目录：无'**
  String get libraryDetailCatalogSourceEmpty;

  /// No description provided for @libraryDetailCatalogSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String libraryDetailCatalogSaveFailed(String error);

  /// No description provided for @libraryDetailCatalogInvalidUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的目录 URL'**
  String get libraryDetailCatalogInvalidUrl;

  /// No description provided for @libraryDetailCatalogIncompleteUrl.
  ///
  /// In zh, this message translates to:
  /// **'目录 URL 不完整'**
  String get libraryDetailCatalogIncompleteUrl;

  /// No description provided for @libraryDetailCatalogUnsupportedScheme.
  ///
  /// In zh, this message translates to:
  /// **'目录 URL 仅支持 HTTP 或 HTTPS'**
  String get libraryDetailCatalogUnsupportedScheme;

  /// 目录 URL host 校验；host 是协议要求的原始 host
  ///
  /// In zh, this message translates to:
  /// **'目录 URL 必须来自 {host}'**
  String libraryDetailCatalogUnexpectedHost(String host);

  /// No description provided for @libraryDetailCatalogNotTagCatalog.
  ///
  /// In zh, this message translates to:
  /// **'请输入标签目录页面的 URL'**
  String get libraryDetailCatalogNotTagCatalog;

  /// No description provided for @libraryDetailCoverUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'封面更新失败：{error}'**
  String libraryDetailCoverUpdateFailed(String error);

  /// No description provided for @libraryDetailCoverUpdated.
  ///
  /// In zh, this message translates to:
  /// **'封面已更新'**
  String get libraryDetailCoverUpdated;

  /// No description provided for @libraryDetailCoverRemoveFailed.
  ///
  /// In zh, this message translates to:
  /// **'取消封面失败：{error}'**
  String libraryDetailCoverRemoveFailed(String error);

  /// No description provided for @libraryDetailCoverRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已取消封面'**
  String get libraryDetailCoverRemoved;

  /// No description provided for @libraryChapterCount.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {共 0 章} other {共 {count} 章}}'**
  String libraryChapterCount(int count);

  /// 来源章节标题为空时的显示兜底；tid 是原始帖子 ID
  ///
  /// In zh, this message translates to:
  /// **'章节 {tid}'**
  String libraryChapterFallbackTitle(String tid);

  /// No description provided for @libraryChapterBookmarkSemantics.
  ///
  /// In zh, this message translates to:
  /// **'已添加书签'**
  String get libraryChapterBookmarkSemantics;

  /// No description provided for @libraryChapterDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载'**
  String get libraryChapterDownloading;

  /// No description provided for @libraryChapterDownloadedDelete.
  ///
  /// In zh, this message translates to:
  /// **'已下载，点击删除下载'**
  String get libraryChapterDownloadedDelete;

  /// No description provided for @libraryChapterDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载该章节'**
  String get libraryChapterDownload;

  /// No description provided for @libraryChapterClearReadState.
  ///
  /// In zh, this message translates to:
  /// **'清除阅读状态'**
  String get libraryChapterClearReadState;

  /// No description provided for @libraryChapterMarkRead.
  ///
  /// In zh, this message translates to:
  /// **'标记已读'**
  String get libraryChapterMarkRead;

  /// No description provided for @libraryChapterCurrentPage.
  ///
  /// In zh, this message translates to:
  /// **'第 {page} 页'**
  String libraryChapterCurrentPage(int page);

  /// No description provided for @libraryChapterCurrentPageOfTotal.
  ///
  /// In zh, this message translates to:
  /// **'第 {page} 页，共 {total} 页'**
  String libraryChapterCurrentPageOfTotal(int page, int total);

  /// No description provided for @libraryChapterLastRead.
  ///
  /// In zh, this message translates to:
  /// **'上次阅读'**
  String get libraryChapterLastRead;

  /// 章节进度语义；subtitle 和 progress 都由共享 presentation 生成，章节数据保持原样
  ///
  /// In zh, this message translates to:
  /// **'{subtitle}，{progress}'**
  String libraryChapterProgressSemantics(String subtitle, String progress);

  /// No description provided for @libraryChapterFilterAny.
  ///
  /// In zh, this message translates to:
  /// **'不限'**
  String get libraryChapterFilterAny;

  /// No description provided for @libraryChapterFilterOnly.
  ///
  /// In zh, this message translates to:
  /// **'只看{label}'**
  String libraryChapterFilterOnly(String label);

  /// No description provided for @libraryChapterFilterExclude.
  ///
  /// In zh, this message translates to:
  /// **'排除{label}'**
  String libraryChapterFilterExclude(String label);

  /// No description provided for @libraryChapterManagementLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取章节'**
  String get libraryChapterManagementLoading;

  /// No description provided for @libraryChapterManagementSummary.
  ///
  /// In zh, this message translates to:
  /// **'{total, plural, =0 {共 0 章} other {共 {total} 章}} · {parsed, plural, =0 {解析 0 章} other {解析 {parsed} 章}} · {manual, plural, =0 {手动 0 章} other {手动 {manual} 章}} · {hidden, plural, =0 {隐藏 0 章} other {隐藏 {hidden} 章}}'**
  String libraryChapterManagementSummary(
    int total,
    int parsed,
    int manual,
    int hidden,
  );

  /// No description provided for @libraryChapterFilterLabel.
  ///
  /// In zh, this message translates to:
  /// **'筛选章节'**
  String get libraryChapterFilterLabel;

  /// No description provided for @libraryChapterFilterHint.
  ///
  /// In zh, this message translates to:
  /// **'按标题或 TID 搜索'**
  String get libraryChapterFilterHint;

  /// No description provided for @libraryChapterClearFilter.
  ///
  /// In zh, this message translates to:
  /// **'清除筛选'**
  String get libraryChapterClearFilter;

  /// No description provided for @libraryChapterAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加章节'**
  String get libraryChapterAdd;

  /// No description provided for @libraryChapterAddHint.
  ///
  /// In zh, this message translates to:
  /// **'粘贴帖子链接或直接输入 TID'**
  String get libraryChapterAddHint;

  /// No description provided for @libraryChapterAddHelp.
  ///
  /// In zh, this message translates to:
  /// **'支持 forum.php、thread-xxx.html、api/mobile 等链接形式'**
  String get libraryChapterAddHelp;

  /// No description provided for @libraryChapterShowAll.
  ///
  /// In zh, this message translates to:
  /// **'全部显示'**
  String get libraryChapterShowAll;

  /// No description provided for @libraryChapterHideAll.
  ///
  /// In zh, this message translates to:
  /// **'全部隐藏'**
  String get libraryChapterHideAll;

  /// No description provided for @libraryChapterManagementEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无章节，可在上方粘贴帖子链接手动添加'**
  String get libraryChapterManagementEmpty;

  /// No description provided for @libraryChapterManagementNoMatches.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的章节'**
  String get libraryChapterManagementNoMatches;

  /// No description provided for @libraryChapterShow.
  ///
  /// In zh, this message translates to:
  /// **'显示该章节'**
  String get libraryChapterShow;

  /// No description provided for @libraryChapterHide.
  ///
  /// In zh, this message translates to:
  /// **'隐藏该章节'**
  String get libraryChapterHide;

  /// No description provided for @libraryChapterHidden.
  ///
  /// In zh, this message translates to:
  /// **'已隐藏'**
  String get libraryChapterHidden;

  /// No description provided for @libraryChapterRename.
  ///
  /// In zh, this message translates to:
  /// **'重命名该章节'**
  String get libraryChapterRename;

  /// No description provided for @libraryChapterRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除该章节'**
  String get libraryChapterRemove;

  /// No description provided for @libraryChapterAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加章节'**
  String get libraryChapterAdded;

  /// No description provided for @libraryChapterDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'该章节已存在'**
  String get libraryChapterDuplicate;

  /// No description provided for @libraryChapterAddFailed.
  ///
  /// In zh, this message translates to:
  /// **'添加失败：{error}'**
  String libraryChapterAddFailed(String error);

  /// No description provided for @libraryChapterInputEmpty.
  ///
  /// In zh, this message translates to:
  /// **'请输入帖子链接或 TID'**
  String get libraryChapterInputEmpty;

  /// No description provided for @libraryChapterInputInvalidUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的帖子链接或 TID'**
  String get libraryChapterInputInvalidUrl;

  /// No description provided for @libraryChapterInputUnsupportedScheme.
  ///
  /// In zh, this message translates to:
  /// **'帖子链接仅支持 HTTP 或 HTTPS'**
  String get libraryChapterInputUnsupportedScheme;

  /// 手动章节 host 校验；host 是协议要求的原始 host
  ///
  /// In zh, this message translates to:
  /// **'帖子链接必须来自 {host}'**
  String libraryChapterInputUnexpectedHost(String host);

  /// No description provided for @libraryChapterInputUnsupportedThreadUrl.
  ///
  /// In zh, this message translates to:
  /// **'不支持此帖子链接形式'**
  String get libraryChapterInputUnsupportedThreadUrl;

  /// No description provided for @libraryChapterInputMissingTid.
  ///
  /// In zh, this message translates to:
  /// **'帖子链接中缺少有效的 TID'**
  String get libraryChapterInputMissingTid;

  /// No description provided for @libraryChapterVisibilityUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新显示状态失败：{error}'**
  String libraryChapterVisibilityUpdateFailed(String error);

  /// No description provided for @libraryChapterRestoredSourceTitle.
  ///
  /// In zh, this message translates to:
  /// **'已恢复来源章节名'**
  String get libraryChapterRestoredSourceTitle;

  /// No description provided for @libraryChapterRenamed.
  ///
  /// In zh, this message translates to:
  /// **'已重命名章节'**
  String get libraryChapterRenamed;

  /// No description provided for @libraryChapterRenameFailed.
  ///
  /// In zh, this message translates to:
  /// **'重命名失败：{error}'**
  String libraryChapterRenameFailed(String error);

  /// No description provided for @libraryChapterAllHidden.
  ///
  /// In zh, this message translates to:
  /// **'已隐藏全部章节'**
  String get libraryChapterAllHidden;

  /// No description provided for @libraryChapterAllShown.
  ///
  /// In zh, this message translates to:
  /// **'已显示全部章节'**
  String get libraryChapterAllShown;

  /// No description provided for @libraryChapterBulkUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'批量更新失败：{error}'**
  String libraryChapterBulkUpdateFailed(String error);

  /// No description provided for @libraryChapterRemoveTitle.
  ///
  /// In zh, this message translates to:
  /// **'移除该章节？'**
  String get libraryChapterRemoveTitle;

  /// 移除手动章节确认；title 是原始或用户自定义章节名
  ///
  /// In zh, this message translates to:
  /// **'将删除手动添加的“{title}”及其阅读记录与下载任务，此操作不可撤销。'**
  String libraryChapterRemoveBody(String title);

  /// No description provided for @libraryChapterParsedCannotRemove.
  ///
  /// In zh, this message translates to:
  /// **'解析章节不可移除，可改为隐藏'**
  String get libraryChapterParsedCannotRemove;

  /// No description provided for @libraryChapterRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除章节'**
  String get libraryChapterRemoved;

  /// No description provided for @libraryChapterRemovedWithWarnings.
  ///
  /// In zh, this message translates to:
  /// **'章节已移除，但{warnings}'**
  String libraryChapterRemovedWithWarnings(String warnings);

  /// No description provided for @libraryChapterDownloadTaskCleanupFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载任务清理失败'**
  String get libraryChapterDownloadTaskCleanupFailed;

  /// No description provided for @libraryChapterDownloadFileCleanupFailed.
  ///
  /// In zh, this message translates to:
  /// **'章节下载文件清理失败'**
  String get libraryChapterDownloadFileCleanupFailed;

  /// No description provided for @libraryChapterRemoveFailed.
  ///
  /// In zh, this message translates to:
  /// **'移除失败：{error}'**
  String libraryChapterRemoveFailed(String error);

  /// No description provided for @libraryChapterRenameTitle.
  ///
  /// In zh, this message translates to:
  /// **'重命名章节'**
  String get libraryChapterRenameTitle;

  /// No description provided for @libraryChapterName.
  ///
  /// In zh, this message translates to:
  /// **'章节名'**
  String get libraryChapterName;

  /// No description provided for @libraryChapterRestoreDefaultTitleHelp.
  ///
  /// In zh, this message translates to:
  /// **'留空恢复默认章节名'**
  String get libraryChapterRestoreDefaultTitleHelp;

  /// 章节重命名说明；title 是原始来源章节名
  ///
  /// In zh, this message translates to:
  /// **'留空恢复来源章节名：{title}'**
  String libraryChapterRestoreSourceTitleHelp(String title);

  /// No description provided for @libraryChapterManual.
  ///
  /// In zh, this message translates to:
  /// **'手动'**
  String get libraryChapterManual;

  /// No description provided for @libraryChapterParsed.
  ///
  /// In zh, this message translates to:
  /// **'解析'**
  String get libraryChapterParsed;

  /// No description provided for @libraryChapterLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取章节失败：{error}'**
  String libraryChapterLoadFailed(String error);

  /// No description provided for @libraryCoverFocalTitle.
  ///
  /// In zh, this message translates to:
  /// **'调整封面焦点'**
  String get libraryCoverFocalTitle;

  /// No description provided for @libraryCoverFocalHelp.
  ///
  /// In zh, this message translates to:
  /// **'拖动选框选择封面取景区域，原图不会被裁剪'**
  String get libraryCoverFocalHelp;

  /// No description provided for @libraryCoverImageLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'图片加载失败'**
  String get libraryCoverImageLoadFailed;

  /// No description provided for @libraryCoverCenter.
  ///
  /// In zh, this message translates to:
  /// **'居中'**
  String get libraryCoverCenter;

  /// No description provided for @libraryErrorRedactedLink.
  ///
  /// In zh, this message translates to:
  /// **'[链接已隐藏]'**
  String get libraryErrorRedactedLink;

  /// No description provided for @libraryErrorRedactedSecret.
  ///
  /// In zh, this message translates to:
  /// **'[敏感信息已隐藏]'**
  String get libraryErrorRedactedSecret;

  /// No description provided for @readerBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get readerBack;

  /// No description provided for @readerPrevious.
  ///
  /// In zh, this message translates to:
  /// **'上一章'**
  String get readerPrevious;

  /// No description provided for @readerNext.
  ///
  /// In zh, this message translates to:
  /// **'下一章'**
  String get readerNext;

  /// 共享阅读器分段按钮选中语义；label 已由调用方本地化
  ///
  /// In zh, this message translates to:
  /// **'{label}，已选择'**
  String readerSelectedSemantics(String label);

  /// 共享阅读器进度滑块语义；current 和 total 是调用方提供的显示值
  ///
  /// In zh, this message translates to:
  /// **'阅读进度：{current} / {total}'**
  String readerProgressSemantics(String current, String total);

  /// No description provided for @readerModeVertical.
  ///
  /// In zh, this message translates to:
  /// **'垂直'**
  String get readerModeVertical;

  /// No description provided for @readerModeLtr.
  ///
  /// In zh, this message translates to:
  /// **'左到右'**
  String get readerModeLtr;

  /// No description provided for @readerModeRtl.
  ///
  /// In zh, this message translates to:
  /// **'右到左'**
  String get readerModeRtl;

  /// No description provided for @readerModeVerticalContinuous.
  ///
  /// In zh, this message translates to:
  /// **'垂直连续'**
  String get readerModeVerticalContinuous;

  /// No description provided for @readerModeSingleLtr.
  ///
  /// In zh, this message translates to:
  /// **'单页 左到右'**
  String get readerModeSingleLtr;

  /// No description provided for @readerModeSingleRtl.
  ///
  /// In zh, this message translates to:
  /// **'单页 右到左'**
  String get readerModeSingleRtl;

  /// No description provided for @readerDisplaySettings.
  ///
  /// In zh, this message translates to:
  /// **'显示设置'**
  String get readerDisplaySettings;

  /// No description provided for @readerReadingMode.
  ///
  /// In zh, this message translates to:
  /// **'阅读模式'**
  String get readerReadingMode;

  /// No description provided for @readerPageFit.
  ///
  /// In zh, this message translates to:
  /// **'页面适配'**
  String get readerPageFit;

  /// No description provided for @readerPageFitWidth.
  ///
  /// In zh, this message translates to:
  /// **'宽度'**
  String get readerPageFitWidth;

  /// No description provided for @readerPageFitHeight.
  ///
  /// In zh, this message translates to:
  /// **'高度'**
  String get readerPageFitHeight;

  /// No description provided for @readerPageFitContain.
  ///
  /// In zh, this message translates to:
  /// **'屏幕'**
  String get readerPageFitContain;

  /// No description provided for @readerBackground.
  ///
  /// In zh, this message translates to:
  /// **'背景色'**
  String get readerBackground;

  /// No description provided for @readerBackgroundTheme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get readerBackgroundTheme;

  /// No description provided for @readerBackgroundBlack.
  ///
  /// In zh, this message translates to:
  /// **'黑'**
  String get readerBackgroundBlack;

  /// No description provided for @readerBackgroundWhite.
  ///
  /// In zh, this message translates to:
  /// **'白'**
  String get readerBackgroundWhite;

  /// No description provided for @readerBackgroundGray.
  ///
  /// In zh, this message translates to:
  /// **'灰'**
  String get readerBackgroundGray;

  /// No description provided for @readerPageSpacing.
  ///
  /// In zh, this message translates to:
  /// **'页间距'**
  String get readerPageSpacing;

  /// No description provided for @readerPageIndicator.
  ///
  /// In zh, this message translates to:
  /// **'页码浮层'**
  String get readerPageIndicator;

  /// No description provided for @readerNoImages.
  ///
  /// In zh, this message translates to:
  /// **'没有可阅读图片'**
  String get readerNoImages;

  /// No description provided for @readerImageLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'图片加载失败'**
  String get readerImageLoadFailed;

  /// No description provided for @readerTailContent.
  ///
  /// In zh, this message translates to:
  /// **'末尾内容'**
  String get readerTailContent;

  /// No description provided for @readerContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get readerContinue;

  /// No description provided for @readerDownloadUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前图片不支持下载'**
  String get readerDownloadUnsupported;

  /// No description provided for @readerExportSaving.
  ///
  /// In zh, this message translates to:
  /// **'正在保存当前图片'**
  String get readerExportSaving;

  /// No description provided for @readerExportSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存到{destination}'**
  String readerExportSaved(String destination);

  /// No description provided for @readerExportDefaultDestination.
  ///
  /// In zh, this message translates to:
  /// **'系统照片'**
  String get readerExportDefaultDestination;

  /// No description provided for @readerExportCacheUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'图片暂不可用，请重试'**
  String get readerExportCacheUnavailable;

  /// No description provided for @readerExportPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'没有照片库写入权限，请在系统设置中允许'**
  String get readerExportPermissionDenied;

  /// No description provided for @readerExportPermissionRestricted.
  ///
  /// In zh, this message translates to:
  /// **'照片库权限受系统限制'**
  String get readerExportPermissionRestricted;

  /// No description provided for @readerExportUnsupportedPlatform.
  ///
  /// In zh, this message translates to:
  /// **'当前平台不支持保存图片'**
  String get readerExportUnsupportedPlatform;

  /// No description provided for @readerExportUnsupportedFormat.
  ///
  /// In zh, this message translates to:
  /// **'当前图片格式不支持保存'**
  String get readerExportUnsupportedFormat;

  /// No description provided for @readerExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存图片失败，请重试'**
  String get readerExportFailed;

  /// No description provided for @comicUntitledWork.
  ///
  /// In zh, this message translates to:
  /// **'未命名漫画（{workId}）'**
  String comicUntitledWork(String workId);

  /// No description provided for @comicChapterFallbackTitle.
  ///
  /// In zh, this message translates to:
  /// **'章节 {sourceTid}'**
  String comicChapterFallbackTitle(String sourceTid);

  /// No description provided for @comicAddToShelf.
  ///
  /// In zh, this message translates to:
  /// **'加入书架'**
  String get comicAddToShelf;

  /// No description provided for @comicAlreadyInShelf.
  ///
  /// In zh, this message translates to:
  /// **'已在书架'**
  String get comicAlreadyInShelf;

  /// No description provided for @comicNoImages.
  ///
  /// In zh, this message translates to:
  /// **'当前章节没有可阅读图片'**
  String get comicNoImages;

  /// No description provided for @comicReaderLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载阅读器失败：{error}'**
  String comicReaderLoadFailed(String error);

  /// No description provided for @comicReaderNetworkFailure.
  ///
  /// In zh, this message translates to:
  /// **'网络异常，请检查后重试'**
  String get comicReaderNetworkFailure;

  /// No description provided for @comicReaderAuthFailure.
  ///
  /// In zh, this message translates to:
  /// **'登录态已失效，请重新登录后重试'**
  String get comicReaderAuthFailure;

  /// No description provided for @comicReaderServerFailure.
  ///
  /// In zh, this message translates to:
  /// **'服务暂时不可用，请稍后重试'**
  String get comicReaderServerFailure;

  /// No description provided for @comicReaderParseFailure.
  ///
  /// In zh, this message translates to:
  /// **'页面结构异常，无法解析章节内容'**
  String get comicReaderParseFailure;

  /// No description provided for @comicReaderUnknownFailure.
  ///
  /// In zh, this message translates to:
  /// **'加载章节失败'**
  String get comicReaderUnknownFailure;

  /// No description provided for @comicReaderEpisodeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'章节不存在或已被移除'**
  String get comicReaderEpisodeUnavailable;

  /// No description provided for @comicBookmarkAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加书签'**
  String get comicBookmarkAdd;

  /// No description provided for @comicBookmarkRemove.
  ///
  /// In zh, this message translates to:
  /// **'取消书签'**
  String get comicBookmarkRemove;

  /// No description provided for @comicBookmarkAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加书签'**
  String get comicBookmarkAdded;

  /// No description provided for @comicBookmarkRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除书签'**
  String get comicBookmarkRemoved;

  /// No description provided for @comicOpenSourceThread.
  ///
  /// In zh, this message translates to:
  /// **'打开原帖'**
  String get comicOpenSourceThread;

  /// No description provided for @comicMoreActions.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get comicMoreActions;

  /// No description provided for @comicMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get comicMore;

  /// No description provided for @comicChapterList.
  ///
  /// In zh, this message translates to:
  /// **'章节列表'**
  String get comicChapterList;

  /// No description provided for @comicChapterAction.
  ///
  /// In zh, this message translates to:
  /// **'章节'**
  String get comicChapterAction;

  /// No description provided for @comicCurrentChapter.
  ///
  /// In zh, this message translates to:
  /// **'当前'**
  String get comicCurrentChapter;

  /// No description provided for @comicDisplay.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get comicDisplay;

  /// No description provided for @comicDownloadCurrentImage.
  ///
  /// In zh, this message translates to:
  /// **'下载当前图片'**
  String get comicDownloadCurrentImage;

  /// No description provided for @comicPreviousEpisode.
  ///
  /// In zh, this message translates to:
  /// **'上一话'**
  String get comicPreviousEpisode;

  /// No description provided for @comicNextEpisode.
  ///
  /// In zh, this message translates to:
  /// **'下一话'**
  String get comicNextEpisode;

  /// No description provided for @comicFirstEpisode.
  ///
  /// In zh, this message translates to:
  /// **'已是第一话'**
  String get comicFirstEpisode;

  /// No description provided for @comicLastEpisode.
  ///
  /// In zh, this message translates to:
  /// **'已是最后一话'**
  String get comicLastEpisode;

  /// No description provided for @comicMarkEpisodeRead.
  ///
  /// In zh, this message translates to:
  /// **'标记本章已读'**
  String get comicMarkEpisodeRead;

  /// No description provided for @comicMarkEpisodeUnread.
  ///
  /// In zh, this message translates to:
  /// **'标记本章未读'**
  String get comicMarkEpisodeUnread;

  /// No description provided for @comicEpisodeMarkedRead.
  ///
  /// In zh, this message translates to:
  /// **'已标记本章已读'**
  String get comicEpisodeMarkedRead;

  /// No description provided for @comicEpisodeMarkedUnread.
  ///
  /// In zh, this message translates to:
  /// **'已标记本章未读'**
  String get comicEpisodeMarkedUnread;

  /// No description provided for @comicSetCurrentPageCover.
  ///
  /// In zh, this message translates to:
  /// **'将当前页设为封面'**
  String get comicSetCurrentPageCover;

  /// No description provided for @comicCoverImageUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前页图片暂不可用，无法设为封面'**
  String get comicCoverImageUnavailable;

  /// No description provided for @comicCoverUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'封面更新失败'**
  String get comicCoverUpdateFailed;

  /// No description provided for @comicCoverUpdated.
  ///
  /// In zh, this message translates to:
  /// **'封面已更新'**
  String get comicCoverUpdated;

  /// No description provided for @comicEpisodeSwitchFailed.
  ///
  /// In zh, this message translates to:
  /// **'章节切换失败，已保留当前章节'**
  String get comicEpisodeSwitchFailed;

  /// No description provided for @comicSetCoverFocus.
  ///
  /// In zh, this message translates to:
  /// **'调整封面焦点'**
  String get comicSetCoverFocus;

  /// No description provided for @comicNextChapterTitle.
  ///
  /// In zh, this message translates to:
  /// **'下一章：{title}'**
  String comicNextChapterTitle(String title);

  /// No description provided for @comicSwitchingEpisode.
  ///
  /// In zh, this message translates to:
  /// **'正在切换章节'**
  String get comicSwitchingEpisode;

  /// No description provided for @comicOpenNextEpisode.
  ///
  /// In zh, this message translates to:
  /// **'点击进入下一章'**
  String get comicOpenNextEpisode;

  /// No description provided for @comicOpeningEpisode.
  ///
  /// In zh, this message translates to:
  /// **'正在打开章节'**
  String get comicOpeningEpisode;

  /// No description provided for @comicRefreshNoNewLinks.
  ///
  /// In zh, this message translates to:
  /// **'未提取到新的章节链接'**
  String get comicRefreshNoNewLinks;

  /// No description provided for @comicRefreshCompleted.
  ///
  /// In zh, this message translates to:
  /// **'章节刷新完成：新增 {insertedCount, plural, =0 {0} other {{insertedCount}}}，更新 {updatedCount, plural, =0 {0} other {{updatedCount}}}'**
  String comicRefreshCompleted(int insertedCount, int updatedCount);

  /// No description provided for @comicRefreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'刷新章节失败：{error}'**
  String comicRefreshFailed(String error);

  /// No description provided for @comicComment.
  ///
  /// In zh, this message translates to:
  /// **'评论'**
  String get comicComment;

  /// No description provided for @comicCommentLoading.
  ///
  /// In zh, this message translates to:
  /// **'评论加载中'**
  String get comicCommentLoading;

  /// No description provided for @comicCommentEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无评论'**
  String get comicCommentEmpty;

  /// No description provided for @comicCommentUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'评论暂不可用'**
  String get comicCommentUnavailable;

  /// No description provided for @comicCommentOpen.
  ///
  /// In zh, this message translates to:
  /// **'查看评论'**
  String get comicCommentOpen;

  /// No description provided for @comicCommentUnavailableFeedback.
  ///
  /// In zh, this message translates to:
  /// **'无法查看评论'**
  String get comicCommentUnavailableFeedback;

  /// No description provided for @comicCommentContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续滑动进入下一章'**
  String get comicCommentContinue;

  /// No description provided for @comicCommentContinueTo.
  ///
  /// In zh, this message translates to:
  /// **'继续滑动进入：{title}'**
  String comicCommentContinueTo(String title);

  /// No description provided for @comicDownloadQueue.
  ///
  /// In zh, this message translates to:
  /// **'下载队列'**
  String get comicDownloadQueue;

  /// No description provided for @comicDownloadQueueEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无下载任务'**
  String get comicDownloadQueueEmpty;

  /// No description provided for @comicDownloadActive.
  ///
  /// In zh, this message translates to:
  /// **'正在下载'**
  String get comicDownloadActive;

  /// No description provided for @comicDownloadPending.
  ///
  /// In zh, this message translates to:
  /// **'等待中'**
  String get comicDownloadPending;

  /// No description provided for @comicDownloadFailedSection.
  ///
  /// In zh, this message translates to:
  /// **'下载失败'**
  String get comicDownloadFailedSection;

  /// No description provided for @comicDownloadCanceling.
  ///
  /// In zh, this message translates to:
  /// **'正在取消'**
  String get comicDownloadCanceling;

  /// No description provided for @comicDownloadCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消下载'**
  String get comicDownloadCancel;

  /// No description provided for @comicDownloadRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除任务'**
  String get comicDownloadRemove;

  /// No description provided for @comicDownloadRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get comicDownloadRetry;

  /// No description provided for @comicDownloadQueuePosition.
  ///
  /// In zh, this message translates to:
  /// **'{episodeTitle} · 第 {position} 位'**
  String comicDownloadQueuePosition(String episodeTitle, int position);

  /// No description provided for @comicDownloadFailureDetail.
  ///
  /// In zh, this message translates to:
  /// **'{episodeTitle} · {error}'**
  String comicDownloadFailureDetail(String episodeTitle, String error);

  /// No description provided for @comicDownloadResolvingImages.
  ///
  /// In zh, this message translates to:
  /// **'正在解析图片'**
  String get comicDownloadResolvingImages;

  /// No description provided for @comicDownloadProgress.
  ///
  /// In zh, this message translates to:
  /// **'{completed}/{total}'**
  String comicDownloadProgress(int completed, int total);

  /// No description provided for @comicDownloadCancelFailed.
  ///
  /// In zh, this message translates to:
  /// **'取消下载失败：{error}'**
  String comicDownloadCancelFailed(String error);

  /// No description provided for @comicDownloadRemoveFailed.
  ///
  /// In zh, this message translates to:
  /// **'移除任务失败：{error}'**
  String comicDownloadRemoveFailed(String error);

  /// No description provided for @comicDownloadRetryFailed.
  ///
  /// In zh, this message translates to:
  /// **'重试失败：{error}'**
  String comicDownloadRetryFailed(String error);

  /// No description provided for @comicDownloadWorkUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'漫画作品不存在或已被移除'**
  String get comicDownloadWorkUnavailable;

  /// No description provided for @comicDownloadEpisodeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'漫画章节不存在或已被移除'**
  String get comicDownloadEpisodeUnavailable;

  /// No description provided for @comicDownloadNoImages.
  ///
  /// In zh, this message translates to:
  /// **'章节没有可下载图片'**
  String get comicDownloadNoImages;

  /// No description provided for @comicDownloadImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'部分图片下载失败'**
  String get comicDownloadImageFailed;

  /// No description provided for @comicDownloadStorageFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载文件保存失败'**
  String get comicDownloadStorageFailed;

  /// No description provided for @comicDownloadUnknownFailure.
  ///
  /// In zh, this message translates to:
  /// **'下载失败，请重试'**
  String get comicDownloadUnknownFailure;

  /// No description provided for @novelUntitledWork.
  ///
  /// In zh, this message translates to:
  /// **'未命名小说（{novelId}）'**
  String novelUntitledWork(String novelId);

  /// No description provided for @novelChapterFallbackTitle.
  ///
  /// In zh, this message translates to:
  /// **'章节 {sourceTid}'**
  String novelChapterFallbackTitle(String sourceTid);

  /// No description provided for @novelOriginalBadge.
  ///
  /// In zh, this message translates to:
  /// **'原创'**
  String get novelOriginalBadge;

  /// No description provided for @novelOpenInReader.
  ///
  /// In zh, this message translates to:
  /// **'阅读器'**
  String get novelOpenInReader;

  /// No description provided for @novelOpenSourcePost.
  ///
  /// In zh, this message translates to:
  /// **'原帖'**
  String get novelOpenSourcePost;

  /// No description provided for @novelSaveOpenModeFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存章节打开方式失败：{error}'**
  String novelSaveOpenModeFailed(String error);

  /// No description provided for @novelSourceRouteDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'无法定位原帖楼层'**
  String get novelSourceRouteDialogTitle;

  /// No description provided for @novelOpenThreadHome.
  ///
  /// In zh, this message translates to:
  /// **'打开帖子首页'**
  String get novelOpenThreadHome;

  /// No description provided for @novelSourceRouteInvalidTid.
  ///
  /// In zh, this message translates to:
  /// **'章节缺少有效的来源 TID'**
  String get novelSourceRouteInvalidTid;

  /// No description provided for @novelSourceRouteInvalidPid.
  ///
  /// In zh, this message translates to:
  /// **'章节缺少有效的来源 PID'**
  String get novelSourceRouteInvalidPid;

  /// No description provided for @novelSourceRouteLocatorFailed.
  ///
  /// In zh, this message translates to:
  /// **'原帖楼层定位失败：{error}'**
  String novelSourceRouteLocatorFailed(String error);

  /// No description provided for @novelSourceRouteEmptyResult.
  ///
  /// In zh, this message translates to:
  /// **'原帖楼层定位结果为空'**
  String get novelSourceRouteEmptyResult;

  /// No description provided for @novelSourceRouteMismatchedResult.
  ///
  /// In zh, this message translates to:
  /// **'原帖楼层定位结果与章节来源不一致'**
  String get novelSourceRouteMismatchedResult;

  /// No description provided for @novelSourceRouteInvalidPage.
  ///
  /// In zh, this message translates to:
  /// **'原帖楼层页码无效'**
  String get novelSourceRouteInvalidPage;

  /// No description provided for @novelHydrationRecoveringMetadata.
  ///
  /// In zh, this message translates to:
  /// **'正在恢复小说来源信息'**
  String get novelHydrationRecoveringMetadata;

  /// No description provided for @novelHydrationPreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在准备章节'**
  String get novelHydrationPreparing;

  /// No description provided for @novelHydrationCommitting.
  ///
  /// In zh, this message translates to:
  /// **'正在保存 {count, plural, =0 {0 个章节} other {{count} 个章节}}'**
  String novelHydrationCommitting(int count);

  /// No description provided for @novelHydrationLoadingPage.
  ///
  /// In zh, this message translates to:
  /// **'正在加载第 {currentPage} 页 · 已发现 {acceptedCount, plural, =0 {0 章} other {{acceptedCount} 章}}'**
  String novelHydrationLoadingPage(int currentPage, int acceptedCount);

  /// No description provided for @novelHydrationLoadingPageOfTotal.
  ///
  /// In zh, this message translates to:
  /// **'正在加载第 {currentPage}/{totalPages} 页 · 已发现 {acceptedCount, plural, =0 {0 章} other {{acceptedCount} 章}}'**
  String novelHydrationLoadingPageOfTotal(
    int currentPage,
    int totalPages,
    int acceptedCount,
  );

  /// No description provided for @novelHydrationMissingSource.
  ///
  /// In zh, this message translates to:
  /// **'缺少小说来源信息，无法加载章节'**
  String get novelHydrationMissingSource;

  /// No description provided for @novelHydrationMissingPublisher.
  ///
  /// In zh, this message translates to:
  /// **'来源帖子缺少有效的发布者 ID'**
  String get novelHydrationMissingPublisher;

  /// No description provided for @novelHydrationMissingTid.
  ///
  /// In zh, this message translates to:
  /// **'小说缺少来源帖子 ID'**
  String get novelHydrationMissingTid;

  /// No description provided for @novelHydrationMissingCheckpoint.
  ///
  /// In zh, this message translates to:
  /// **'章节同步检查点缺失，无法安全更新'**
  String get novelHydrationMissingCheckpoint;

  /// No description provided for @novelHydrationInterrupted.
  ///
  /// In zh, this message translates to:
  /// **'章节同步已中断，请重试'**
  String get novelHydrationInterrupted;

  /// No description provided for @novelChapterLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'章节加载失败：{error}'**
  String novelChapterLoadFailed(String error);

  /// No description provided for @novelChapterLoadUnknown.
  ///
  /// In zh, this message translates to:
  /// **'章节加载失败，请重试'**
  String get novelChapterLoadUnknown;

  /// No description provided for @novelReaderNoChapters.
  ///
  /// In zh, this message translates to:
  /// **'小说没有可阅读章节'**
  String get novelReaderNoChapters;

  /// No description provided for @novelReaderContentMissing.
  ///
  /// In zh, this message translates to:
  /// **'章节正文暂不可用'**
  String get novelReaderContentMissing;

  /// No description provided for @novelReaderLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载阅读器失败：{error}'**
  String novelReaderLoadFailed(String error);

  /// No description provided for @novelDisplaySettings.
  ///
  /// In zh, this message translates to:
  /// **'显示设置'**
  String get novelDisplaySettings;

  /// No description provided for @novelTypography.
  ///
  /// In zh, this message translates to:
  /// **'排版'**
  String get novelTypography;

  /// No description provided for @novelFontSize.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get novelFontSize;

  /// No description provided for @novelLineSpacing.
  ///
  /// In zh, this message translates to:
  /// **'间隔'**
  String get novelLineSpacing;

  /// No description provided for @novelTheme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get novelTheme;

  /// No description provided for @novelThemeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get novelThemeLight;

  /// No description provided for @novelThemeSepia.
  ///
  /// In zh, this message translates to:
  /// **'护眼'**
  String get novelThemeSepia;

  /// No description provided for @novelThemeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get novelThemeDark;

  /// No description provided for @novelThemeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get novelThemeSystem;

  /// No description provided for @novelReading.
  ///
  /// In zh, this message translates to:
  /// **'阅读'**
  String get novelReading;

  /// No description provided for @novelReadingMode.
  ///
  /// In zh, this message translates to:
  /// **'阅读模式'**
  String get novelReadingMode;

  /// No description provided for @novelConversionMode.
  ///
  /// In zh, this message translates to:
  /// **'简繁'**
  String get novelConversionMode;

  /// No description provided for @novelSafeContent.
  ///
  /// In zh, this message translates to:
  /// **'安全显示正文'**
  String get novelSafeContent;

  /// No description provided for @novelConversionOriginal.
  ///
  /// In zh, this message translates to:
  /// **'原文'**
  String get novelConversionOriginal;

  /// No description provided for @novelConversionSimplified.
  ///
  /// In zh, this message translates to:
  /// **'简体'**
  String get novelConversionSimplified;

  /// No description provided for @novelConversionTraditional.
  ///
  /// In zh, this message translates to:
  /// **'繁体'**
  String get novelConversionTraditional;

  /// No description provided for @novelFlowScroll.
  ///
  /// In zh, this message translates to:
  /// **'滚动'**
  String get novelFlowScroll;

  /// No description provided for @novelFlowPagedLtr.
  ///
  /// In zh, this message translates to:
  /// **'分页 LTR'**
  String get novelFlowPagedLtr;

  /// No description provided for @novelFlowPagedRtl.
  ///
  /// In zh, this message translates to:
  /// **'分页 RTL'**
  String get novelFlowPagedRtl;

  /// No description provided for @novelBookmarkAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加章节书签'**
  String get novelBookmarkAdd;

  /// No description provided for @novelBookmarkRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除章节书签'**
  String get novelBookmarkRemove;

  /// No description provided for @novelBookmarkAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加书签'**
  String get novelBookmarkAdded;

  /// No description provided for @novelBookmarkRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除书签'**
  String get novelBookmarkRemoved;

  /// No description provided for @novelOpenSourceThread.
  ///
  /// In zh, this message translates to:
  /// **'打开原帖'**
  String get novelOpenSourceThread;

  /// No description provided for @novelCatalog.
  ///
  /// In zh, this message translates to:
  /// **'目录'**
  String get novelCatalog;

  /// No description provided for @novelDisplay.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get novelDisplay;

  /// No description provided for @novelPageCountPending.
  ///
  /// In zh, this message translates to:
  /// **'计算中'**
  String get novelPageCountPending;

  /// No description provided for @novelPositionChanged.
  ///
  /// In zh, this message translates to:
  /// **'位置已变化，已保留当前页'**
  String get novelPositionChanged;

  /// No description provided for @novelChapterSwitchFailed.
  ///
  /// In zh, this message translates to:
  /// **'章节切换失败，已保留当前章节'**
  String get novelChapterSwitchFailed;

  /// No description provided for @novelReturnToScrollFailed.
  ///
  /// In zh, this message translates to:
  /// **'切回滚动模式失败'**
  String get novelReturnToScrollFailed;

  /// No description provided for @novelSaveDisplaySettingsFailed.
  ///
  /// In zh, this message translates to:
  /// **'显示设置保存失败'**
  String get novelSaveDisplaySettingsFailed;

  /// No description provided for @novelLinkOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'链接打开失败'**
  String get novelLinkOpenFailed;

  /// No description provided for @novelImageLinkCopied.
  ///
  /// In zh, this message translates to:
  /// **'图片链接已复制'**
  String get novelImageLinkCopied;

  /// No description provided for @novelWorkUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'作品更新失败，已保留当前章节'**
  String get novelWorkUpdateFailed;

  /// No description provided for @novelSearchChapters.
  ///
  /// In zh, this message translates to:
  /// **'搜索章节'**
  String get novelSearchChapters;

  /// No description provided for @novelNoMatchingChapters.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的章节'**
  String get novelNoMatchingChapters;

  /// No description provided for @novelBookmark.
  ///
  /// In zh, this message translates to:
  /// **'书签'**
  String get novelBookmark;

  /// No description provided for @novelCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前'**
  String get novelCurrent;

  /// No description provided for @novelLastRead.
  ///
  /// In zh, this message translates to:
  /// **'上次阅读'**
  String get novelLastRead;

  /// No description provided for @novelNextChapter.
  ///
  /// In zh, this message translates to:
  /// **'下一章：{title}'**
  String novelNextChapter(String title);

  /// No description provided for @novelChapterUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'章节暂时无法显示'**
  String get novelChapterUnavailable;

  /// No description provided for @novelUpdateWork.
  ///
  /// In zh, this message translates to:
  /// **'更新作品'**
  String get novelUpdateWork;

  /// No description provided for @novelPagedWindowUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前窗口无法生成分页布局'**
  String get novelPagedWindowUnavailable;

  /// No description provided for @novelPagedPreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在准备分页正文'**
  String get novelPagedPreparing;

  /// No description provided for @novelPagedCalculating.
  ///
  /// In zh, this message translates to:
  /// **'正在计算分页布局'**
  String get novelPagedCalculating;

  /// No description provided for @novelPagedNoContent.
  ///
  /// In zh, this message translates to:
  /// **'本章没有可显示的正文'**
  String get novelPagedNoContent;

  /// No description provided for @novelPagedRestoringPosition.
  ///
  /// In zh, this message translates to:
  /// **'正在恢复阅读位置'**
  String get novelPagedRestoringPosition;

  /// No description provided for @novelPagedLayoutFailed.
  ///
  /// In zh, this message translates to:
  /// **'分页布局失败'**
  String get novelPagedLayoutFailed;

  /// No description provided for @novelReturnToScroll.
  ///
  /// In zh, this message translates to:
  /// **'回到滚动'**
  String get novelReturnToScroll;

  /// No description provided for @novelPages.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {0 页} other {{count} 页}}'**
  String novelPages(int count);

  /// No description provided for @novelPageSemantics.
  ///
  /// In zh, this message translates to:
  /// **'{chapterTitle}，第 {currentPage} 页，共 {totalPages}'**
  String novelPageSemantics(
    String chapterTitle,
    int currentPage,
    String totalPages,
  );

  /// No description provided for @novelPageValue.
  ///
  /// In zh, this message translates to:
  /// **'第 {currentPage} 页，共 {totalPages}'**
  String novelPageValue(int currentPage, String totalPages);

  /// No description provided for @novelNextPageSemantics.
  ///
  /// In zh, this message translates to:
  /// **'下一页，第 {page} 页'**
  String novelNextPageSemantics(int page);

  /// No description provided for @novelPreviousPageSemantics.
  ///
  /// In zh, this message translates to:
  /// **'上一页，第 {page} 页'**
  String novelPreviousPageSemantics(int page);

  /// No description provided for @novelPageIndicator.
  ///
  /// In zh, this message translates to:
  /// **'{currentPage} / {totalPages}'**
  String novelPageIndicator(int currentPage, String totalPages);

  /// No description provided for @novelChapterTurnContinue.
  ///
  /// In zh, this message translates to:
  /// **'{direction, select, next {继续滑动进入下一章} previous {继续滑动进入上一章} other {继续滑动切换章节}}'**
  String novelChapterTurnContinue(String direction);

  /// No description provided for @novelChapterTurnRelease.
  ///
  /// In zh, this message translates to:
  /// **'{direction, select, next {松手进入下一章 · {title}} previous {松手进入上一章 · {title}} other {松手切换章节 · {title}}}'**
  String novelChapterTurnRelease(String direction, String title);

  /// No description provided for @novelPageOfTotalSemantics.
  ///
  /// In zh, this message translates to:
  /// **'第 {page} 页，共 {total} 页'**
  String novelPageOfTotalSemantics(int page, int total);

  /// No description provided for @libraryOperationWorkNotFound.
  ///
  /// In zh, this message translates to:
  /// **'作品不存在或已被移除'**
  String get libraryOperationWorkNotFound;

  /// No description provided for @libraryOperationChapterNotFound.
  ///
  /// In zh, this message translates to:
  /// **'章节不存在或已被移除'**
  String get libraryOperationChapterNotFound;

  /// No description provided for @libraryOperationUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前模块不支持此操作'**
  String get libraryOperationUnsupported;

  /// No description provided for @libraryOperationCacheWriteFailed.
  ///
  /// In zh, this message translates to:
  /// **'缓存写入失败，请重试'**
  String get libraryOperationCacheWriteFailed;

  /// No description provided for @libraryOperationDefaultCategoryImmutable.
  ///
  /// In zh, this message translates to:
  /// **'默认分类不能修改或删除'**
  String get libraryOperationDefaultCategoryImmutable;

  /// No description provided for @moreTitle.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get moreTitle;

  /// No description provided for @moreMyProfile.
  ///
  /// In zh, this message translates to:
  /// **'我的资料'**
  String get moreMyProfile;

  /// No description provided for @moreMyProfileSignedOutSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'登录后查看个人资料、消息提醒'**
  String get moreMyProfileSignedOutSubtitle;

  /// 个人资料入口副标题；username 是原始用户名，不进行内容转换
  ///
  /// In zh, this message translates to:
  /// **'{username} 的资料与消息提醒'**
  String moreMyProfileSubtitle(String username);

  /// No description provided for @moreLogin.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get moreLogin;

  /// No description provided for @moreLoginSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'登录论坛账号并同步登录状态'**
  String get moreLoginSubtitle;

  /// No description provided for @moreLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get moreLogout;

  /// No description provided for @moreLogoutSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'退出当前论坛账号'**
  String get moreLogoutSubtitle;

  /// 已登录账号副标题；username 是原始用户名
  ///
  /// In zh, this message translates to:
  /// **'当前账号：{username}'**
  String moreLogoutSubtitleUsername(String username);

  /// No description provided for @moreLogoutConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get moreLogoutConfirmTitle;

  /// No description provided for @moreLogoutConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'退出后会清除本地论坛登录状态。'**
  String get moreLogoutConfirmBody;

  /// No description provided for @moreLogoutSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已退出登录'**
  String get moreLogoutSuccess;

  /// 退出登录失败提示；error 是安全的外部错误摘要
  ///
  /// In zh, this message translates to:
  /// **'退出登录失败：{error}'**
  String moreLogoutFailed(String error);

  /// No description provided for @moreForumDisplayMode.
  ///
  /// In zh, this message translates to:
  /// **'论坛显示模式'**
  String get moreForumDisplayMode;

  /// No description provided for @moreForumCurrentMode.
  ///
  /// In zh, this message translates to:
  /// **'当前：{mode}'**
  String moreForumCurrentMode(String mode);

  /// No description provided for @moreForumModeWebView.
  ///
  /// In zh, this message translates to:
  /// **'WebView 模式'**
  String get moreForumModeWebView;

  /// No description provided for @moreForumModeNative.
  ///
  /// In zh, this message translates to:
  /// **'解析模式'**
  String get moreForumModeNative;

  /// 论坛模式切换失败提示；error 是安全的外部错误摘要
  ///
  /// In zh, this message translates to:
  /// **'论坛显示模式切换失败：{error}'**
  String moreForumModeSwitchFailed(String error);

  /// No description provided for @moreAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观与文字'**
  String get moreAppearance;

  /// No description provided for @moreCurrentTheme.
  ///
  /// In zh, this message translates to:
  /// **'当前：{theme}'**
  String moreCurrentTheme(String theme);

  /// No description provided for @moreThemeSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get moreThemeSectionTitle;

  /// No description provided for @moreThemeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get moreThemeLight;

  /// No description provided for @moreThemeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get moreThemeDark;

  /// No description provided for @moreThemeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get moreThemeSystem;

  /// No description provided for @moreThemeDescriptionLight.
  ///
  /// In zh, this message translates to:
  /// **'保持浅色外观'**
  String get moreThemeDescriptionLight;

  /// No description provided for @moreThemeDescriptionDark.
  ///
  /// In zh, this message translates to:
  /// **'使用深色外观'**
  String get moreThemeDescriptionDark;

  /// No description provided for @moreThemeDescriptionSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统浅色或深色设置'**
  String get moreThemeDescriptionSystem;

  /// 保存主题偏好失败提示；error 是安全的外部错误摘要
  ///
  /// In zh, this message translates to:
  /// **'主题设置保存失败：{error}'**
  String moreThemeSaveFailed(String error);

  /// No description provided for @moreNavigationManagement.
  ///
  /// In zh, this message translates to:
  /// **'导航栏管理'**
  String get moreNavigationManagement;

  /// 更多页导航栏管理入口的可见项目数量
  ///
  /// In zh, this message translates to:
  /// **'已显示 {count, plural, =0 {0 项} other {{count} 项}}'**
  String moreVisibleNavigationCount(int count);

  /// No description provided for @moreNavigationRestoreDefault.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get moreNavigationRestoreDefault;

  /// No description provided for @moreNavigationRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get moreNavigationRetry;

  /// No description provided for @moreNavigationDragToReorder.
  ///
  /// In zh, this message translates to:
  /// **'拖动排序'**
  String get moreNavigationDragToReorder;

  /// No description provided for @moreNavigationMinimumOneRequired.
  ///
  /// In zh, this message translates to:
  /// **'至少保留一个导航项'**
  String get moreNavigationMinimumOneRequired;

  /// No description provided for @moreNavigationSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'导航栏设置保存失败'**
  String get moreNavigationSaveFailed;

  /// No description provided for @moreDataAndStorage.
  ///
  /// In zh, this message translates to:
  /// **'数据与存储'**
  String get moreDataAndStorage;

  /// No description provided for @moreDataAndStorageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'管理图片缓存与下载位置'**
  String get moreDataAndStorageSubtitle;

  /// No description provided for @moreDownloadQueue.
  ///
  /// In zh, this message translates to:
  /// **'下载队列'**
  String get moreDownloadQueue;

  /// No description provided for @moreDownloadParsingImages.
  ///
  /// In zh, this message translates to:
  /// **'正在解析图片'**
  String get moreDownloadParsingImages;

  /// 下载队列当前任务摘要；标题和章节名是原始业务内容
  ///
  /// In zh, this message translates to:
  /// **'正在下载《{comicTitle}》 {episodeTitle} · {progress}{waitingCount, plural, =0 {} other { · 等待 {waitingCount}}}'**
  String moreDownloadActiveProgress(
    String comicTitle,
    String episodeTitle,
    String progress,
    int waitingCount,
  );

  /// No description provided for @moreDownloadWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待下载 · {count, plural, =0 {0 个任务} other {{count} 个任务}}'**
  String moreDownloadWaiting(int count);

  /// No description provided for @moreDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {0 个任务下载失败} other {{count} 个任务下载失败}}'**
  String moreDownloadFailed(int count);

  /// No description provided for @moreDownloadEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无下载任务'**
  String get moreDownloadEmpty;

  /// No description provided for @moreAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get moreAbout;

  /// No description provided for @moreAboutSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'应用信息'**
  String get moreAboutSubtitle;

  /// No description provided for @moreAboutVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本 {version}'**
  String moreAboutVersion(String version);

  /// No description provided for @moreAboutVersionWithBuild.
  ///
  /// In zh, this message translates to:
  /// **'版本 {version} ({buildNumber})'**
  String moreAboutVersionWithBuild(String version, String buildNumber);

  /// No description provided for @moreAboutVersionLoading.
  ///
  /// In zh, this message translates to:
  /// **'版本读取中'**
  String get moreAboutVersionLoading;

  /// No description provided for @moreAboutVersionSection.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get moreAboutVersionSection;

  /// No description provided for @moreAboutReleaseNotes.
  ///
  /// In zh, this message translates to:
  /// **'更新日志'**
  String get moreAboutReleaseNotes;

  /// No description provided for @moreAboutProjectSection.
  ///
  /// In zh, this message translates to:
  /// **'项目'**
  String get moreAboutProjectSection;

  /// No description provided for @moreAboutGitHub.
  ///
  /// In zh, this message translates to:
  /// **'GitHub 仓库'**
  String get moreAboutGitHub;

  /// No description provided for @moreAboutOpenGitHubFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开 GitHub 仓库'**
  String get moreAboutOpenGitHubFailed;

  /// No description provided for @moreDebugQuillComposer.
  ///
  /// In zh, this message translates to:
  /// **'Quill Composer 原型'**
  String get moreDebugQuillComposer;

  /// No description provided for @moreDebugQuillComposerSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'验证所见即所得的 Discuz BBCode 转换'**
  String get moreDebugQuillComposerSubtitle;

  /// No description provided for @moreDebugHtmlRenderer.
  ///
  /// In zh, this message translates to:
  /// **'HTML 正文渲染原型'**
  String get moreDebugHtmlRenderer;

  /// No description provided for @moreDebugHtmlRendererSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'验证复杂正文 HTML 的原生渲染'**
  String get moreDebugHtmlRendererSubtitle;

  /// No description provided for @moreStorageTitle.
  ///
  /// In zh, this message translates to:
  /// **'数据与存储'**
  String get moreStorageTitle;

  /// 数据与存储页面加载失败提示；error 是安全的外部错误摘要
  ///
  /// In zh, this message translates to:
  /// **'加载数据与存储设置失败：{error}'**
  String moreStorageLoadFailed(String error);

  /// No description provided for @moreStorageClearCache.
  ///
  /// In zh, this message translates to:
  /// **'清理缓存'**
  String get moreStorageClearCache;

  /// No description provided for @moreStorageClear.
  ///
  /// In zh, this message translates to:
  /// **'清理'**
  String get moreStorageClear;

  /// No description provided for @moreStorageCacheDescription.
  ///
  /// In zh, this message translates to:
  /// **'清理 HTML、解析快照与常规图片缓存；长期缓存、封面、下载和用户数据会保留。'**
  String get moreStorageCacheDescription;

  /// No description provided for @moreStorageLocation.
  ///
  /// In zh, this message translates to:
  /// **'存储位置'**
  String get moreStorageLocation;

  /// No description provided for @moreStorageDefaultLocation.
  ///
  /// In zh, this message translates to:
  /// **'默认位置'**
  String get moreStorageDefaultLocation;

  /// No description provided for @moreStorageCustomLocation.
  ///
  /// In zh, this message translates to:
  /// **'自定义位置'**
  String get moreStorageCustomLocation;

  /// No description provided for @moreStorageChooseDirectory.
  ///
  /// In zh, this message translates to:
  /// **'选择自定义目录'**
  String get moreStorageChooseDirectory;

  /// No description provided for @moreStorageRestoreDefault.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get moreStorageRestoreDefault;

  /// No description provided for @moreStorageMaximumCache.
  ///
  /// In zh, this message translates to:
  /// **'最大缓存：{size}'**
  String moreStorageMaximumCache(String size);

  /// No description provided for @moreStorageNoticeCachePartiallyCleared.
  ///
  /// In zh, this message translates to:
  /// **'部分缓存清理失败，请稍后重试'**
  String get moreStorageNoticeCachePartiallyCleared;

  /// No description provided for @moreStorageNoticeCacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清理常规缓存，长期缓存、下载与用户数据已保留'**
  String get moreStorageNoticeCacheCleared;

  /// No description provided for @moreStorageNoticeCacheLimitUpdated.
  ///
  /// In zh, this message translates to:
  /// **'最大缓存已更新'**
  String get moreStorageNoticeCacheLimitUpdated;

  /// No description provided for @moreStorageNoticeDirectoryNotSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择目录'**
  String get moreStorageNoticeDirectoryNotSelected;

  /// No description provided for @moreStorageNoticeLocationUpdated.
  ///
  /// In zh, this message translates to:
  /// **'存储位置已更新'**
  String get moreStorageNoticeLocationUpdated;

  /// No description provided for @moreStorageNoticeDefaultRestored.
  ///
  /// In zh, this message translates to:
  /// **'已恢复默认存储位置'**
  String get moreStorageNoticeDefaultRestored;

  /// No description provided for @moreStorageNoticeUsageReloaded.
  ///
  /// In zh, this message translates to:
  /// **'存储统计已刷新'**
  String get moreStorageNoticeUsageReloaded;

  /// 缓存诊断导出完成提示；path 是本地文件路径
  ///
  /// In zh, this message translates to:
  /// **'缓存诊断已导出：{path}'**
  String moreStorageNoticeDiagnosticsExported(String path);

  /// No description provided for @moreStorageUsageOverview.
  ///
  /// In zh, this message translates to:
  /// **'缓存与数据总览'**
  String get moreStorageUsageOverview;

  /// No description provided for @moreStorageUsageTotal.
  ///
  /// In zh, this message translates to:
  /// **'应用数据总计：{size}'**
  String moreStorageUsageTotal(String size);

  /// No description provided for @moreStorageReloadUsage.
  ///
  /// In zh, this message translates to:
  /// **'重新统计'**
  String get moreStorageReloadUsage;

  /// No description provided for @moreStorageExportDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'缓存诊断导出'**
  String get moreStorageExportDiagnostics;

  /// No description provided for @moreStorageBucketImageCache.
  ///
  /// In zh, this message translates to:
  /// **'图片缓存'**
  String get moreStorageBucketImageCache;

  /// No description provided for @moreStorageBucketPageCache.
  ///
  /// In zh, this message translates to:
  /// **'页面缓存'**
  String get moreStorageBucketPageCache;

  /// No description provided for @moreStorageBucketLibraryMetadata.
  ///
  /// In zh, this message translates to:
  /// **'书架数据'**
  String get moreStorageBucketLibraryMetadata;

  /// No description provided for @moreStorageBucketHistory.
  ///
  /// In zh, this message translates to:
  /// **'浏览记录'**
  String get moreStorageBucketHistory;

  /// No description provided for @moreStorageBucketComposerDraft.
  ///
  /// In zh, this message translates to:
  /// **'草稿'**
  String get moreStorageBucketComposerDraft;

  /// No description provided for @moreStorageBucketDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载内容'**
  String get moreStorageBucketDownload;

  /// No description provided for @moreStorageBucketAppSettings.
  ///
  /// In zh, this message translates to:
  /// **'应用设置'**
  String get moreStorageBucketAppSettings;

  /// No description provided for @moreStorageCategoryClearable.
  ///
  /// In zh, this message translates to:
  /// **'可清缓存'**
  String get moreStorageCategoryClearable;

  /// No description provided for @moreStorageCategorySticky.
  ///
  /// In zh, this message translates to:
  /// **'长期缓存'**
  String get moreStorageCategorySticky;

  /// No description provided for @moreStorageCategoryProtected.
  ///
  /// In zh, this message translates to:
  /// **'受保护/下载内容'**
  String get moreStorageCategoryProtected;

  /// No description provided for @moreStorageImageRole.
  ///
  /// In zh, this message translates to:
  /// **'{role}{qualifier}'**
  String moreStorageImageRole(String role, String qualifier);

  /// No description provided for @moreStorageImageQualifierRecentReader.
  ///
  /// In zh, this message translates to:
  /// **'（最近阅读）'**
  String get moreStorageImageQualifierRecentReader;

  /// No description provided for @moreStorageImageQualifierSticky.
  ///
  /// In zh, this message translates to:
  /// **'（低淘汰）'**
  String get moreStorageImageQualifierSticky;

  /// No description provided for @moreStorageImageQualifierProtected.
  ///
  /// In zh, this message translates to:
  /// **'（受保护）'**
  String get moreStorageImageQualifierProtected;

  /// No description provided for @moreStorageImageQualifierDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'（已下载）'**
  String get moreStorageImageQualifierDownloaded;

  /// No description provided for @moreStorageImageCover.
  ///
  /// In zh, this message translates to:
  /// **'封面'**
  String get moreStorageImageCover;

  /// No description provided for @moreStorageImageCustomCover.
  ///
  /// In zh, this message translates to:
  /// **'自定义封面'**
  String get moreStorageImageCustomCover;

  /// No description provided for @moreStorageImageComicPage.
  ///
  /// In zh, this message translates to:
  /// **'漫画页'**
  String get moreStorageImageComicPage;

  /// No description provided for @moreStorageImageNovelInline.
  ///
  /// In zh, this message translates to:
  /// **'小说正文图'**
  String get moreStorageImageNovelInline;

  /// No description provided for @moreStorageImageThreadInline.
  ///
  /// In zh, this message translates to:
  /// **'帖子图片'**
  String get moreStorageImageThreadInline;

  /// No description provided for @moreStorageImageThreadAttachment.
  ///
  /// In zh, this message translates to:
  /// **'帖子附件图'**
  String get moreStorageImageThreadAttachment;

  /// No description provided for @moreStorageImageAvatar.
  ///
  /// In zh, this message translates to:
  /// **'头像'**
  String get moreStorageImageAvatar;

  /// No description provided for @moreStorageImageRemoteSmiley.
  ///
  /// In zh, this message translates to:
  /// **'表情图片'**
  String get moreStorageImageRemoteSmiley;

  /// No description provided for @moreStorageImageForumHead.
  ///
  /// In zh, this message translates to:
  /// **'论坛头图'**
  String get moreStorageImageForumHead;

  /// No description provided for @moreStorageImageForumIcon.
  ///
  /// In zh, this message translates to:
  /// **'论坛图标'**
  String get moreStorageImageForumIcon;

  /// No description provided for @moreStorageImageBlogInline.
  ///
  /// In zh, this message translates to:
  /// **'日志图片'**
  String get moreStorageImageBlogInline;

  /// No description provided for @moreStorageImageUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未分类图片'**
  String get moreStorageImageUnknown;

  /// No description provided for @moreStorageDocumentForum.
  ///
  /// In zh, this message translates to:
  /// **'论坛首页'**
  String get moreStorageDocumentForum;

  /// No description provided for @moreStorageDocumentForumDisplay.
  ///
  /// In zh, this message translates to:
  /// **'帖子列表'**
  String get moreStorageDocumentForumDisplay;

  /// No description provided for @moreStorageDocumentThread.
  ///
  /// In zh, this message translates to:
  /// **'帖子详情'**
  String get moreStorageDocumentThread;

  /// No description provided for @moreStorageDocumentTag.
  ///
  /// In zh, this message translates to:
  /// **'标签页'**
  String get moreStorageDocumentTag;

  /// No description provided for @moreStorageDocumentProfile.
  ///
  /// In zh, this message translates to:
  /// **'个人资料'**
  String get moreStorageDocumentProfile;

  /// No description provided for @moreStorageDocumentBlog.
  ///
  /// In zh, this message translates to:
  /// **'日志'**
  String get moreStorageDocumentBlog;

  /// No description provided for @moreStorageDocumentUnknown.
  ///
  /// In zh, this message translates to:
  /// **'页面'**
  String get moreStorageDocumentUnknown;

  /// No description provided for @moreStorageDocumentHtml.
  ///
  /// In zh, this message translates to:
  /// **'{owner} HTML（{count}）'**
  String moreStorageDocumentHtml(String owner, int count);

  /// No description provided for @moreStorageSnapshot.
  ///
  /// In zh, this message translates to:
  /// **'{snapshotType}快照（{count}）'**
  String moreStorageSnapshot(String snapshotType, int count);

  /// No description provided for @moreStorageSnapshotForumHome.
  ///
  /// In zh, this message translates to:
  /// **'论坛首页'**
  String get moreStorageSnapshotForumHome;

  /// No description provided for @moreStorageSnapshotForumDisplay.
  ///
  /// In zh, this message translates to:
  /// **'帖子列表'**
  String get moreStorageSnapshotForumDisplay;

  /// No description provided for @moreStorageSnapshotThreadDetail.
  ///
  /// In zh, this message translates to:
  /// **'帖子详情'**
  String get moreStorageSnapshotThreadDetail;

  /// No description provided for @moreStorageSnapshotUnknown.
  ///
  /// In zh, this message translates to:
  /// **'页面解析'**
  String get moreStorageSnapshotUnknown;

  /// No description provided for @moreStorageComposerDraft.
  ///
  /// In zh, this message translates to:
  /// **'发帖/回复草稿（{count}）'**
  String moreStorageComposerDraft(int count);

  /// No description provided for @moreStorageDownloadComics.
  ///
  /// In zh, this message translates to:
  /// **'漫画下载'**
  String get moreStorageDownloadComics;

  /// No description provided for @moreStorageDownloadNovels.
  ///
  /// In zh, this message translates to:
  /// **'小说下载'**
  String get moreStorageDownloadNovels;

  /// No description provided for @moreStorageDownloadFavorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏快照'**
  String get moreStorageDownloadFavorites;

  /// No description provided for @moreStorageDatabase.
  ///
  /// In zh, this message translates to:
  /// **'本地数据库'**
  String get moreStorageDatabase;

  /// No description provided for @moreStorageLibraryCount.
  ///
  /// In zh, this message translates to:
  /// **'{kind}：{count}'**
  String moreStorageLibraryCount(String kind, int count);

  /// No description provided for @moreStorageLibraryComics.
  ///
  /// In zh, this message translates to:
  /// **'漫画作品'**
  String get moreStorageLibraryComics;

  /// No description provided for @moreStorageLibraryComicEpisodes.
  ///
  /// In zh, this message translates to:
  /// **'漫画章节'**
  String get moreStorageLibraryComicEpisodes;

  /// No description provided for @moreStorageLibraryNovels.
  ///
  /// In zh, this message translates to:
  /// **'小说作品'**
  String get moreStorageLibraryNovels;

  /// No description provided for @moreStorageLibraryNovelEpisodes.
  ///
  /// In zh, this message translates to:
  /// **'小说章节'**
  String get moreStorageLibraryNovelEpisodes;

  /// No description provided for @moreStorageLibraryFavorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏帖子'**
  String get moreStorageLibraryFavorites;

  /// No description provided for @moreStorageLibraryWorkState.
  ///
  /// In zh, this message translates to:
  /// **'作品状态'**
  String get moreStorageLibraryWorkState;

  /// No description provided for @moreStorageLibraryEpisodeState.
  ///
  /// In zh, this message translates to:
  /// **'章节状态'**
  String get moreStorageLibraryEpisodeState;

  /// No description provided for @moreStorageHistoryDatabase.
  ///
  /// In zh, this message translates to:
  /// **'记录数据库'**
  String get moreStorageHistoryDatabase;

  /// No description provided for @moreStorageHistoryEntries.
  ///
  /// In zh, this message translates to:
  /// **'浏览记录：{count}'**
  String moreStorageHistoryEntries(int count);

  /// No description provided for @threadDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'帖子详情'**
  String get threadDetailTitle;

  /// No description provided for @threadDetailRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新帖子详情'**
  String get threadDetailRefresh;

  /// No description provided for @threadDetailOnlyAuthor.
  ///
  /// In zh, this message translates to:
  /// **'只看该作者'**
  String get threadDetailOnlyAuthor;

  /// No description provided for @threadDetailAllPosts.
  ///
  /// In zh, this message translates to:
  /// **'显示全部楼层'**
  String get threadDetailAllPosts;

  /// No description provided for @threadDetailReverseOrder.
  ///
  /// In zh, this message translates to:
  /// **'倒序浏览'**
  String get threadDetailReverseOrder;

  /// No description provided for @threadDetailNormalOrder.
  ///
  /// In zh, this message translates to:
  /// **'正序浏览'**
  String get threadDetailNormalOrder;

  /// No description provided for @threadDetailPreviousPage.
  ///
  /// In zh, this message translates to:
  /// **'上一页'**
  String get threadDetailPreviousPage;

  /// No description provided for @threadDetailNextPage.
  ///
  /// In zh, this message translates to:
  /// **'下一页'**
  String get threadDetailNextPage;

  /// No description provided for @threadDetailNoMore.
  ///
  /// In zh, this message translates to:
  /// **'没有更多'**
  String get threadDetailNoMore;

  /// No description provided for @threadDetailPage.
  ///
  /// In zh, this message translates to:
  /// **'第{page}页'**
  String threadDetailPage(int page);

  /// No description provided for @threadDetailReply.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get threadDetailReply;

  /// No description provided for @threadDetailReplyPost.
  ///
  /// In zh, this message translates to:
  /// **'回复帖子'**
  String get threadDetailReplyPost;

  /// No description provided for @threadDetailEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get threadDetailEdit;

  /// No description provided for @threadDetailShare.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get threadDetailShare;

  /// No description provided for @threadDetailCopyLink.
  ///
  /// In zh, this message translates to:
  /// **'复制链接'**
  String get threadDetailCopyLink;

  /// No description provided for @threadDetailPostLink.
  ///
  /// In zh, this message translates to:
  /// **'帖子链接'**
  String get threadDetailPostLink;

  /// No description provided for @threadDetailFloorLink.
  ///
  /// In zh, this message translates to:
  /// **'楼层链接'**
  String get threadDetailFloorLink;

  /// No description provided for @threadDetailCopyFloorLink.
  ///
  /// In zh, this message translates to:
  /// **'复制楼层链接'**
  String get threadDetailCopyFloorLink;

  /// No description provided for @threadDetailCopyFloorLinkFailed.
  ///
  /// In zh, this message translates to:
  /// **'楼层链接复制失败'**
  String get threadDetailCopyFloorLinkFailed;

  /// No description provided for @threadDetailExternalLink.
  ///
  /// In zh, this message translates to:
  /// **'外部链接'**
  String get threadDetailExternalLink;

  /// No description provided for @threadDetailHomeLink.
  ///
  /// In zh, this message translates to:
  /// **'首页链接'**
  String get threadDetailHomeLink;

  /// No description provided for @threadDetailReplyLink.
  ///
  /// In zh, this message translates to:
  /// **'楼层回复链接'**
  String get threadDetailReplyLink;

  /// No description provided for @threadDetailCopySuccess.
  ///
  /// In zh, this message translates to:
  /// **'{target}已复制'**
  String threadDetailCopySuccess(String target);

  /// No description provided for @threadDetailFavorite.
  ///
  /// In zh, this message translates to:
  /// **'收藏帖子'**
  String get threadDetailFavorite;

  /// No description provided for @threadDetailUnfavorite.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get threadDetailUnfavorite;

  /// No description provided for @threadDetailOpenSource.
  ///
  /// In zh, this message translates to:
  /// **'打开原帖'**
  String get threadDetailOpenSource;

  /// No description provided for @threadDetailMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get threadDetailMore;

  /// No description provided for @threadDetailDisplaySettings.
  ///
  /// In zh, this message translates to:
  /// **'显示设置'**
  String get threadDetailDisplaySettings;

  /// No description provided for @threadDetailBackHome.
  ///
  /// In zh, this message translates to:
  /// **'返回首页'**
  String get threadDetailBackHome;

  /// No description provided for @threadDetailSelectCopy.
  ///
  /// In zh, this message translates to:
  /// **'选择复制'**
  String get threadDetailSelectCopy;

  /// No description provided for @threadDetailCopyAll.
  ///
  /// In zh, this message translates to:
  /// **'全部复制'**
  String get threadDetailCopyAll;

  /// No description provided for @threadDetailLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'帖子详情加载失败：{error}'**
  String threadDetailLoadFailed(String error);

  /// No description provided for @threadDetailRefreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'刷新帖子详情失败：{error}'**
  String threadDetailRefreshFailed(String error);

  /// No description provided for @threadDetailPageLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'页面加载失败：{error}'**
  String threadDetailPageLoadFailed(String error);

  /// No description provided for @threadDetailFloorLocatorFailed.
  ///
  /// In zh, this message translates to:
  /// **'楼层定位失败，已打开帖子'**
  String get threadDetailFloorLocatorFailed;

  /// No description provided for @threadDetailUidMissing.
  ///
  /// In zh, this message translates to:
  /// **'用户 UID 缺失'**
  String get threadDetailUidMissing;

  /// No description provided for @threadFavoriteFailed.
  ///
  /// In zh, this message translates to:
  /// **'收藏操作失败：{error}'**
  String threadFavoriteFailed(String error);

  /// No description provided for @threadLoginRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先登录后再操作'**
  String get threadLoginRequired;

  /// No description provided for @threadPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'没有执行此操作的权限'**
  String get threadPermissionDenied;

  /// No description provided for @threadUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前暂不支持此操作'**
  String get threadUnsupported;

  /// No description provided for @threadDetailAnonymous.
  ///
  /// In zh, this message translates to:
  /// **'匿名'**
  String get threadDetailAnonymous;

  /// No description provided for @threadDetailImageLink.
  ///
  /// In zh, this message translates to:
  /// **'图片链接'**
  String get threadDetailImageLink;

  /// No description provided for @threadDetailPostBody.
  ///
  /// In zh, this message translates to:
  /// **'正文'**
  String get threadDetailPostBody;

  /// No description provided for @threadPollVote.
  ///
  /// In zh, this message translates to:
  /// **'投票'**
  String get threadPollVote;

  /// No description provided for @threadPollMultipleChoice.
  ///
  /// In zh, this message translates to:
  /// **'可多选'**
  String get threadPollMultipleChoice;

  /// No description provided for @threadPollDeadline.
  ///
  /// In zh, this message translates to:
  /// **'截止时间'**
  String get threadPollDeadline;

  /// No description provided for @threadPollResults.
  ///
  /// In zh, this message translates to:
  /// **'投票结果'**
  String get threadPollResults;

  /// No description provided for @threadPollSubmit.
  ///
  /// In zh, this message translates to:
  /// **'提交'**
  String get threadPollSubmit;

  /// No description provided for @threadPollMaxChoices.
  ///
  /// In zh, this message translates to:
  /// **'最多可选 {count} 项'**
  String threadPollMaxChoices(int count);

  /// No description provided for @threadPollSelectOption.
  ///
  /// In zh, this message translates to:
  /// **'请选择投票选项'**
  String get threadPollSelectOption;

  /// No description provided for @threadPollVoteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'投票成功'**
  String get threadPollVoteSuccess;

  /// No description provided for @threadPollVoteFailed.
  ///
  /// In zh, this message translates to:
  /// **'投票失败：{error}'**
  String threadPollVoteFailed(String error);

  /// No description provided for @threadPollVotes.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {0 票} other {{count} 票}}'**
  String threadPollVotes(int count);

  /// No description provided for @threadRatingTitle.
  ///
  /// In zh, this message translates to:
  /// **'评分'**
  String get threadRatingTitle;

  /// No description provided for @threadRatingSubmit.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get threadRatingSubmit;

  /// No description provided for @threadRatingScore.
  ///
  /// In zh, this message translates to:
  /// **'积分'**
  String get threadRatingScore;

  /// No description provided for @threadRatingReasonHint.
  ///
  /// In zh, this message translates to:
  /// **'评分理由'**
  String get threadRatingReasonHint;

  /// No description provided for @threadRatingNotifyAuthor.
  ///
  /// In zh, this message translates to:
  /// **'通知作者'**
  String get threadRatingNotifyAuthor;

  /// No description provided for @threadRatingRange.
  ///
  /// In zh, this message translates to:
  /// **'范围 {min}~{max}'**
  String threadRatingRange(int min, int max);

  /// No description provided for @threadRatingRangeWithRemaining.
  ///
  /// In zh, this message translates to:
  /// **'{range}，今日剩余 {remaining, plural, =0 {0} other {{remaining}}}'**
  String threadRatingRangeWithRemaining(String range, int remaining);

  /// No description provided for @threadRatingRemaining.
  ///
  /// In zh, this message translates to:
  /// **'今日剩余 {count}'**
  String threadRatingRemaining(int count);

  /// No description provided for @threadRatingParticipants.
  ///
  /// In zh, this message translates to:
  /// **'参与人数'**
  String get threadRatingParticipants;

  /// No description provided for @threadRatingParticipantsCount.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {参与人数 0} other {参与人数 {count}}}'**
  String threadRatingParticipantsCount(int count);

  /// No description provided for @threadRatingPoints.
  ///
  /// In zh, this message translates to:
  /// **'积分'**
  String get threadRatingPoints;

  /// No description provided for @threadRatingReason.
  ///
  /// In zh, this message translates to:
  /// **'理由'**
  String get threadRatingReason;

  /// No description provided for @threadRatingLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'完整评分加载失败'**
  String get threadRatingLoadFailed;

  /// No description provided for @threadRatingRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试加载完整评分'**
  String get threadRatingRetry;

  /// No description provided for @threadRatingExpand.
  ///
  /// In zh, this message translates to:
  /// **'展开完整评分'**
  String get threadRatingExpand;

  /// No description provided for @threadRatingUnknownUser.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get threadRatingUnknownUser;

  /// No description provided for @threadRatingSuccess.
  ///
  /// In zh, this message translates to:
  /// **'评分成功'**
  String get threadRatingSuccess;

  /// No description provided for @threadRatingFailed.
  ///
  /// In zh, this message translates to:
  /// **'评分失败：{error}'**
  String threadRatingFailed(String error);

  /// No description provided for @threadCommentTitle.
  ///
  /// In zh, this message translates to:
  /// **'点评'**
  String get threadCommentTitle;

  /// No description provided for @threadCommentSubmit.
  ///
  /// In zh, this message translates to:
  /// **'发布'**
  String get threadCommentSubmit;

  /// No description provided for @threadCommentContent.
  ///
  /// In zh, this message translates to:
  /// **'点评内容'**
  String get threadCommentContent;

  /// No description provided for @threadCommentSuccess.
  ///
  /// In zh, this message translates to:
  /// **'点评成功'**
  String get threadCommentSuccess;

  /// No description provided for @threadCommentFailed.
  ///
  /// In zh, this message translates to:
  /// **'点评失败：{error}'**
  String threadCommentFailed(String error);

  /// No description provided for @threadReplyContentRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入回复内容'**
  String get threadReplyContentRequired;

  /// No description provided for @threadReplySuccess.
  ///
  /// In zh, this message translates to:
  /// **'回复成功'**
  String get threadReplySuccess;

  /// No description provided for @threadReplyFailed.
  ///
  /// In zh, this message translates to:
  /// **'回复失败：{error}'**
  String threadReplyFailed(String error);

  /// No description provided for @threadAttachmentOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开附件'**
  String get threadAttachmentOpen;

  /// No description provided for @threadImageSave.
  ///
  /// In zh, this message translates to:
  /// **'保存图片'**
  String get threadImageSave;

  /// No description provided for @threadImageDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载当前图片'**
  String get threadImageDownload;

  /// No description provided for @threadImageReaderTitle.
  ///
  /// In zh, this message translates to:
  /// **'图片阅读'**
  String get threadImageReaderTitle;

  /// No description provided for @threadImageDisplay.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get threadImageDisplay;

  /// No description provided for @threadHtmlConversionOriginal.
  ///
  /// In zh, this message translates to:
  /// **'原文'**
  String get threadHtmlConversionOriginal;

  /// No description provided for @threadHtmlConversionSimplified.
  ///
  /// In zh, this message translates to:
  /// **'简体'**
  String get threadHtmlConversionSimplified;

  /// No description provided for @threadHtmlConversionTraditional.
  ///
  /// In zh, this message translates to:
  /// **'繁体'**
  String get threadHtmlConversionTraditional;

  /// No description provided for @threadHtmlConversionSettings.
  ///
  /// In zh, this message translates to:
  /// **'阅读设置'**
  String get threadHtmlConversionSettings;

  /// No description provided for @threadHtmlFontSize.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get threadHtmlFontSize;

  /// No description provided for @threadHtmlLineSpacing.
  ///
  /// In zh, this message translates to:
  /// **'间隔'**
  String get threadHtmlLineSpacing;

  /// No description provided for @threadHtmlPreserveAuthorFontSize.
  ///
  /// In zh, this message translates to:
  /// **'保留作者字号'**
  String get threadHtmlPreserveAuthorFontSize;

  /// No description provided for @threadHtmlReset.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get threadHtmlReset;

  /// No description provided for @threadHtmlCollapseContent.
  ///
  /// In zh, this message translates to:
  /// **'折叠内容'**
  String get threadHtmlCollapseContent;

  /// No description provided for @threadHtmlRenderFailed.
  ///
  /// In zh, this message translates to:
  /// **'正文渲染失败，可长按楼层复制正文或打开原帖查看。'**
  String get threadHtmlRenderFailed;

  /// No description provided for @threadSelectionCopyTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择复制'**
  String get threadSelectionCopyTitle;

  /// No description provided for @threadDetailScrollTop.
  ///
  /// In zh, this message translates to:
  /// **'滚动到顶部'**
  String get threadDetailScrollTop;

  /// No description provided for @threadDetailScrollBottom.
  ///
  /// In zh, this message translates to:
  /// **'滚动到底部'**
  String get threadDetailScrollBottom;

  /// No description provided for @commonUse.
  ///
  /// In zh, this message translates to:
  /// **'使用'**
  String get commonUse;

  /// No description provided for @commonReset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get commonReset;

  /// No description provided for @composerBold.
  ///
  /// In zh, this message translates to:
  /// **'加粗'**
  String get composerBold;

  /// No description provided for @composerItalic.
  ///
  /// In zh, this message translates to:
  /// **'斜体'**
  String get composerItalic;

  /// No description provided for @composerUnderline.
  ///
  /// In zh, this message translates to:
  /// **'下划线'**
  String get composerUnderline;

  /// No description provided for @composerStrikethrough.
  ///
  /// In zh, this message translates to:
  /// **'删除线'**
  String get composerStrikethrough;

  /// No description provided for @composerTextColor.
  ///
  /// In zh, this message translates to:
  /// **'字体色'**
  String get composerTextColor;

  /// No description provided for @composerBackgroundColor.
  ///
  /// In zh, this message translates to:
  /// **'背景色'**
  String get composerBackgroundColor;

  /// No description provided for @composerLink.
  ///
  /// In zh, this message translates to:
  /// **'链接'**
  String get composerLink;

  /// No description provided for @composerFontSize.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get composerFontSize;

  /// No description provided for @composerAlignment.
  ///
  /// In zh, this message translates to:
  /// **'对齐'**
  String get composerAlignment;

  /// No description provided for @composerQuote.
  ///
  /// In zh, this message translates to:
  /// **'引用'**
  String get composerQuote;

  /// No description provided for @composerImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get composerImage;

  /// No description provided for @composerSticker.
  ///
  /// In zh, this message translates to:
  /// **'表情'**
  String get composerSticker;

  /// No description provided for @composerFormat.
  ///
  /// In zh, this message translates to:
  /// **'格式'**
  String get composerFormat;

  /// No description provided for @composerPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get composerPreview;

  /// No description provided for @composerSourceMode.
  ///
  /// In zh, this message translates to:
  /// **'源码'**
  String get composerSourceMode;

  /// No description provided for @composerVisualMode.
  ///
  /// In zh, this message translates to:
  /// **'返回编辑'**
  String get composerVisualMode;

  /// No description provided for @composerMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get composerMore;

  /// No description provided for @composerMoreSettings.
  ///
  /// In zh, this message translates to:
  /// **'更多设置'**
  String get composerMoreSettings;

  /// No description provided for @composerUseSignature.
  ///
  /// In zh, this message translates to:
  /// **'使用个人签名'**
  String get composerUseSignature;

  /// No description provided for @composerResetDraft.
  ///
  /// In zh, this message translates to:
  /// **'重置草稿'**
  String get composerResetDraft;

  /// No description provided for @composerResetDraftTitle.
  ///
  /// In zh, this message translates to:
  /// **'重置草稿？'**
  String get composerResetDraftTitle;

  /// No description provided for @composerResetDraftBody.
  ///
  /// In zh, this message translates to:
  /// **'当前编辑内容和已选图片将被清空，且无法恢复。'**
  String get composerResetDraftBody;

  /// No description provided for @composerContinueEditing.
  ///
  /// In zh, this message translates to:
  /// **'继续编辑'**
  String get composerContinueEditing;

  /// No description provided for @composerSaveDraftAndLeave.
  ///
  /// In zh, this message translates to:
  /// **'保存草稿并离开'**
  String get composerSaveDraftAndLeave;

  /// No description provided for @composerRestoredDraft.
  ///
  /// In zh, this message translates to:
  /// **'已恢复未发送草稿'**
  String get composerRestoredDraft;

  /// No description provided for @postingRestoredDraftWithTags.
  ///
  /// In zh, this message translates to:
  /// **'已恢复未发送的草稿，请注意已恢复的主题标签'**
  String get postingRestoredDraftWithTags;

  /// No description provided for @composerPendingAttachment.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {图片已上传，请选择位置后点击图片按钮重新插入} other {{count} 张图片已上传，请选择位置后点击图片按钮重新插入}}'**
  String composerPendingAttachment(int count);

  /// No description provided for @composerPendingAttachmentSelectionExpired.
  ///
  /// In zh, this message translates to:
  /// **'当前选区无法安全恢复，请重新选择位置'**
  String get composerPendingAttachmentSelectionExpired;

  /// No description provided for @composerUploadingImages.
  ///
  /// In zh, this message translates to:
  /// **'正在上传图片 {current}/{total}'**
  String composerUploadingImages(int current, int total);

  /// No description provided for @composerImageUploaded.
  ///
  /// In zh, this message translates to:
  /// **'{fileName} 已上传'**
  String composerImageUploaded(String fileName);

  /// No description provided for @composerImageUploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'{fileName} 上传失败，请重试'**
  String composerImageUploadFailed(String fileName);

  /// No description provided for @composerImageUploadFailedWithReason.
  ///
  /// In zh, this message translates to:
  /// **'{fileName} 上传失败：{reason}'**
  String composerImageUploadFailedWithReason(String fileName, String reason);

  /// No description provided for @composerImagePickerFailed.
  ///
  /// In zh, this message translates to:
  /// **'选择图片失败，请重试'**
  String get composerImagePickerFailed;

  /// No description provided for @composerImageFileMissing.
  ///
  /// In zh, this message translates to:
  /// **'图片文件不存在，无法上传'**
  String get composerImageFileMissing;

  /// No description provided for @composerImageInvalidFileType.
  ///
  /// In zh, this message translates to:
  /// **'只能上传图片文件'**
  String get composerImageInvalidFileType;

  /// No description provided for @composerImageExtensionNotAllowed.
  ///
  /// In zh, this message translates to:
  /// **'当前版块不允许上传该类型图片'**
  String get composerImageExtensionNotAllowed;

  /// No description provided for @composerImagePermissionExpired.
  ///
  /// In zh, this message translates to:
  /// **'上传权限已失效，请重新登录'**
  String get composerImagePermissionExpired;

  /// No description provided for @composerImageQuotaExceeded.
  ///
  /// In zh, this message translates to:
  /// **'附件额度不足，无法上传图片'**
  String get composerImageQuotaExceeded;

  /// No description provided for @composerImageUploadTimeout.
  ///
  /// In zh, this message translates to:
  /// **'图片上传超时，请重试'**
  String get composerImageUploadTimeout;

  /// No description provided for @composerImageUploadNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络异常，图片上传失败'**
  String get composerImageUploadNetwork;

  /// No description provided for @composerImageUploadServer.
  ///
  /// In zh, this message translates to:
  /// **'上传服务异常，请稍后重试'**
  String get composerImageUploadServer;

  /// No description provided for @composerImageUploadUnknown.
  ///
  /// In zh, this message translates to:
  /// **'图片上传失败，请重试'**
  String get composerImageUploadUnknown;

  /// No description provided for @composerLoadDraftFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载草稿失败：{error}'**
  String composerLoadDraftFailed(String error);

  /// No description provided for @composerStickerLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'表情加载失败：{error}'**
  String composerStickerLoadFailed(String error);

  /// No description provided for @composerStickerNetworkRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要联网加载表情包'**
  String get composerStickerNetworkRequired;

  /// No description provided for @composerStickerAllGroup.
  ///
  /// In zh, this message translates to:
  /// **'表情'**
  String get composerStickerAllGroup;

  /// No description provided for @composerStickerDefaultGroup.
  ///
  /// In zh, this message translates to:
  /// **'默认表情'**
  String get composerStickerDefaultGroup;

  /// No description provided for @composerStartTypingHint.
  ///
  /// In zh, this message translates to:
  /// **'请开始输入'**
  String get composerStartTypingHint;

  /// No description provided for @composerImageRetentionHint.
  ///
  /// In zh, this message translates to:
  /// **'请注意上传的图片仅在本地保存 24 小时'**
  String get composerImageRetentionHint;

  /// No description provided for @composerLinkTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加链接'**
  String get composerLinkTitle;

  /// No description provided for @composerLinkUrl.
  ///
  /// In zh, this message translates to:
  /// **'链接'**
  String get composerLinkUrl;

  /// No description provided for @composerLinkText.
  ///
  /// In zh, this message translates to:
  /// **'链接文字'**
  String get composerLinkText;

  /// No description provided for @composerLinkTextHint.
  ///
  /// In zh, this message translates to:
  /// **'显示给别人看的文字'**
  String get composerLinkTextHint;

  /// No description provided for @composerLinkUrlRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入链接'**
  String get composerLinkUrlRequired;

  /// No description provided for @composerLinkTextRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入链接文字'**
  String get composerLinkTextRequired;

  /// No description provided for @composerAlignLeft.
  ///
  /// In zh, this message translates to:
  /// **'左对齐'**
  String get composerAlignLeft;

  /// No description provided for @composerAlignCenter.
  ///
  /// In zh, this message translates to:
  /// **'居中'**
  String get composerAlignCenter;

  /// No description provided for @composerAlignRight.
  ///
  /// In zh, this message translates to:
  /// **'右对齐'**
  String get composerAlignRight;

  /// No description provided for @composerClearFormatting.
  ///
  /// In zh, this message translates to:
  /// **'清除状态'**
  String get composerClearFormatting;

  /// No description provided for @composerClearFontSize.
  ///
  /// In zh, this message translates to:
  /// **'清除字号'**
  String get composerClearFontSize;

  /// No description provided for @composerClearTextColor.
  ///
  /// In zh, this message translates to:
  /// **'清除颜色'**
  String get composerClearTextColor;

  /// No description provided for @composerClearBackgroundColor.
  ///
  /// In zh, this message translates to:
  /// **'清除背景'**
  String get composerClearBackgroundColor;

  /// No description provided for @composerAuthenticationRequired.
  ///
  /// In zh, this message translates to:
  /// **'登录状态已失效，请重新登录后再试'**
  String get composerAuthenticationRequired;

  /// No description provided for @composerCredentialExpired.
  ///
  /// In zh, this message translates to:
  /// **'{kind, select, newThread {发帖凭证已失效，请刷新登录态后重试} reply {回复凭证已失效，请刷新登录态后重试} other {提交凭证已失效，请刷新登录态后重试}}'**
  String composerCredentialExpired(String kind);

  /// No description provided for @composerRateLimited.
  ///
  /// In zh, this message translates to:
  /// **'{kind, select, newThread {发帖过于频繁，请稍后再试} reply {回复太频繁了，请稍后再试} other {操作过于频繁，请稍后再试}}'**
  String composerRateLimited(String kind);

  /// No description provided for @composerPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'{kind, select, newThread {当前账号权限不足，无法发帖} reply {当前账号权限不足，无法发送回复} other {当前账号权限不足}}'**
  String composerPermissionDenied(String kind);

  /// No description provided for @composerSubmissionTypeRequired.
  ///
  /// In zh, this message translates to:
  /// **'该版块要求选择主题分类，请先选择'**
  String get composerSubmissionTypeRequired;

  /// No description provided for @composerSubmissionContentTooShort.
  ///
  /// In zh, this message translates to:
  /// **'{kind, select, newThread {标题或内容过短} reply {回复内容过短} other {提交内容过短}}'**
  String composerSubmissionContentTooShort(String kind);

  /// No description provided for @composerCaptchaRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要验证码，请暂时改用网页发布'**
  String get composerCaptchaRequired;

  /// No description provided for @composerPollInvalid.
  ///
  /// In zh, this message translates to:
  /// **'投票配置无效，请检查选项与截止时间'**
  String get composerPollInvalid;

  /// No description provided for @composerPollOptionCountInvalid.
  ///
  /// In zh, this message translates to:
  /// **'投票选项数量不合法'**
  String get composerPollOptionCountInvalid;

  /// No description provided for @composerPollFieldsInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请正确填写投票相关字段'**
  String get composerPollFieldsInvalid;

  /// No description provided for @composerNetworkTimeout.
  ///
  /// In zh, this message translates to:
  /// **'网络超时，请稍后重试'**
  String get composerNetworkTimeout;

  /// No description provided for @composerNetworkFailure.
  ///
  /// In zh, this message translates to:
  /// **'网络异常，请稍后重试'**
  String get composerNetworkFailure;

  /// No description provided for @composerServerFailure.
  ///
  /// In zh, this message translates to:
  /// **'服务异常，请稍后重试'**
  String get composerServerFailure;

  /// No description provided for @composerUnknownFailure.
  ///
  /// In zh, this message translates to:
  /// **'{kind, select, newThread {发帖失败，请稍后重试} reply {发送回复失败，请稍后重试} other {提交失败，请稍后重试}}'**
  String composerUnknownFailure(String kind);

  /// No description provided for @postingTitle.
  ///
  /// In zh, this message translates to:
  /// **'发帖'**
  String get postingTitle;

  /// No description provided for @postingTitleWithForum.
  ///
  /// In zh, this message translates to:
  /// **'发帖 — {forumName}'**
  String postingTitleWithForum(String forumName);

  /// No description provided for @postingSend.
  ///
  /// In zh, this message translates to:
  /// **'发布'**
  String get postingSend;

  /// No description provided for @postingSubjectHint.
  ///
  /// In zh, this message translates to:
  /// **'输入标题'**
  String get postingSubjectHint;

  /// No description provided for @postingBodyHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入正文'**
  String get postingBodyHint;

  /// No description provided for @postingFormLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在加载发帖表单'**
  String get postingFormLoading;

  /// No description provided for @postingFormLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载发帖表单失败：{error}'**
  String postingFormLoadFailed(String error);

  /// No description provided for @postingType.
  ///
  /// In zh, this message translates to:
  /// **'主题分类'**
  String get postingType;

  /// No description provided for @postingTypeRequired.
  ///
  /// In zh, this message translates to:
  /// **'主题分类（必选）'**
  String get postingTypeRequired;

  /// No description provided for @postingTypeNone.
  ///
  /// In zh, this message translates to:
  /// **'无分类'**
  String get postingTypeNone;

  /// No description provided for @postingTypeUnselected.
  ///
  /// In zh, this message translates to:
  /// **'未选择'**
  String get postingTypeUnselected;

  /// No description provided for @postingTags.
  ///
  /// In zh, this message translates to:
  /// **'主题标签'**
  String get postingTags;

  /// No description provided for @postingTagsHint.
  ///
  /// In zh, this message translates to:
  /// **'输入标签，回车或英文逗号确认'**
  String get postingTagsHint;

  /// No description provided for @postingTagDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除标签'**
  String get postingTagDelete;

  /// No description provided for @postingTagsLimit.
  ///
  /// In zh, this message translates to:
  /// **'最多 {maxTags} 个；单个标签 ≤ {maxLength} 字符'**
  String postingTagsLimit(int maxTags, int maxLength);

  /// No description provided for @postingNormalThread.
  ///
  /// In zh, this message translates to:
  /// **'普通帖'**
  String get postingNormalThread;

  /// No description provided for @postingPoll.
  ///
  /// In zh, this message translates to:
  /// **'投票'**
  String get postingPoll;

  /// No description provided for @postingPollConfig.
  ///
  /// In zh, this message translates to:
  /// **'投票配置'**
  String get postingPollConfig;

  /// No description provided for @postingThreadKind.
  ///
  /// In zh, this message translates to:
  /// **'帖子类型'**
  String get postingThreadKind;

  /// No description provided for @postingPollConstraints.
  ///
  /// In zh, this message translates to:
  /// **'至少 {min} 个选项；最多 {max} 个，单项 ≤ {maxLength} 字符'**
  String postingPollConstraints(int min, int max, int maxLength);

  /// No description provided for @postingPollSummary.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {尚未填写选项 / {mode}} other {已填 {count} 项 / {mode}}}'**
  String postingPollSummary(int count, String mode);

  /// No description provided for @postingPollSingle.
  ///
  /// In zh, this message translates to:
  /// **'单选'**
  String get postingPollSingle;

  /// No description provided for @postingPollMultipleMode.
  ///
  /// In zh, this message translates to:
  /// **'多选'**
  String get postingPollMultipleMode;

  /// No description provided for @postingPollOption.
  ///
  /// In zh, this message translates to:
  /// **'选项 {index}'**
  String postingPollOption(int index);

  /// No description provided for @postingPollAddOption.
  ///
  /// In zh, this message translates to:
  /// **'添加选项'**
  String get postingPollAddOption;

  /// No description provided for @postingPollRemoveOption.
  ///
  /// In zh, this message translates to:
  /// **'删除选项'**
  String get postingPollRemoveOption;

  /// No description provided for @postingPollMultiple.
  ///
  /// In zh, this message translates to:
  /// **'允许多选'**
  String get postingPollMultiple;

  /// No description provided for @postingPollMaxChoices.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {不可选择选项} other {最多可选 {count} 项}}'**
  String postingPollMaxChoices(int count);

  /// No description provided for @postingPollDeadline.
  ///
  /// In zh, this message translates to:
  /// **'截止天数'**
  String get postingPollDeadline;

  /// No description provided for @postingPollNeverExpires.
  ///
  /// In zh, this message translates to:
  /// **'不限期'**
  String get postingPollNeverExpires;

  /// No description provided for @postingPollDays.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {不限期} other {{count} 天}}'**
  String postingPollDays(int count);

  /// No description provided for @postingPollPublicVoters.
  ///
  /// In zh, this message translates to:
  /// **'公开投票人'**
  String get postingPollPublicVoters;

  /// No description provided for @postingPollPublicVotersDescription.
  ///
  /// In zh, this message translates to:
  /// **'开启后所有人可看到谁投了哪一项'**
  String get postingPollPublicVotersDescription;

  /// No description provided for @postingPollShowResultsAfterVote.
  ///
  /// In zh, this message translates to:
  /// **'投票后才显示结果'**
  String get postingPollShowResultsAfterVote;

  /// No description provided for @postingAllowNoticeAuthor.
  ///
  /// In zh, this message translates to:
  /// **'允许通知作者'**
  String get postingAllowNoticeAuthor;

  /// No description provided for @postingDisableBbCode.
  ///
  /// In zh, this message translates to:
  /// **'关闭 BBCode 解析'**
  String get postingDisableBbCode;

  /// No description provided for @postingDisableSmiley.
  ///
  /// In zh, this message translates to:
  /// **'关闭表情解析'**
  String get postingDisableSmiley;

  /// No description provided for @postingDisableUrl.
  ///
  /// In zh, this message translates to:
  /// **'关闭 URL 解析'**
  String get postingDisableUrl;

  /// No description provided for @postingLeaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'保存草稿并离开？'**
  String get postingLeaveTitle;

  /// No description provided for @postingLeaveBody.
  ///
  /// In zh, this message translates to:
  /// **'当前帖子还没有发送，离开前会保存为草稿。'**
  String get postingLeaveBody;

  /// No description provided for @postingSubjectRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入标题'**
  String get postingSubjectRequired;

  /// No description provided for @postingBodyRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入正文'**
  String get postingBodyRequired;

  /// No description provided for @postingFormStillLoading.
  ///
  /// In zh, this message translates to:
  /// **'发帖表单还在加载，请稍候再试'**
  String get postingFormStillLoading;

  /// No description provided for @postingSubjectTooLong.
  ///
  /// In zh, this message translates to:
  /// **'标题超出版块上限（最多 {limit} 字符）'**
  String postingSubjectTooLong(int limit);

  /// No description provided for @postingBodyTooLong.
  ///
  /// In zh, this message translates to:
  /// **'正文超出版块上限（最多 {limit} 字符）'**
  String postingBodyTooLong(int limit);

  /// No description provided for @postingPollMissing.
  ///
  /// In zh, this message translates to:
  /// **'投票配置缺失，请添加选项'**
  String get postingPollMissing;

  /// No description provided for @postingPollTooFewOptions.
  ///
  /// In zh, this message translates to:
  /// **'投票至少需要 {limit} 个非空选项'**
  String postingPollTooFewOptions(int limit);

  /// No description provided for @postingPollOptionTooLong.
  ///
  /// In zh, this message translates to:
  /// **'单个投票选项不能超过 {limit} 字符'**
  String postingPollOptionTooLong(int limit);

  /// No description provided for @postingPollMultipleInvalid.
  ///
  /// In zh, this message translates to:
  /// **'多选投票的最大选择数至少为 {limit}'**
  String postingPollMultipleInvalid(int limit);

  /// No description provided for @postingSubmitSuccess.
  ///
  /// In zh, this message translates to:
  /// **'发布成功'**
  String get postingSubmitSuccess;

  /// No description provided for @postingSubmitSuccessWithDetail.
  ///
  /// In zh, this message translates to:
  /// **'发布成功：{detail}'**
  String postingSubmitSuccessWithDetail(String detail);

  /// No description provided for @replyThreadTitle.
  ///
  /// In zh, this message translates to:
  /// **'回复帖子'**
  String get replyThreadTitle;

  /// No description provided for @replyFloorTitle.
  ///
  /// In zh, this message translates to:
  /// **'回复楼层'**
  String get replyFloorTitle;

  /// No description provided for @replySubmit.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get replySubmit;

  /// No description provided for @replyMessageHint.
  ///
  /// In zh, this message translates to:
  /// **'输入回复内容'**
  String get replyMessageHint;

  /// No description provided for @replyPreparingQuote.
  ///
  /// In zh, this message translates to:
  /// **'正在准备楼层引用'**
  String get replyPreparingQuote;

  /// No description provided for @replyPreparationFailed.
  ///
  /// In zh, this message translates to:
  /// **'楼层回复引用准备失败：{error}'**
  String replyPreparationFailed(String error);

  /// No description provided for @replyLeaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'保存草稿并离开？'**
  String get replyLeaveTitle;

  /// No description provided for @replyLeaveBody.
  ///
  /// In zh, this message translates to:
  /// **'当前回复还没有发送，离开前会保存为草稿。'**
  String get replyLeaveBody;

  /// No description provided for @replyContentRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入回复内容'**
  String get replyContentRequired;

  /// No description provided for @replyReferenceUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'楼层回复引用准备失败，请重试'**
  String get replyReferenceUnavailable;

  /// No description provided for @replySubmitSuccess.
  ///
  /// In zh, this message translates to:
  /// **'回复成功'**
  String get replySubmitSuccess;

  /// No description provided for @replySubmitSuccessWithDetail.
  ///
  /// In zh, this message translates to:
  /// **'回复成功：{detail}'**
  String replySubmitSuccessWithDetail(String detail);

  /// No description provided for @composerPrototypeTitle.
  ///
  /// In zh, this message translates to:
  /// **'Quill Composer 原型'**
  String get composerPrototypeTitle;

  /// No description provided for @composerPrototypeSourceTitle.
  ///
  /// In zh, this message translates to:
  /// **'源码微调'**
  String get composerPrototypeSourceTitle;

  /// No description provided for @composerPrototypeAttachmentInserted.
  ///
  /// In zh, this message translates to:
  /// **'已插入测试附件 {aid}'**
  String composerPrototypeAttachmentInserted(String aid);

  /// No description provided for @composerAttachmentFallback.
  ///
  /// In zh, this message translates to:
  /// **'图片 {aid}'**
  String composerAttachmentFallback(String aid);

  /// No description provided for @composerLinkUrlHint.
  ///
  /// In zh, this message translates to:
  /// **'https://example.com'**
  String get composerLinkUrlHint;

  /// No description provided for @commonSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get commonSearch;

  /// No description provided for @commonMenu.
  ///
  /// In zh, this message translates to:
  /// **'菜单'**
  String get commonMenu;

  /// No description provided for @commonPreviousPage.
  ///
  /// In zh, this message translates to:
  /// **'上一页'**
  String get commonPreviousPage;

  /// No description provided for @commonNextPage.
  ///
  /// In zh, this message translates to:
  /// **'下一页'**
  String get commonNextPage;

  /// No description provided for @commonPage.
  ///
  /// In zh, this message translates to:
  /// **'第{page}页'**
  String commonPage(int page);

  /// No description provided for @commonPageOf.
  ///
  /// In zh, this message translates to:
  /// **'第 {page} / {total} 页'**
  String commonPageOf(int page, int total);

  /// No description provided for @commonImageLoading.
  ///
  /// In zh, this message translates to:
  /// **'图片加载中'**
  String get commonImageLoading;

  /// No description provided for @commonNetworkError.
  ///
  /// In zh, this message translates to:
  /// **'网络连接失败'**
  String get commonNetworkError;

  /// No description provided for @commonTimeoutError.
  ///
  /// In zh, this message translates to:
  /// **'请求超时'**
  String get commonTimeoutError;

  /// No description provided for @commonUnauthorizedError.
  ///
  /// In zh, this message translates to:
  /// **'登录状态已失效'**
  String get commonUnauthorizedError;

  /// No description provided for @commonServerError.
  ///
  /// In zh, this message translates to:
  /// **'服务器暂时不可用'**
  String get commonServerError;

  /// No description provided for @commonParseError.
  ///
  /// In zh, this message translates to:
  /// **'内容解析失败'**
  String get commonParseError;

  /// No description provided for @commonRequestError.
  ///
  /// In zh, this message translates to:
  /// **'请求失败'**
  String get commonRequestError;

  /// No description provided for @authLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get authLoginTitle;

  /// No description provided for @authUsername.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get authUsername;

  /// No description provided for @authUsernameHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入论坛账号'**
  String get authUsernameHint;

  /// No description provided for @authPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get authPassword;

  /// No description provided for @authLoginSuccess.
  ///
  /// In zh, this message translates to:
  /// **'登录成功'**
  String get authLoginSuccess;

  /// No description provided for @authCredentialsRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名和密码'**
  String get authCredentialsRequired;

  /// No description provided for @authLoginTimeout.
  ///
  /// In zh, this message translates to:
  /// **'登录超时，请检查网络后重试'**
  String get authLoginTimeout;

  /// No description provided for @authLoginRejected.
  ///
  /// In zh, this message translates to:
  /// **'账号或密码错误'**
  String get authLoginRejected;

  /// No description provided for @authLoginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败：{error}'**
  String authLoginFailed(String error);

  /// No description provided for @authLoginWelcome.
  ///
  /// In zh, this message translates to:
  /// **'欢迎回来，{username}'**
  String authLoginWelcome(String username);

  /// No description provided for @authWebViewVerificationFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录校验失败：{error}'**
  String authWebViewVerificationFailed(String error);

  /// No description provided for @appUpdateDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本'**
  String get appUpdateDialogTitle;

  /// No description provided for @appUpdateDialogBody.
  ///
  /// In zh, this message translates to:
  /// **'{appName} v{latestVersion} 已发布，当前版本为 v{installedVersion}'**
  String appUpdateDialogBody(
    String appName,
    String latestVersion,
    String installedVersion,
  );

  /// No description provided for @appUpdateDialogPrompt.
  ///
  /// In zh, this message translates to:
  /// **'是否立即更新？'**
  String get appUpdateDialogPrompt;

  /// No description provided for @appUpdateDialogReleaseNotes.
  ///
  /// In zh, this message translates to:
  /// **'更新说明'**
  String get appUpdateDialogReleaseNotes;

  /// No description provided for @appUpdateDialogIgnore.
  ///
  /// In zh, this message translates to:
  /// **'忽略'**
  String get appUpdateDialogIgnore;

  /// No description provided for @appUpdateDialogLater.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get appUpdateDialogLater;

  /// No description provided for @appUpdateDialogUpdate.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get appUpdateDialogUpdate;

  /// No description provided for @appUpdateCheck.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get appUpdateCheck;

  /// No description provided for @appUpdateVersionLoading.
  ///
  /// In zh, this message translates to:
  /// **'当前版本：读取中'**
  String get appUpdateVersionLoading;

  /// No description provided for @appUpdateCurrentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前版本：{version}'**
  String appUpdateCurrentVersion(String version);

  /// No description provided for @appUpdateUpToDate.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本'**
  String get appUpdateUpToDate;

  /// No description provided for @appUpdateReleaseNotesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'当前版本暂无更新日志'**
  String get appUpdateReleaseNotesEmpty;

  /// No description provided for @appUpdateReleaseNotesUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'更新日志暂不可用'**
  String get appUpdateReleaseNotesUnavailable;

  /// No description provided for @appUpdateDownloadNetworkUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'网络不可用，无法开始下载更新'**
  String get appUpdateDownloadNetworkUnavailable;

  /// No description provided for @appUpdateDownloadTimeout.
  ///
  /// In zh, this message translates to:
  /// **'更新检查超时，请稍后重试'**
  String get appUpdateDownloadTimeout;

  /// No description provided for @appUpdateDownloadInvalid.
  ///
  /// In zh, this message translates to:
  /// **'当前更新信息无效，请稍后重试'**
  String get appUpdateDownloadInvalid;

  /// No description provided for @appUpdateDownloadInProgress.
  ///
  /// In zh, this message translates to:
  /// **'更新下载正在进行中，请稍候'**
  String get appUpdateDownloadInProgress;

  /// No description provided for @appUpdateDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法开始更新下载，请稍后重试'**
  String get appUpdateDownloadFailed;

  /// No description provided for @appUpdateCheckNetworkUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'网络不可用，检查更新失败'**
  String get appUpdateCheckNetworkUnavailable;

  /// No description provided for @appUpdateCheckTimeout.
  ///
  /// In zh, this message translates to:
  /// **'检查更新超时，请稍后重试'**
  String get appUpdateCheckTimeout;

  /// No description provided for @appUpdateCheckRateLimited.
  ///
  /// In zh, this message translates to:
  /// **'检查更新过于频繁，请稍后重试'**
  String get appUpdateCheckRateLimited;

  /// No description provided for @appUpdateInstalledVersionUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法读取当前应用版本'**
  String get appUpdateInstalledVersionUnavailable;

  /// No description provided for @appUpdateCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败，请稍后重试'**
  String get appUpdateCheckFailed;

  /// No description provided for @appUpdateInvalidUrl.
  ///
  /// In zh, this message translates to:
  /// **'更新下载地址无效，请稍后重试'**
  String get appUpdateInvalidUrl;

  /// No description provided for @appUpdateBrowserUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法打开下载链接，请确认设备已安装浏览器'**
  String get appUpdateBrowserUnavailable;

  /// No description provided for @appUpdateOpenUrlFailed.
  ///
  /// In zh, this message translates to:
  /// **'打开下载链接失败，请稍后重试'**
  String get appUpdateOpenUrlFailed;

  /// No description provided for @appUpdateLaunchFailed.
  ///
  /// In zh, this message translates to:
  /// **'打开更新下载链接失败，请稍后重试'**
  String get appUpdateLaunchFailed;

  /// No description provided for @searchTitle.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get searchTitle;

  /// No description provided for @searchInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词'**
  String get searchInputHint;

  /// No description provided for @searchLoadMore.
  ///
  /// In zh, this message translates to:
  /// **'查看更多'**
  String get searchLoadMore;

  /// No description provided for @searchRetryAfter.
  ///
  /// In zh, this message translates to:
  /// **'请 {seconds} 秒后重试'**
  String searchRetryAfter(int seconds);

  /// No description provided for @searchNoResults.
  ///
  /// In zh, this message translates to:
  /// **'未找到结果'**
  String get searchNoResults;

  /// No description provided for @searchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败：{error}'**
  String searchFailed(String error);

  /// No description provided for @searchLoadMoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载更多失败：{error}'**
  String searchLoadMoreFailed(String error);

  /// No description provided for @searchForumFallback.
  ///
  /// In zh, this message translates to:
  /// **'论坛搜索'**
  String get searchForumFallback;

  /// No description provided for @searchQueueWaiting.
  ///
  /// In zh, this message translates to:
  /// **'{subject} 正在等待搜索，预计 {seconds} 秒'**
  String searchQueueWaiting(String subject, String seconds);

  /// No description provided for @searchResultTid.
  ///
  /// In zh, this message translates to:
  /// **'TID：{tid}'**
  String searchResultTid(String tid);

  /// No description provided for @tagTitleFallback.
  ///
  /// In zh, this message translates to:
  /// **'标签'**
  String get tagTitleFallback;

  /// No description provided for @tagLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'标签页加载失败：{error}'**
  String tagLoadFailed(String error);

  /// No description provided for @tagRelatedThreads.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {暂无相关帖子} other {{count} 个相关帖子}}'**
  String tagRelatedThreads(int count);

  /// No description provided for @tagReplies.
  ///
  /// In zh, this message translates to:
  /// **'回复 {count}'**
  String tagReplies(int count);

  /// No description provided for @tagViews.
  ///
  /// In zh, this message translates to:
  /// **'查看 {count}'**
  String tagViews(int count);

  /// No description provided for @tagLastPost.
  ///
  /// In zh, this message translates to:
  /// **'最后发表 {value}'**
  String tagLastPost(String value);

  /// No description provided for @tagMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get tagMore;

  /// No description provided for @tagEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无相关帖子'**
  String get tagEmpty;

  /// No description provided for @profileTitle.
  ///
  /// In zh, this message translates to:
  /// **'个人资料'**
  String get profileTitle;

  /// No description provided for @profileMyTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的资料'**
  String get profileMyTitle;

  /// 服务器未提供资料页标题时由应用生成的标题；username 保持原文
  ///
  /// In zh, this message translates to:
  /// **'{username}的资料'**
  String profileUserTitle(String username);

  /// No description provided for @profileHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get profileHome;

  /// No description provided for @profileLoginRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先登录后查看个人资料'**
  String get profileLoginRequired;

  /// No description provided for @profileMyThreads.
  ///
  /// In zh, this message translates to:
  /// **'我的主题'**
  String get profileMyThreads;

  /// No description provided for @profileMyBlogs.
  ///
  /// In zh, this message translates to:
  /// **'我的日志'**
  String get profileMyBlogs;

  /// No description provided for @profileMyFavorites.
  ///
  /// In zh, this message translates to:
  /// **'我的收藏'**
  String get profileMyFavorites;

  /// No description provided for @profileMessages.
  ///
  /// In zh, this message translates to:
  /// **'消息提醒'**
  String get profileMessages;

  /// No description provided for @profileMyFriends.
  ///
  /// In zh, this message translates to:
  /// **'我的好友'**
  String get profileMyFriends;

  /// No description provided for @profileDailyCheckIn.
  ///
  /// In zh, this message translates to:
  /// **'每日签到'**
  String get profileDailyCheckIn;

  /// No description provided for @profileTheirThreads.
  ///
  /// In zh, this message translates to:
  /// **'Ta的主题'**
  String get profileTheirThreads;

  /// No description provided for @profileTheirBlogs.
  ///
  /// In zh, this message translates to:
  /// **'Ta的日志'**
  String get profileTheirBlogs;

  /// No description provided for @profileSendMessage.
  ///
  /// In zh, this message translates to:
  /// **'发短消息'**
  String get profileSendMessage;

  /// No description provided for @profileAddFriend.
  ///
  /// In zh, this message translates to:
  /// **'加为好友'**
  String get profileAddFriend;

  /// No description provided for @profileActionUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂未接入该操作'**
  String get profileActionUnavailable;

  /// No description provided for @profileSignature.
  ///
  /// In zh, this message translates to:
  /// **'个人签名'**
  String get profileSignature;

  /// No description provided for @profileDetails.
  ///
  /// In zh, this message translates to:
  /// **'个人资料'**
  String get profileDetails;

  /// No description provided for @profileLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'资料加载失败：{error}'**
  String profileLoadFailed(String error);

  /// No description provided for @profileBlogTitle.
  ///
  /// In zh, this message translates to:
  /// **'日志'**
  String get profileBlogTitle;

  /// No description provided for @profileBlogWrite.
  ///
  /// In zh, this message translates to:
  /// **'写日志'**
  String get profileBlogWrite;

  /// No description provided for @profileBlogWriteUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'发表新日志暂未接入'**
  String get profileBlogWriteUnavailable;

  /// No description provided for @profileBlogEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有相关的日志'**
  String get profileBlogEmpty;

  /// No description provided for @profileBlogFriends.
  ///
  /// In zh, this message translates to:
  /// **'好友的日志'**
  String get profileBlogFriends;

  /// No description provided for @profileBlogMine.
  ///
  /// In zh, this message translates to:
  /// **'我的日志'**
  String get profileBlogMine;

  /// No description provided for @profileBlogExplore.
  ///
  /// In zh, this message translates to:
  /// **'随便看看'**
  String get profileBlogExplore;

  /// No description provided for @profileBlogLatest.
  ///
  /// In zh, this message translates to:
  /// **'最新发表的日志'**
  String get profileBlogLatest;

  /// No description provided for @profileBlogRecommended.
  ///
  /// In zh, this message translates to:
  /// **'推荐阅读的日志'**
  String get profileBlogRecommended;

  /// No description provided for @profileBlogComments.
  ///
  /// In zh, this message translates to:
  /// **'日志评论'**
  String get profileBlogComments;

  /// No description provided for @profileBlogCommentUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'日志评论提交暂未接入'**
  String get profileBlogCommentUnavailable;

  /// No description provided for @profileBlogComment.
  ///
  /// In zh, this message translates to:
  /// **'评论'**
  String get profileBlogComment;

  /// No description provided for @profileBlogViews.
  ///
  /// In zh, this message translates to:
  /// **'浏览 {count}'**
  String profileBlogViews(int count);

  /// No description provided for @profileBlogCommentCount.
  ///
  /// In zh, this message translates to:
  /// **'评论 {count}'**
  String profileBlogCommentCount(int count);

  /// No description provided for @profileBlogLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'日志加载失败：{error}'**
  String profileBlogLoadFailed(String error);

  /// No description provided for @profileMessageCenterTitle.
  ///
  /// In zh, this message translates to:
  /// **'消息提醒'**
  String get profileMessageCenterTitle;

  /// No description provided for @profileNotificationsTab.
  ///
  /// In zh, this message translates to:
  /// **'提醒 {count}'**
  String profileNotificationsTab(int count);

  /// No description provided for @profileMessagesTab.
  ///
  /// In zh, this message translates to:
  /// **'消息 {count}'**
  String profileMessagesTab(int count);

  /// No description provided for @profileNoNotifications.
  ///
  /// In zh, this message translates to:
  /// **'暂无提醒'**
  String get profileNoNotifications;

  /// No description provided for @profileSystemNotification.
  ///
  /// In zh, this message translates to:
  /// **'系统提醒'**
  String get profileSystemNotification;

  /// No description provided for @profileNoMessages.
  ///
  /// In zh, this message translates to:
  /// **'暂无消息'**
  String get profileNoMessages;

  /// No description provided for @profilePrivateMessage.
  ///
  /// In zh, this message translates to:
  /// **'私信'**
  String get profilePrivateMessage;

  /// No description provided for @profileMessageTo.
  ///
  /// In zh, this message translates to:
  /// **'发给 {name}'**
  String profileMessageTo(String name);

  /// No description provided for @profileNewBadge.
  ///
  /// In zh, this message translates to:
  /// **'新'**
  String get profileNewBadge;

  /// No description provided for @profileMessagesLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'消息加载失败：{error}'**
  String profileMessagesLoadFailed(String error);

  /// No description provided for @threadPrototypeTitle.
  ///
  /// In zh, this message translates to:
  /// **'HTML 正文渲染原型'**
  String get threadPrototypeTitle;

  /// No description provided for @threadPrototypeLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'样例加载失败：{error}'**
  String threadPrototypeLoadFailed(String error);

  /// No description provided for @threadPrototypeEmptyResult.
  ///
  /// In zh, this message translates to:
  /// **'样例加载失败：结果为空'**
  String get threadPrototypeEmptyResult;

  /// No description provided for @threadPrototypeMissingAsset.
  ///
  /// In zh, this message translates to:
  /// **'本地样例未找到，请从 {sourcePath} 复制到 {assetPath}'**
  String threadPrototypeMissingAsset(String sourcePath, String assetPath);

  /// No description provided for @threadPrototypeLink.
  ///
  /// In zh, this message translates to:
  /// **'链接：{url}'**
  String threadPrototypeLink(String url);

  /// No description provided for @threadPrototypeThemeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get threadPrototypeThemeLight;

  /// No description provided for @threadPrototypeThemeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get threadPrototypeThemeDark;

  /// No description provided for @threadPrototypeJitterCopied.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {未复制抖动日志} other {已复制 {count} 条抖动日志}}'**
  String threadPrototypeJitterCopied(int count);

  /// No description provided for @threadPrototypeImageOpened.
  ///
  /// In zh, this message translates to:
  /// **'{postNumber}# 图片：{index}'**
  String threadPrototypeImageOpened(int postNumber, int index);

  /// No description provided for @threadPrototypeActionUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'原型页暂不执行该帖子操作'**
  String get threadPrototypeActionUnsupported;

  /// No description provided for @threadPrototypeJitterTitle.
  ///
  /// In zh, this message translates to:
  /// **'记录抖动日志'**
  String get threadPrototypeJitterTitle;

  /// No description provided for @threadPrototypeJitterRecording.
  ///
  /// In zh, this message translates to:
  /// **'记录中，关闭后复制日志'**
  String get threadPrototypeJitterRecording;

  /// No description provided for @threadPrototypeJitterCount.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {尚未记录} other {已记录 {count} 条}}'**
  String threadPrototypeJitterCount(int count);

  /// No description provided for @threadPrototypeCopyLog.
  ///
  /// In zh, this message translates to:
  /// **'复制日志'**
  String get threadPrototypeCopyLog;

  /// No description provided for @threadPrototypeThreadSummarySemantics.
  ///
  /// In zh, this message translates to:
  /// **'HTML 原型帖子样例摘要'**
  String get threadPrototypeThreadSummarySemantics;

  /// No description provided for @threadPrototypeSummarySemantics.
  ///
  /// In zh, this message translates to:
  /// **'HTML 原型样例摘要'**
  String get threadPrototypeSummarySemantics;

  /// No description provided for @threadPrototypeSample.
  ///
  /// In zh, this message translates to:
  /// **'样例：{sample}'**
  String threadPrototypeSample(String sample);

  /// No description provided for @threadPrototypeThread.
  ///
  /// In zh, this message translates to:
  /// **'帖子：{subject}'**
  String threadPrototypeThread(String subject);

  /// No description provided for @threadPrototypePage.
  ///
  /// In zh, this message translates to:
  /// **'页码：{page}/{total}'**
  String threadPrototypePage(int page, String total);

  /// No description provided for @threadPrototypePosts.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {楼层：0 个} other {楼层：{count} 个}}'**
  String threadPrototypePosts(int count);

  /// No description provided for @threadPrototypeConversionMode.
  ///
  /// In zh, this message translates to:
  /// **'转换模式：{mode}'**
  String threadPrototypeConversionMode(String mode);

  /// No description provided for @threadPrototypeConverter.
  ///
  /// In zh, this message translates to:
  /// **'转换器：{converterId}'**
  String threadPrototypeConverter(String converterId);

  /// No description provided for @threadPrototypeConvertedNodes.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {转换文本节点：0 个} other {转换文本节点：{count} 个}}'**
  String threadPrototypeConvertedNodes(int count);

  /// No description provided for @threadPrototypePreviewTheme.
  ///
  /// In zh, this message translates to:
  /// **'预览主题：{theme}'**
  String threadPrototypePreviewTheme(String theme);

  /// No description provided for @threadPrototypeTypography.
  ///
  /// In zh, this message translates to:
  /// **'字号 {fontScale}% / 间隔 {lineHeight}×'**
  String threadPrototypeTypography(int fontScale, String lineHeight);

  /// No description provided for @threadPrototypeThemeAdaptation.
  ///
  /// In zh, this message translates to:
  /// **'{authorFontMode, select, preserved {主题适配：始终启用 / 作者字号保留} unified {主题适配：始终启用 / 作者字号统一} other {主题适配：始终启用}}'**
  String threadPrototypeThemeAdaptation(String authorFontMode);

  /// No description provided for @threadPrototypeRawHtmlLength.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {原 HTML：0 字符} other {原 HTML：{count} 字符}}'**
  String threadPrototypeRawHtmlLength(int count);

  /// No description provided for @threadPrototypeFragmentLength.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {正文 fragment：0 字符} other {正文 fragment：{count} 字符}}'**
  String threadPrototypeFragmentLength(int count);

  /// No description provided for @threadPrototypeAdaptedColors.
  ///
  /// In zh, this message translates to:
  /// **'适配前景：{remappedForeground}/{explicitForeground} · 适配背景：{remappedBackground}/{explicitBackground}'**
  String threadPrototypeAdaptedColors(
    int remappedForeground,
    int explicitForeground,
    int remappedBackground,
    int explicitBackground,
  );

  /// No description provided for @threadPrototypeAdaptationFallbacks.
  ///
  /// In zh, this message translates to:
  /// **'语义回退：{semanticFallback} · 不支持：{unsupported} · 隐藏：{concealed}'**
  String threadPrototypeAdaptationFallbacks(
    int semanticFallback,
    int unsupported,
    int concealed,
  );

  /// No description provided for @threadPrototypeMinimumContrast.
  ///
  /// In zh, this message translates to:
  /// **'最低可见对比度：{value}'**
  String threadPrototypeMinimumContrast(String value);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
