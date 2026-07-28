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
  String startupSelectionSelectedCount(int count);

  /// No description provided for @startupSelectionExit.
  ///
  /// In zh, this message translates to:
  /// **'退出多选'**
  String get startupSelectionExit;

  /// No description provided for @startupSelectionSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选当前分类'**
  String get startupSelectionSelectAll;

  /// No description provided for @startupSelectionInvert.
  ///
  /// In zh, this message translates to:
  /// **'反选当前分类'**
  String get startupSelectionInvert;

  /// No description provided for @startupSelectionActionAssignCategory.
  ///
  /// In zh, this message translates to:
  /// **'设置分类'**
  String get startupSelectionActionAssignCategory;

  /// No description provided for @startupSelectionActionMarkAllRead.
  ///
  /// In zh, this message translates to:
  /// **'全部已读'**
  String get startupSelectionActionMarkAllRead;

  /// No description provided for @startupSelectionActionMarkAllUnread.
  ///
  /// In zh, this message translates to:
  /// **'全部未读'**
  String get startupSelectionActionMarkAllUnread;

  /// No description provided for @startupSelectionActionDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get startupSelectionActionDownload;

  /// No description provided for @startupSelectionActionUnfavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get startupSelectionActionUnfavorite;

  /// No description provided for @startupSelectionActionGeneric.
  ///
  /// In zh, this message translates to:
  /// **'执行操作'**
  String get startupSelectionActionGeneric;

  /// 批量操作异常提示；error 是经过清理的安全错误摘要
  ///
  /// In zh, this message translates to:
  /// **'批量操作失败：{error}'**
  String startupBatchActionFailed(String error);

  /// No description provided for @startupConfirmUnfavoriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认取消收藏'**
  String get startupConfirmUnfavoriteTitle;

  /// No description provided for @startupConfirmActionTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认执行操作'**
  String get startupConfirmActionTitle;

  /// 取消收藏确认正文；count 是选中项目数量
  ///
  /// In zh, this message translates to:
  /// **'将取消已选 {count, plural, =0 {0 项} other {{count} 项}}收藏。若作品已无其它活跃收藏来源，相关本地作品、章节、封面缓存和下载也会被清除。是否继续？'**
  String startupConfirmUnfavoriteBody(int count);

  /// 普通多选动作确认正文；action 是由稳定 action id 映射的本地化名称
  ///
  /// In zh, this message translates to:
  /// **'将对已选 {count, plural, =0 {0 项} other {{count} 项}}执行“{action}”，是否继续？'**
  String startupConfirmActionBody(int count, String action);

  /// No description provided for @startupSelectCategory.
  ///
  /// In zh, this message translates to:
  /// **'选择分类'**
  String get startupSelectCategory;

  /// No description provided for @startupCreateCategory.
  ///
  /// In zh, this message translates to:
  /// **'新建分类'**
  String get startupCreateCategory;

  /// No description provided for @startupCategoryNameHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入分类名称'**
  String get startupCategoryNameHint;

  /// 批量设置分类成功提示；count 是成功处理的项目数量
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0 {没有项目设置分类} other {已为 {count} 项设置分类}}'**
  String startupSelectionCategoryAssigned(int count);

  /// 批量设置分类部分失败提示
  ///
  /// In zh, this message translates to:
  /// **'{succeededCount, plural, =0 {没有项目设置分类} other {已为 {succeededCount} 项设置分类}}；{failedCount, plural, =0 {没有失败项目} other {失败 {failedCount} 项}}'**
  String startupSelectionCategoryAssignedPartial(
    int succeededCount,
    int failedCount,
  );

  /// 批量阅读状态修改成功提示；state 是已读或未读的本地化名称
  ///
  /// In zh, this message translates to:
  /// **'已将 {count, plural, =0 {0 项} other {{count} 项}}标记为{state}'**
  String startupSelectionReadStateChanged(int count, String state);

  /// 批量阅读状态修改部分失败提示
  ///
  /// In zh, this message translates to:
  /// **'已将 {succeededCount, plural, =0 {0 项} other {{succeededCount} 项}}标记为{state}；{failedCount, plural, =0 {没有失败项目} other {失败 {failedCount} 项}}'**
  String startupSelectionReadStateChangedPartial(
    int succeededCount,
    int failedCount,
    String state,
  );

  /// No description provided for @startupSelectionRead.
  ///
  /// In zh, this message translates to:
  /// **'已读'**
  String get startupSelectionRead;

  /// No description provided for @startupSelectionUnread.
  ///
  /// In zh, this message translates to:
  /// **'未读'**
  String get startupSelectionUnread;

  /// 批量下载入队提示；count 是新加入队列的章节数量
  ///
  /// In zh, this message translates to:
  /// **'已将 {count, plural, =0 {0 个章节} other {{count} 个章节}}加入下载队列'**
  String startupSelectionDownloadQueued(int count);

  /// 批量下载入队部分失败提示
  ///
  /// In zh, this message translates to:
  /// **'已将 {count, plural, =0 {0 个章节} other {{count} 个章节}}加入下载队列；{failedCount, plural, =0 {没有失败项目} other {失败 {failedCount} 项}}'**
  String startupSelectionDownloadQueuedPartial(int count, int failedCount);

  /// No description provided for @startupSelectionDownloadAlreadyQueued.
  ///
  /// In zh, this message translates to:
  /// **'所选章节已在下载队列中'**
  String get startupSelectionDownloadAlreadyQueued;

  /// No description provided for @startupSelectionNothingToDownload.
  ///
  /// In zh, this message translates to:
  /// **'没有需要下载的章节'**
  String get startupSelectionNothingToDownload;

  /// 批量取消收藏成功提示；count 是成功取消的项目数量
  ///
  /// In zh, this message translates to:
  /// **'已取消 {count, plural, =0 {0 项} other {{count} 项}}收藏'**
  String startupSelectionUnfavorite(int count);

  /// 批量取消收藏部分失败提示
  ///
  /// In zh, this message translates to:
  /// **'已取消 {succeededCount, plural, =0 {0 项} other {{succeededCount} 项}}收藏；{failedCount, plural, =0 {没有失败项目} other {失败 {failedCount} 项}}'**
  String startupSelectionUnfavoritePartial(int succeededCount, int failedCount);

  /// 当前书架不支持某个批量动作；action 是本地化动作名称
  ///
  /// In zh, this message translates to:
  /// **'当前不支持批量{action}'**
  String startupSelectionUnsupported(String action);

  /// No description provided for @startupSelectionMissingTargetCategory.
  ///
  /// In zh, this message translates to:
  /// **'请选择目标分类'**
  String get startupSelectionMissingTargetCategory;

  /// No description provided for @startupSelectionNoValidItems.
  ///
  /// In zh, this message translates to:
  /// **'没有可处理的项目'**
  String get startupSelectionNoValidItems;

  /// 批量动作没有产生变化；action 是本地化动作名称
  ///
  /// In zh, this message translates to:
  /// **'没有可执行的{action}'**
  String startupSelectionNoChange(String action);

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
