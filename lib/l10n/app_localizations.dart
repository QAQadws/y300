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
