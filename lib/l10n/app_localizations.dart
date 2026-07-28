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
