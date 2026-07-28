// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appLanguageSectionTitle => '界面语言';

  @override
  String get appLanguageSystem => '跟随系统';

  @override
  String get appLanguageSimplifiedChinese => '简体中文';

  @override
  String get appLanguageTraditionalChinese => '繁体中文';

  @override
  String appLanguageSaveFailed(String error) {
    return '语言设置保存失败：$error';
  }

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确定';

  @override
  String get commonClose => '关闭';

  @override
  String get commonClear => '清空';

  @override
  String get commonRetry => '重试';

  @override
  String get commonUnknownError => '未知错误';

  @override
  String get forumHomeTitle => '论坛首页';

  @override
  String get forumHomeSearch => '搜索论坛';

  @override
  String get forumHomeRefresh => '刷新论坛首页';

  @override
  String get forumHomeEmpty => '暂无论坛版块';

  @override
  String forumHomeLoadFailed(String error) {
    return '论坛首页加载失败：$error';
  }

  @override
  String forumHomeRefreshFailed(String error) {
    return '刷新论坛首页失败：$error';
  }

  @override
  String get forumHomeFavoriteForums => '我收藏的版块';

  @override
  String get forumHomeUncategorized => '未分类';

  @override
  String get forumDisplayTitle => '帖子列表';

  @override
  String get forumDisplaySearch => '搜索本版';

  @override
  String get forumDisplayCreateThread => '发帖';

  @override
  String get forumDisplayToday => '今日';

  @override
  String get forumDisplayThreads => '主题';

  @override
  String get forumDisplayRank => '排名';

  @override
  String get forumDisplaySubForum => '子版块';

  @override
  String get forumDisplayAnnouncements => '公告';

  @override
  String get forumDisplayPinned => '置顶';

  @override
  String get forumDisplayAnonymous => '匿名';

  @override
  String get forumDisplayPreviousPage => '上一页';

  @override
  String get forumDisplayNextPage => '下一页';

  @override
  String get forumDisplayNoMore => '没有更多';

  @override
  String forumDisplayPage(int page) {
    return '第$page页';
  }

  @override
  String get forumDisplayEmpty => '暂无帖子';

  @override
  String forumDisplayLoadFailed(String error) {
    return '帖子列表加载失败：$error';
  }

  @override
  String get forumDisplayCopiedLink => '已复制帖子链接';

  @override
  String get forumShellNative => '解析模式';

  @override
  String get forumShellWebView => 'WebView 模式';

  @override
  String get forumWebViewLoading => '正在加载论坛页面';

  @override
  String forumWebViewLoadFailed(String error) {
    return '论坛页面加载失败：$error';
  }

  @override
  String get forumWebViewRetry => '重试加载';

  @override
  String get forumWebViewOpenExternal => '在外部打开';

  @override
  String get forumWebViewOpenExternalFailed => '打开外部链接失败';

  @override
  String get forumWebViewClose => '关闭论坛页面';

  @override
  String get forumWebViewReplyThread => '回复帖子';

  @override
  String get forumWebViewRefresh => '刷新页面';

  @override
  String get forumWebViewBackHome => '返回首页';

  @override
  String get forumWebViewFeatureInProgress => '功能开发中';

  @override
  String get forumWebViewProcessing => '处理中';

  @override
  String get forumWebViewFavoriteForum => '收藏本版';

  @override
  String get forumWebViewUnfavoriteForum => '取消收藏';

  @override
  String get forumWebViewCancelFavorite => '取消收藏';

  @override
  String get forumWebViewFavoriteSuccess => '已收藏本版';

  @override
  String get forumWebViewUnfavoriteSuccess => '已取消收藏本版';

  @override
  String forumWebViewActionFailed(String error) {
    return '操作失败，请稍后重试：$error';
  }

  @override
  String get forumWebViewFavoriteForumsTitle => '取消收藏';

  @override
  String forumWebViewFavoriteForumsLoadFailed(String error) {
    return '加载收藏版块失败：$error';
  }

  @override
  String get forumWebViewNoFavoriteForums => '暂无收藏版块';

  @override
  String get forumWebViewAuthorOnly => '只看楼主';

  @override
  String get forumWebViewAllPosts => '看全部';

  @override
  String get forumWebViewNormalOrder => '正序浏览';

  @override
  String get forumWebViewReverseOrder => '倒序浏览';

  @override
  String get forumWebViewLocationFallback => '楼层定位失败，已打开帖子';

  @override
  String get forumWebViewPostLinkFallback => '帖子链接解析失败，已在网页中打开';

  @override
  String get forumWebViewReplySuccess => '回复成功';

  @override
  String get forumWebViewPostSuccess => '发布成功';

  @override
  String forumWebViewForumSearch(String board) {
    return '$board搜索';
  }

  @override
  String get forumWebViewSearchForum => '论坛搜索';

  @override
  String forumWebViewForumByFid(String fid) {
    return 'fid=$fid';
  }

  @override
  String get historyTitle => '记录';

  @override
  String get historySearchHint => '搜索记录';

  @override
  String get historySearchOpen => '搜索记录';

  @override
  String get historySearchClose => '退出搜索';

  @override
  String get historySearchClear => '清除搜索';

  @override
  String get historyClearAll => '清空记录';

  @override
  String get historyDelete => '删除记录';

  @override
  String get historyOpenSourceThread => '打开原帖';

  @override
  String get historyOpenFailed => '打开失败，请稍后重试';

  @override
  String historyOpenFailedDetail(String error) {
    return '打开失败：$error';
  }

  @override
  String get historyDeleteFailed => '删除记录失败';

  @override
  String get historyClearAllFailed => '清空记录失败';

  @override
  String get historyClearAllTitle => '清空全部记录';

  @override
  String get historyClearAllBody => '浏览记录将被清空，但不会删除收藏、书架作品或下载内容。';

  @override
  String get historyNoResults => '没有搜索结果';

  @override
  String get historyEmpty => '还没有浏览记录';

  @override
  String get historyLoadFailed => '记录加载失败';

  @override
  String get historyLoadMoreFailed => '加载失败，点击重试';

  @override
  String get historyTypeThread => '帖子';

  @override
  String get historyTypeComic => '漫画';

  @override
  String get historyTypeNovel => '小说';

  @override
  String get historySourceThread => '来源原帖';

  @override
  String get historyToday => '今天';

  @override
  String historyDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days 天前',
      one: '1 天前',
    );
    return '$_temp0';
  }

  @override
  String get historyTargetInvalid => '记录目标无效';

  @override
  String get historyPageClosed => '当前页面已关闭';

  @override
  String get historyThreadExpired => '帖子记录已失效';

  @override
  String historyWorkUnavailable(String type) {
    return '该$type作品已从本地移除';
  }

  @override
  String get historyNativeUnavailable => '当前无法打开原生页面';

  @override
  String get historyLoginRequired => '请先登录后再打开此记录';

  @override
  String get appNavigationForum => '论坛';

  @override
  String get appNavigationFavorites => '收藏';

  @override
  String get appNavigationComic => '漫画';

  @override
  String get appNavigationNovel => '小说';

  @override
  String get appNavigationHistory => '记录';

  @override
  String get appNavigationMore => '更多';

  @override
  String startupSelectionSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选 $count 项',
      zero: '未选择项目',
    );
    return '$_temp0';
  }

  @override
  String get startupSelectionExit => '退出多选';

  @override
  String get startupSelectionSelectAll => '全选当前分类';

  @override
  String get startupSelectionInvert => '反选当前分类';

  @override
  String get startupSelectionActionAssignCategory => '设置分类';

  @override
  String get startupSelectionActionMarkAllRead => '全部已读';

  @override
  String get startupSelectionActionMarkAllUnread => '全部未读';

  @override
  String get startupSelectionActionDownload => '下载';

  @override
  String get startupSelectionActionUnfavorite => '取消收藏';

  @override
  String get startupSelectionActionGeneric => '执行操作';

  @override
  String startupBatchActionFailed(String error) {
    return '批量操作失败：$error';
  }

  @override
  String get startupConfirmUnfavoriteTitle => '确认取消收藏';

  @override
  String get startupConfirmActionTitle => '确认执行操作';

  @override
  String startupConfirmUnfavoriteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      zero: '0 项',
    );
    return '将取消已选 $_temp0收藏。若作品已无其它活跃收藏来源，相关本地作品、章节、封面缓存和下载也会被清除。是否继续？';
  }

  @override
  String startupConfirmActionBody(int count, String action) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      zero: '0 项',
    );
    return '将对已选 $_temp0执行“$action”，是否继续？';
  }

  @override
  String get startupSelectCategory => '选择分类';

  @override
  String get startupCreateCategory => '新建分类';

  @override
  String get startupCategoryNameHint => '请输入分类名称';

  @override
  String startupSelectionCategoryAssigned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已为 $count 项设置分类',
      zero: '没有项目设置分类',
    );
    return '$_temp0';
  }

  @override
  String startupSelectionCategoryAssignedPartial(
    int succeededCount,
    int failedCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      succeededCount,
      locale: localeName,
      other: '已为 $succeededCount 项设置分类',
      zero: '没有项目设置分类',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failedCount,
      locale: localeName,
      other: '失败 $failedCount 项',
      zero: '没有失败项目',
    );
    return '$_temp0；$_temp1';
  }

  @override
  String startupSelectionReadStateChanged(int count, String state) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      zero: '0 项',
    );
    return '已将 $_temp0标记为$state';
  }

  @override
  String startupSelectionReadStateChangedPartial(
    int succeededCount,
    int failedCount,
    String state,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      succeededCount,
      locale: localeName,
      other: '$succeededCount 项',
      zero: '0 项',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failedCount,
      locale: localeName,
      other: '失败 $failedCount 项',
      zero: '没有失败项目',
    );
    return '已将 $_temp0标记为$state；$_temp1';
  }

  @override
  String get startupSelectionRead => '已读';

  @override
  String get startupSelectionUnread => '未读';

  @override
  String startupSelectionDownloadQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个章节',
      zero: '0 个章节',
    );
    return '已将 $_temp0加入下载队列';
  }

  @override
  String startupSelectionDownloadQueuedPartial(int count, int failedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个章节',
      zero: '0 个章节',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failedCount,
      locale: localeName,
      other: '失败 $failedCount 项',
      zero: '没有失败项目',
    );
    return '已将 $_temp0加入下载队列；$_temp1';
  }

  @override
  String get startupSelectionDownloadAlreadyQueued => '所选章节已在下载队列中';

  @override
  String get startupSelectionNothingToDownload => '没有需要下载的章节';

  @override
  String startupSelectionUnfavorite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      zero: '0 项',
    );
    return '已取消 $_temp0收藏';
  }

  @override
  String startupSelectionUnfavoritePartial(
    int succeededCount,
    int failedCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      succeededCount,
      locale: localeName,
      other: '$succeededCount 项',
      zero: '0 项',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failedCount,
      locale: localeName,
      other: '失败 $failedCount 项',
      zero: '没有失败项目',
    );
    return '已取消 $_temp0收藏；$_temp1';
  }

  @override
  String startupSelectionUnsupported(String action) {
    return '当前不支持批量$action';
  }

  @override
  String get startupSelectionMissingTargetCategory => '请选择目标分类';

  @override
  String get startupSelectionNoValidItems => '没有可处理的项目';

  @override
  String startupSelectionNoChange(String action) {
    return '没有可执行的$action';
  }

  @override
  String get moreTitle => '更多';

  @override
  String get moreMyProfile => '我的资料';

  @override
  String get moreMyProfileSignedOutSubtitle => '登录后查看个人资料、消息提醒';

  @override
  String moreMyProfileSubtitle(String username) {
    return '$username 的资料与消息提醒';
  }

  @override
  String get moreLogin => '登录';

  @override
  String get moreLoginSubtitle => '登录论坛账号并同步登录状态';

  @override
  String get moreLogout => '退出登录';

  @override
  String get moreLogoutSubtitle => '退出当前论坛账号';

  @override
  String moreLogoutSubtitleUsername(String username) {
    return '当前账号：$username';
  }

  @override
  String get moreLogoutConfirmTitle => '退出登录';

  @override
  String get moreLogoutConfirmBody => '退出后会清除本地论坛登录状态。';

  @override
  String get moreLogoutSuccess => '已退出登录';

  @override
  String moreLogoutFailed(String error) {
    return '退出登录失败：$error';
  }

  @override
  String get moreForumDisplayMode => '论坛显示模式';

  @override
  String moreForumCurrentMode(String mode) {
    return '当前：$mode';
  }

  @override
  String get moreForumModeWebView => 'WebView 模式';

  @override
  String get moreForumModeNative => '解析模式';

  @override
  String moreForumModeSwitchFailed(String error) {
    return '论坛显示模式切换失败：$error';
  }

  @override
  String get moreAppearance => '外观与文字';

  @override
  String moreCurrentTheme(String theme) {
    return '当前：$theme';
  }

  @override
  String get moreThemeSectionTitle => '主题';

  @override
  String get moreThemeLight => '浅色';

  @override
  String get moreThemeDark => '深色';

  @override
  String get moreThemeSystem => '跟随系统';

  @override
  String get moreThemeDescriptionLight => '保持浅色外观';

  @override
  String get moreThemeDescriptionDark => '使用深色外观';

  @override
  String get moreThemeDescriptionSystem => '跟随系统浅色或深色设置';

  @override
  String moreThemeSaveFailed(String error) {
    return '主题设置保存失败：$error';
  }

  @override
  String get moreNavigationManagement => '导航栏管理';

  @override
  String moreVisibleNavigationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      zero: '0 项',
    );
    return '已显示 $_temp0';
  }

  @override
  String get moreNavigationRestoreDefault => '恢复默认';

  @override
  String get moreNavigationRetry => '重试';

  @override
  String get moreNavigationDragToReorder => '拖动排序';

  @override
  String get moreNavigationMinimumOneRequired => '至少保留一个导航项';

  @override
  String get moreNavigationSaveFailed => '导航栏设置保存失败';

  @override
  String get moreDataAndStorage => '数据与存储';

  @override
  String get moreDataAndStorageSubtitle => '管理图片缓存与下载位置';

  @override
  String get moreDownloadQueue => '下载队列';

  @override
  String get moreDownloadParsingImages => '正在解析图片';

  @override
  String moreDownloadActiveProgress(
    String comicTitle,
    String episodeTitle,
    String progress,
    int waitingCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      waitingCount,
      locale: localeName,
      other: ' · 等待 $waitingCount',
      zero: '',
    );
    return '正在下载《$comicTitle》 $episodeTitle · $progress$_temp0';
  }

  @override
  String moreDownloadWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个任务',
      zero: '0 个任务',
    );
    return '等待下载 · $_temp0';
  }

  @override
  String moreDownloadFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个任务下载失败',
      zero: '0 个任务下载失败',
    );
    return '$_temp0';
  }

  @override
  String get moreDownloadEmpty => '暂无下载任务';

  @override
  String get moreAbout => '关于';

  @override
  String get moreAboutSubtitle => '应用信息';

  @override
  String moreAboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String moreAboutVersionWithBuild(String version, String buildNumber) {
    return '版本 $version ($buildNumber)';
  }

  @override
  String get moreAboutVersionLoading => '版本读取中';

  @override
  String get moreAboutVersionSection => '版本';

  @override
  String get moreAboutReleaseNotes => '更新日志';

  @override
  String get moreAboutProjectSection => '项目';

  @override
  String get moreAboutGitHub => 'GitHub 仓库';

  @override
  String get moreAboutOpenGitHubFailed => '无法打开 GitHub 仓库';

  @override
  String get moreDebugQuillComposer => 'Quill Composer 原型';

  @override
  String get moreDebugQuillComposerSubtitle => '验证所见即所得的 Discuz BBCode 转换';

  @override
  String get moreDebugHtmlRenderer => 'HTML 正文渲染原型';

  @override
  String get moreDebugHtmlRendererSubtitle => '验证复杂正文 HTML 的原生渲染';

  @override
  String get moreStorageTitle => '数据与存储';

  @override
  String moreStorageLoadFailed(String error) {
    return '加载数据与存储设置失败：$error';
  }

  @override
  String get moreStorageClearCache => '清理缓存';

  @override
  String get moreStorageClear => '清理';

  @override
  String get moreStorageCacheDescription =>
      '清理 HTML、解析快照与常规图片缓存；长期缓存、封面、下载和用户数据会保留。';

  @override
  String get moreStorageLocation => '存储位置';

  @override
  String get moreStorageDefaultLocation => '默认位置';

  @override
  String get moreStorageCustomLocation => '自定义位置';

  @override
  String get moreStorageChooseDirectory => '选择自定义目录';

  @override
  String get moreStorageRestoreDefault => '恢复默认';

  @override
  String moreStorageMaximumCache(String size) {
    return '最大缓存：$size';
  }

  @override
  String get moreStorageNoticeCachePartiallyCleared => '部分缓存清理失败，请稍后重试';

  @override
  String get moreStorageNoticeCacheCleared => '已清理常规缓存，长期缓存、下载与用户数据已保留';

  @override
  String get moreStorageNoticeCacheLimitUpdated => '最大缓存已更新';

  @override
  String get moreStorageNoticeDirectoryNotSelected => '未选择目录';

  @override
  String get moreStorageNoticeLocationUpdated => '存储位置已更新';

  @override
  String get moreStorageNoticeDefaultRestored => '已恢复默认存储位置';

  @override
  String get moreStorageNoticeUsageReloaded => '存储统计已刷新';

  @override
  String moreStorageNoticeDiagnosticsExported(String path) {
    return '缓存诊断已导出：$path';
  }

  @override
  String get moreStorageUsageOverview => '缓存与数据总览';

  @override
  String moreStorageUsageTotal(String size) {
    return '应用数据总计：$size';
  }

  @override
  String get moreStorageReloadUsage => '重新统计';

  @override
  String get moreStorageExportDiagnostics => '缓存诊断导出';

  @override
  String get moreStorageBucketImageCache => '图片缓存';

  @override
  String get moreStorageBucketPageCache => '页面缓存';

  @override
  String get moreStorageBucketLibraryMetadata => '书架数据';

  @override
  String get moreStorageBucketHistory => '浏览记录';

  @override
  String get moreStorageBucketComposerDraft => '草稿';

  @override
  String get moreStorageBucketDownload => '下载内容';

  @override
  String get moreStorageBucketAppSettings => '应用设置';

  @override
  String get moreStorageCategoryClearable => '可清缓存';

  @override
  String get moreStorageCategorySticky => '长期缓存';

  @override
  String get moreStorageCategoryProtected => '受保护/下载内容';

  @override
  String moreStorageImageRole(String role, String qualifier) {
    return '$role$qualifier';
  }

  @override
  String get moreStorageImageQualifierRecentReader => '（最近阅读）';

  @override
  String get moreStorageImageQualifierSticky => '（低淘汰）';

  @override
  String get moreStorageImageQualifierProtected => '（受保护）';

  @override
  String get moreStorageImageQualifierDownloaded => '（已下载）';

  @override
  String get moreStorageImageCover => '封面';

  @override
  String get moreStorageImageCustomCover => '自定义封面';

  @override
  String get moreStorageImageComicPage => '漫画页';

  @override
  String get moreStorageImageNovelInline => '小说正文图';

  @override
  String get moreStorageImageThreadInline => '帖子图片';

  @override
  String get moreStorageImageThreadAttachment => '帖子附件图';

  @override
  String get moreStorageImageAvatar => '头像';

  @override
  String get moreStorageImageRemoteSmiley => '表情图片';

  @override
  String get moreStorageImageForumHead => '论坛头图';

  @override
  String get moreStorageImageForumIcon => '论坛图标';

  @override
  String get moreStorageImageBlogInline => '日志图片';

  @override
  String get moreStorageImageUnknown => '未分类图片';

  @override
  String get moreStorageDocumentForum => '论坛首页';

  @override
  String get moreStorageDocumentForumDisplay => '帖子列表';

  @override
  String get moreStorageDocumentThread => '帖子详情';

  @override
  String get moreStorageDocumentTag => '标签页';

  @override
  String get moreStorageDocumentProfile => '个人资料';

  @override
  String get moreStorageDocumentBlog => '日志';

  @override
  String get moreStorageDocumentUnknown => '页面';

  @override
  String moreStorageDocumentHtml(String owner, int count) {
    return '$owner HTML（$count）';
  }

  @override
  String moreStorageSnapshot(String snapshotType, int count) {
    return '$snapshotType快照（$count）';
  }

  @override
  String get moreStorageSnapshotForumHome => '论坛首页';

  @override
  String get moreStorageSnapshotForumDisplay => '帖子列表';

  @override
  String get moreStorageSnapshotThreadDetail => '帖子详情';

  @override
  String get moreStorageSnapshotUnknown => '页面解析';

  @override
  String moreStorageComposerDraft(int count) {
    return '发帖/回复草稿（$count）';
  }

  @override
  String get moreStorageDownloadComics => '漫画下载';

  @override
  String get moreStorageDownloadNovels => '小说下载';

  @override
  String get moreStorageDownloadFavorites => '收藏快照';

  @override
  String get moreStorageDatabase => '本地数据库';

  @override
  String moreStorageLibraryCount(String kind, int count) {
    return '$kind：$count';
  }

  @override
  String get moreStorageLibraryComics => '漫画作品';

  @override
  String get moreStorageLibraryComicEpisodes => '漫画章节';

  @override
  String get moreStorageLibraryNovels => '小说作品';

  @override
  String get moreStorageLibraryNovelEpisodes => '小说章节';

  @override
  String get moreStorageLibraryFavorites => '收藏帖子';

  @override
  String get moreStorageLibraryWorkState => '作品状态';

  @override
  String get moreStorageLibraryEpisodeState => '章节状态';

  @override
  String get moreStorageHistoryDatabase => '记录数据库';

  @override
  String moreStorageHistoryEntries(int count) {
    return '浏览记录：$count';
  }

  @override
  String get threadDetailTitle => '帖子详情';

  @override
  String get threadDetailRefresh => '刷新帖子详情';

  @override
  String get threadDetailOnlyAuthor => '只看该作者';

  @override
  String get threadDetailAllPosts => '显示全部楼层';

  @override
  String get threadDetailReverseOrder => '倒序浏览';

  @override
  String get threadDetailNormalOrder => '正序浏览';

  @override
  String get threadDetailPreviousPage => '上一页';

  @override
  String get threadDetailNextPage => '下一页';

  @override
  String get threadDetailNoMore => '没有更多';

  @override
  String threadDetailPage(int page) {
    return '第$page页';
  }

  @override
  String get threadDetailReply => '回复';

  @override
  String get threadDetailReplyPost => '回复帖子';

  @override
  String get threadDetailEdit => '编辑';

  @override
  String get threadDetailShare => '分享';

  @override
  String get threadDetailCopyLink => '复制链接';

  @override
  String get threadDetailPostLink => '帖子链接';

  @override
  String get threadDetailFloorLink => '楼层链接';

  @override
  String get threadDetailExternalLink => '外部链接';

  @override
  String get threadDetailHomeLink => '首页链接';

  @override
  String get threadDetailReplyLink => '楼层回复链接';

  @override
  String threadDetailCopySuccess(String target) {
    return '$target已复制';
  }

  @override
  String get threadDetailFavorite => '收藏帖子';

  @override
  String get threadDetailUnfavorite => '已收藏';

  @override
  String get threadDetailOpenSource => '打开原帖';

  @override
  String get threadDetailMore => '更多';

  @override
  String get threadDetailDisplaySettings => '显示设置';

  @override
  String get threadDetailBackHome => '返回首页';

  @override
  String get threadDetailSelectCopy => '选择复制';

  @override
  String get threadDetailCopyAll => '全部复制';

  @override
  String threadDetailLoadFailed(String error) {
    return '帖子详情加载失败：$error';
  }

  @override
  String threadDetailRefreshFailed(String error) {
    return '刷新帖子详情失败：$error';
  }

  @override
  String threadDetailPageLoadFailed(String error) {
    return '页面加载失败：$error';
  }

  @override
  String get threadDetailFloorLocatorFailed => '楼层定位失败，已打开帖子';

  @override
  String get threadDetailUidMissing => '用户 UID 缺失';

  @override
  String threadFavoriteFailed(String error) {
    return '收藏操作失败：$error';
  }

  @override
  String get threadLoginRequired => '请先登录后再操作';

  @override
  String get threadPermissionDenied => '没有执行此操作的权限';

  @override
  String get threadUnsupported => '当前暂不支持此操作';

  @override
  String get threadDetailAnonymous => '匿名';

  @override
  String get threadDetailImageLink => '图片链接';

  @override
  String get threadDetailPostBody => '正文';

  @override
  String get threadPollVote => '投票';

  @override
  String get threadPollMultipleChoice => '可多选';

  @override
  String get threadPollDeadline => '截止时间';

  @override
  String get threadPollResults => '投票结果';

  @override
  String get threadPollSubmit => '提交';

  @override
  String threadPollMaxChoices(int count) {
    return '最多可选 $count 项';
  }

  @override
  String get threadPollSelectOption => '请选择投票选项';

  @override
  String get threadPollVoteSuccess => '投票成功';

  @override
  String threadPollVoteFailed(String error) {
    return '投票失败：$error';
  }

  @override
  String threadPollVotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 票',
      zero: '0 票',
    );
    return '$_temp0';
  }

  @override
  String get threadRatingTitle => '评分';

  @override
  String get threadRatingSubmit => '确定';

  @override
  String get threadRatingScore => '积分';

  @override
  String get threadRatingReasonHint => '评分理由';

  @override
  String get threadRatingNotifyAuthor => '通知作者';

  @override
  String threadRatingRange(int min, int max) {
    return '范围 $min~$max';
  }

  @override
  String threadRatingRangeWithRemaining(String range, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining',
      zero: '0',
    );
    return '$range，今日剩余 $_temp0';
  }

  @override
  String threadRatingRemaining(int count) {
    return '今日剩余 $count';
  }

  @override
  String get threadRatingParticipants => '参与人数';

  @override
  String threadRatingParticipantsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '参与人数 $count',
      zero: '参与人数 0',
    );
    return '$_temp0';
  }

  @override
  String get threadRatingPoints => '积分';

  @override
  String get threadRatingReason => '理由';

  @override
  String get threadRatingLoadFailed => '完整评分加载失败';

  @override
  String get threadRatingRetry => '重试加载完整评分';

  @override
  String get threadRatingExpand => '展开完整评分';

  @override
  String get threadRatingUnknownUser => '用户';

  @override
  String get threadRatingSuccess => '评分成功';

  @override
  String threadRatingFailed(String error) {
    return '评分失败：$error';
  }

  @override
  String get threadCommentTitle => '点评';

  @override
  String get threadCommentSubmit => '发布';

  @override
  String get threadCommentContent => '点评内容';

  @override
  String get threadCommentSuccess => '点评成功';

  @override
  String threadCommentFailed(String error) {
    return '点评失败：$error';
  }

  @override
  String get threadReplyContentRequired => '请输入回复内容';

  @override
  String get threadReplySuccess => '回复成功';

  @override
  String threadReplyFailed(String error) {
    return '回复失败：$error';
  }

  @override
  String get threadAttachmentOpen => '打开附件';

  @override
  String get threadImageSave => '保存图片';

  @override
  String get threadImageDownload => '下载当前图片';

  @override
  String get threadImageReaderTitle => '图片阅读';

  @override
  String get threadImageDisplay => '显示';

  @override
  String get threadHtmlConversionOriginal => '原文';

  @override
  String get threadHtmlConversionSimplified => '简体';

  @override
  String get threadHtmlConversionTraditional => '繁体';

  @override
  String get threadHtmlConversionSettings => '阅读设置';

  @override
  String get threadHtmlFontSize => '字号';

  @override
  String get threadHtmlLineSpacing => '间隔';

  @override
  String get threadHtmlPreserveAuthorFontSize => '保留作者字号';

  @override
  String get threadHtmlReset => '恢复默认';

  @override
  String get threadHtmlCollapseContent => '折叠内容';

  @override
  String get threadHtmlRenderFailed => '正文渲染失败，可长按楼层复制正文或打开原帖查看。';

  @override
  String get threadSelectionCopyTitle => '选择复制';

  @override
  String get threadDetailScrollTop => '滚动到顶部';

  @override
  String get threadDetailScrollBottom => '滚动到底部';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appLanguageSectionTitle => '介面語言';

  @override
  String get appLanguageSystem => '跟隨系統';

  @override
  String get appLanguageSimplifiedChinese => '簡體中文';

  @override
  String get appLanguageTraditionalChinese => '繁體中文';

  @override
  String appLanguageSaveFailed(String error) {
    return '語言設定儲存失敗：$error';
  }

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '確定';

  @override
  String get commonClose => '關閉';

  @override
  String get commonClear => '清空';

  @override
  String get commonRetry => '重試';

  @override
  String get commonUnknownError => '未知錯誤';

  @override
  String get forumHomeTitle => '論壇首頁';

  @override
  String get forumHomeSearch => '搜尋論壇';

  @override
  String get forumHomeRefresh => '重新整理論壇首頁';

  @override
  String get forumHomeEmpty => '目前沒有論壇版塊';

  @override
  String forumHomeLoadFailed(String error) {
    return '論壇首頁載入失敗：$error';
  }

  @override
  String forumHomeRefreshFailed(String error) {
    return '重新整理論壇首頁失敗：$error';
  }

  @override
  String get forumHomeFavoriteForums => '我收藏的版塊';

  @override
  String get forumHomeUncategorized => '未分類';

  @override
  String get forumDisplayTitle => '帖子列表';

  @override
  String get forumDisplaySearch => '搜尋本版';

  @override
  String get forumDisplayCreateThread => '發帖';

  @override
  String get forumDisplayToday => '今日';

  @override
  String get forumDisplayThreads => '主題';

  @override
  String get forumDisplayRank => '排名';

  @override
  String get forumDisplaySubForum => '子版塊';

  @override
  String get forumDisplayAnnouncements => '公告';

  @override
  String get forumDisplayPinned => '置頂';

  @override
  String get forumDisplayAnonymous => '匿名';

  @override
  String get forumDisplayPreviousPage => '上一頁';

  @override
  String get forumDisplayNextPage => '下一頁';

  @override
  String get forumDisplayNoMore => '沒有更多';

  @override
  String forumDisplayPage(int page) {
    return '第$page頁';
  }

  @override
  String get forumDisplayEmpty => '目前沒有帖子';

  @override
  String forumDisplayLoadFailed(String error) {
    return '帖子列表載入失敗：$error';
  }

  @override
  String get forumDisplayCopiedLink => '已複製帖子連結';

  @override
  String get forumShellNative => '解析模式';

  @override
  String get forumShellWebView => 'WebView 模式';

  @override
  String get forumWebViewLoading => '正在載入論壇頁面';

  @override
  String forumWebViewLoadFailed(String error) {
    return '論壇頁面載入失敗：$error';
  }

  @override
  String get forumWebViewRetry => '重試載入';

  @override
  String get forumWebViewOpenExternal => '在外部開啟';

  @override
  String get forumWebViewOpenExternalFailed => '開啟外部連結失敗';

  @override
  String get forumWebViewClose => '關閉論壇頁面';

  @override
  String get forumWebViewReplyThread => '回覆帖子';

  @override
  String get forumWebViewRefresh => '重新整理頁面';

  @override
  String get forumWebViewBackHome => '返回首頁';

  @override
  String get forumWebViewFeatureInProgress => '功能開發中';

  @override
  String get forumWebViewProcessing => '處理中';

  @override
  String get forumWebViewFavoriteForum => '收藏本版';

  @override
  String get forumWebViewUnfavoriteForum => '取消收藏';

  @override
  String get forumWebViewCancelFavorite => '取消收藏';

  @override
  String get forumWebViewFavoriteSuccess => '已收藏本版';

  @override
  String get forumWebViewUnfavoriteSuccess => '已取消收藏本版';

  @override
  String forumWebViewActionFailed(String error) {
    return '操作失敗，請稍後重試：$error';
  }

  @override
  String get forumWebViewFavoriteForumsTitle => '取消收藏';

  @override
  String forumWebViewFavoriteForumsLoadFailed(String error) {
    return '載入收藏版塊失敗：$error';
  }

  @override
  String get forumWebViewNoFavoriteForums => '目前沒有收藏版塊';

  @override
  String get forumWebViewAuthorOnly => '只看樓主';

  @override
  String get forumWebViewAllPosts => '看全部';

  @override
  String get forumWebViewNormalOrder => '正序瀏覽';

  @override
  String get forumWebViewReverseOrder => '倒序瀏覽';

  @override
  String get forumWebViewLocationFallback => '樓層定位失敗，已開啟帖子';

  @override
  String get forumWebViewPostLinkFallback => '帖子連結解析失敗，已在網頁中開啟';

  @override
  String get forumWebViewReplySuccess => '回覆成功';

  @override
  String get forumWebViewPostSuccess => '發布成功';

  @override
  String forumWebViewForumSearch(String board) {
    return '$board搜尋';
  }

  @override
  String get forumWebViewSearchForum => '論壇搜尋';

  @override
  String forumWebViewForumByFid(String fid) {
    return 'fid=$fid';
  }

  @override
  String get historyTitle => '記錄';

  @override
  String get historySearchHint => '搜尋記錄';

  @override
  String get historySearchOpen => '搜尋記錄';

  @override
  String get historySearchClose => '退出搜尋';

  @override
  String get historySearchClear => '清除搜尋';

  @override
  String get historyClearAll => '清空記錄';

  @override
  String get historyDelete => '刪除記錄';

  @override
  String get historyOpenSourceThread => '開啟原帖';

  @override
  String get historyOpenFailed => '開啟失敗，請稍後重試';

  @override
  String historyOpenFailedDetail(String error) {
    return '開啟失敗：$error';
  }

  @override
  String get historyDeleteFailed => '刪除記錄失敗';

  @override
  String get historyClearAllFailed => '清空記錄失敗';

  @override
  String get historyClearAllTitle => '清空全部記錄';

  @override
  String get historyClearAllBody => '瀏覽記錄將被清空，但不會刪除收藏、書架作品或下載內容。';

  @override
  String get historyNoResults => '沒有搜尋結果';

  @override
  String get historyEmpty => '還沒有瀏覽記錄';

  @override
  String get historyLoadFailed => '記錄載入失敗';

  @override
  String get historyLoadMoreFailed => '載入失敗，點擊重試';

  @override
  String get historyTypeThread => '帖子';

  @override
  String get historyTypeComic => '漫畫';

  @override
  String get historyTypeNovel => '小說';

  @override
  String get historySourceThread => '來源原帖';

  @override
  String get historyToday => '今天';

  @override
  String historyDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days 天前',
      one: '1 天前',
    );
    return '$_temp0';
  }

  @override
  String get historyTargetInvalid => '記錄目標無效';

  @override
  String get historyPageClosed => '目前頁面已關閉';

  @override
  String get historyThreadExpired => '帖子記錄已失效';

  @override
  String historyWorkUnavailable(String type) {
    return '該$type作品已從本機移除';
  }

  @override
  String get historyNativeUnavailable => '目前無法開啟原生頁面';

  @override
  String get historyLoginRequired => '請先登入後再開啟此記錄';

  @override
  String get appNavigationForum => '論壇';

  @override
  String get appNavigationFavorites => '收藏';

  @override
  String get appNavigationComic => '漫畫';

  @override
  String get appNavigationNovel => '小說';

  @override
  String get appNavigationHistory => '記錄';

  @override
  String get appNavigationMore => '更多';

  @override
  String startupSelectionSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已選 $count 項',
      zero: '未選擇項目',
    );
    return '$_temp0';
  }

  @override
  String get startupSelectionExit => '退出多選';

  @override
  String get startupSelectionSelectAll => '全選目前分類';

  @override
  String get startupSelectionInvert => '反選目前分類';

  @override
  String get startupSelectionActionAssignCategory => '設定分類';

  @override
  String get startupSelectionActionMarkAllRead => '全部已讀';

  @override
  String get startupSelectionActionMarkAllUnread => '全部未讀';

  @override
  String get startupSelectionActionDownload => '下載';

  @override
  String get startupSelectionActionUnfavorite => '取消收藏';

  @override
  String get startupSelectionActionGeneric => '執行操作';

  @override
  String startupBatchActionFailed(String error) {
    return '批次操作失敗：$error';
  }

  @override
  String get startupConfirmUnfavoriteTitle => '確認取消收藏';

  @override
  String get startupConfirmActionTitle => '確認執行操作';

  @override
  String startupConfirmUnfavoriteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項',
      zero: '0 項',
    );
    return '將取消已選 $_temp0收藏。若作品已無其他活躍收藏來源，相關本機作品、章節、封面快取和下載也會被清除。是否繼續？';
  }

  @override
  String startupConfirmActionBody(int count, String action) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項',
      zero: '0 項',
    );
    return '將對已選 $_temp0執行「$action」，是否繼續？';
  }

  @override
  String get startupSelectCategory => '選擇分類';

  @override
  String get startupCreateCategory => '新增分類';

  @override
  String get startupCategoryNameHint => '請輸入分類名稱';

  @override
  String startupSelectionCategoryAssigned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已為 $count 項設定分類',
      zero: '沒有項目設定分類',
    );
    return '$_temp0';
  }

  @override
  String startupSelectionCategoryAssignedPartial(
    int succeededCount,
    int failedCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      succeededCount,
      locale: localeName,
      other: '已為 $succeededCount 項設定分類',
      zero: '沒有項目設定分類',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failedCount,
      locale: localeName,
      other: '失敗 $failedCount 項',
      zero: '沒有失敗項目',
    );
    return '$_temp0；$_temp1';
  }

  @override
  String startupSelectionReadStateChanged(int count, String state) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項',
      zero: '0 項',
    );
    return '已將 $_temp0標記為$state';
  }

  @override
  String startupSelectionReadStateChangedPartial(
    int succeededCount,
    int failedCount,
    String state,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      succeededCount,
      locale: localeName,
      other: '$succeededCount 項',
      zero: '0 項',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failedCount,
      locale: localeName,
      other: '失敗 $failedCount 項',
      zero: '沒有失敗項目',
    );
    return '已將 $_temp0標記為$state；$_temp1';
  }

  @override
  String get startupSelectionRead => '已讀';

  @override
  String get startupSelectionUnread => '未讀';

  @override
  String startupSelectionDownloadQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個章節',
      zero: '0 個章節',
    );
    return '已將 $_temp0加入下載佇列';
  }

  @override
  String startupSelectionDownloadQueuedPartial(int count, int failedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個章節',
      zero: '0 個章節',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failedCount,
      locale: localeName,
      other: '失敗 $failedCount 項',
      zero: '沒有失敗項目',
    );
    return '已將 $_temp0加入下載佇列；$_temp1';
  }

  @override
  String get startupSelectionDownloadAlreadyQueued => '所選章節已在下載佇列中';

  @override
  String get startupSelectionNothingToDownload => '沒有需要下載的章節';

  @override
  String startupSelectionUnfavorite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項',
      zero: '0 項',
    );
    return '已取消 $_temp0收藏';
  }

  @override
  String startupSelectionUnfavoritePartial(
    int succeededCount,
    int failedCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      succeededCount,
      locale: localeName,
      other: '$succeededCount 項',
      zero: '0 項',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failedCount,
      locale: localeName,
      other: '失敗 $failedCount 項',
      zero: '沒有失敗項目',
    );
    return '已取消 $_temp0收藏；$_temp1';
  }

  @override
  String startupSelectionUnsupported(String action) {
    return '目前不支援批次$action';
  }

  @override
  String get startupSelectionMissingTargetCategory => '請選擇目標分類';

  @override
  String get startupSelectionNoValidItems => '沒有可處理的項目';

  @override
  String startupSelectionNoChange(String action) {
    return '沒有可執行的$action';
  }

  @override
  String get moreTitle => '更多';

  @override
  String get moreMyProfile => '我的資料';

  @override
  String get moreMyProfileSignedOutSubtitle => '登入後查看個人資料、訊息提醒';

  @override
  String moreMyProfileSubtitle(String username) {
    return '$username 的資料與訊息提醒';
  }

  @override
  String get moreLogin => '登入';

  @override
  String get moreLoginSubtitle => '登入論壇帳號並同步登入狀態';

  @override
  String get moreLogout => '登出';

  @override
  String get moreLogoutSubtitle => '登出目前論壇帳號';

  @override
  String moreLogoutSubtitleUsername(String username) {
    return '目前帳號：$username';
  }

  @override
  String get moreLogoutConfirmTitle => '登出';

  @override
  String get moreLogoutConfirmBody => '登出後會清除本地論壇登入狀態。';

  @override
  String get moreLogoutSuccess => '已登出';

  @override
  String moreLogoutFailed(String error) {
    return '登出失敗：$error';
  }

  @override
  String get moreForumDisplayMode => '論壇顯示模式';

  @override
  String moreForumCurrentMode(String mode) {
    return '目前：$mode';
  }

  @override
  String get moreForumModeWebView => 'WebView 模式';

  @override
  String get moreForumModeNative => '解析模式';

  @override
  String moreForumModeSwitchFailed(String error) {
    return '論壇顯示模式切換失敗：$error';
  }

  @override
  String get moreAppearance => '外觀與文字';

  @override
  String moreCurrentTheme(String theme) {
    return '目前：$theme';
  }

  @override
  String get moreThemeSectionTitle => '主題';

  @override
  String get moreThemeLight => '淺色';

  @override
  String get moreThemeDark => '深色';

  @override
  String get moreThemeSystem => '跟隨系統';

  @override
  String get moreThemeDescriptionLight => '保持淺色外觀';

  @override
  String get moreThemeDescriptionDark => '使用深色外觀';

  @override
  String get moreThemeDescriptionSystem => '跟隨系統淺色或深色設定';

  @override
  String moreThemeSaveFailed(String error) {
    return '主題設定儲存失敗：$error';
  }

  @override
  String get moreNavigationManagement => '導覽列管理';

  @override
  String moreVisibleNavigationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項',
      zero: '0 項',
    );
    return '已顯示 $_temp0';
  }

  @override
  String get moreNavigationRestoreDefault => '恢復預設';

  @override
  String get moreNavigationRetry => '重試';

  @override
  String get moreNavigationDragToReorder => '拖曳排序';

  @override
  String get moreNavigationMinimumOneRequired => '至少保留一個導覽項目';

  @override
  String get moreNavigationSaveFailed => '導覽列設定儲存失敗';

  @override
  String get moreDataAndStorage => '資料與儲存空間';

  @override
  String get moreDataAndStorageSubtitle => '管理圖片快取與下載位置';

  @override
  String get moreDownloadQueue => '下載佇列';

  @override
  String get moreDownloadParsingImages => '正在解析圖片';

  @override
  String moreDownloadActiveProgress(
    String comicTitle,
    String episodeTitle,
    String progress,
    int waitingCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      waitingCount,
      locale: localeName,
      other: ' · 等待 $waitingCount',
      zero: '',
    );
    return '正在下載《$comicTitle》 $episodeTitle · $progress$_temp0';
  }

  @override
  String moreDownloadWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個工作',
      zero: '0 個工作',
    );
    return '等待下載 · $_temp0';
  }

  @override
  String moreDownloadFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個工作下載失敗',
      zero: '0 個工作下載失敗',
    );
    return '$_temp0';
  }

  @override
  String get moreDownloadEmpty => '目前沒有下載工作';

  @override
  String get moreAbout => '關於';

  @override
  String get moreAboutSubtitle => '應用程式資訊';

  @override
  String moreAboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String moreAboutVersionWithBuild(String version, String buildNumber) {
    return '版本 $version ($buildNumber)';
  }

  @override
  String get moreAboutVersionLoading => '版本讀取中';

  @override
  String get moreAboutVersionSection => '版本';

  @override
  String get moreAboutReleaseNotes => '更新日誌';

  @override
  String get moreAboutProjectSection => '專案';

  @override
  String get moreAboutGitHub => 'GitHub 儲存庫';

  @override
  String get moreAboutOpenGitHubFailed => '無法開啟 GitHub 儲存庫';

  @override
  String get moreDebugQuillComposer => 'Quill Composer 原型';

  @override
  String get moreDebugQuillComposerSubtitle => '驗證所見即所得的 Discuz BBCode 轉換';

  @override
  String get moreDebugHtmlRenderer => 'HTML 正文渲染原型';

  @override
  String get moreDebugHtmlRendererSubtitle => '驗證複雜正文 HTML 的原生渲染';

  @override
  String get moreStorageTitle => '資料與儲存空間';

  @override
  String moreStorageLoadFailed(String error) {
    return '載入資料與儲存設定失敗：$error';
  }

  @override
  String get moreStorageClearCache => '清理快取';

  @override
  String get moreStorageClear => '清理';

  @override
  String get moreStorageCacheDescription =>
      '清理 HTML、解析快照與一般圖片快取；長期快取、封面、下載和使用者資料會保留。';

  @override
  String get moreStorageLocation => '儲存位置';

  @override
  String get moreStorageDefaultLocation => '預設位置';

  @override
  String get moreStorageCustomLocation => '自訂位置';

  @override
  String get moreStorageChooseDirectory => '選擇自訂目錄';

  @override
  String get moreStorageRestoreDefault => '恢復預設';

  @override
  String moreStorageMaximumCache(String size) {
    return '最大快取：$size';
  }

  @override
  String get moreStorageNoticeCachePartiallyCleared => '部分快取清理失敗，請稍後重試';

  @override
  String get moreStorageNoticeCacheCleared => '已清理一般快取，長期快取、下載與使用者資料已保留';

  @override
  String get moreStorageNoticeCacheLimitUpdated => '最大快取已更新';

  @override
  String get moreStorageNoticeDirectoryNotSelected => '未選擇目錄';

  @override
  String get moreStorageNoticeLocationUpdated => '儲存位置已更新';

  @override
  String get moreStorageNoticeDefaultRestored => '已恢復預設儲存位置';

  @override
  String get moreStorageNoticeUsageReloaded => '儲存統計已重新整理';

  @override
  String moreStorageNoticeDiagnosticsExported(String path) {
    return '快取診斷已匯出：$path';
  }

  @override
  String get moreStorageUsageOverview => '快取與資料總覽';

  @override
  String moreStorageUsageTotal(String size) {
    return '應用程式資料總計：$size';
  }

  @override
  String get moreStorageReloadUsage => '重新統計';

  @override
  String get moreStorageExportDiagnostics => '快取診斷匯出';

  @override
  String get moreStorageBucketImageCache => '圖片快取';

  @override
  String get moreStorageBucketPageCache => '頁面快取';

  @override
  String get moreStorageBucketLibraryMetadata => '書架資料';

  @override
  String get moreStorageBucketHistory => '瀏覽記錄';

  @override
  String get moreStorageBucketComposerDraft => '草稿';

  @override
  String get moreStorageBucketDownload => '下載內容';

  @override
  String get moreStorageBucketAppSettings => '應用程式設定';

  @override
  String get moreStorageCategoryClearable => '可清理快取';

  @override
  String get moreStorageCategorySticky => '長期快取';

  @override
  String get moreStorageCategoryProtected => '受保護/下載內容';

  @override
  String moreStorageImageRole(String role, String qualifier) {
    return '$role$qualifier';
  }

  @override
  String get moreStorageImageQualifierRecentReader => '（最近閱讀）';

  @override
  String get moreStorageImageQualifierSticky => '（低淘汰）';

  @override
  String get moreStorageImageQualifierProtected => '（受保護）';

  @override
  String get moreStorageImageQualifierDownloaded => '（已下載）';

  @override
  String get moreStorageImageCover => '封面';

  @override
  String get moreStorageImageCustomCover => '自訂封面';

  @override
  String get moreStorageImageComicPage => '漫畫頁';

  @override
  String get moreStorageImageNovelInline => '小說正文圖';

  @override
  String get moreStorageImageThreadInline => '帖子圖片';

  @override
  String get moreStorageImageThreadAttachment => '帖子附件圖';

  @override
  String get moreStorageImageAvatar => '頭像';

  @override
  String get moreStorageImageRemoteSmiley => '表情圖片';

  @override
  String get moreStorageImageForumHead => '論壇頭圖';

  @override
  String get moreStorageImageForumIcon => '論壇圖示';

  @override
  String get moreStorageImageBlogInline => '日誌圖片';

  @override
  String get moreStorageImageUnknown => '未分類圖片';

  @override
  String get moreStorageDocumentForum => '論壇首頁';

  @override
  String get moreStorageDocumentForumDisplay => '帖子列表';

  @override
  String get moreStorageDocumentThread => '帖子詳情';

  @override
  String get moreStorageDocumentTag => '標籤頁';

  @override
  String get moreStorageDocumentProfile => '個人資料';

  @override
  String get moreStorageDocumentBlog => '日誌';

  @override
  String get moreStorageDocumentUnknown => '頁面';

  @override
  String moreStorageDocumentHtml(String owner, int count) {
    return '$owner HTML（$count）';
  }

  @override
  String moreStorageSnapshot(String snapshotType, int count) {
    return '$snapshotType快照（$count）';
  }

  @override
  String get moreStorageSnapshotForumHome => '論壇首頁';

  @override
  String get moreStorageSnapshotForumDisplay => '帖子列表';

  @override
  String get moreStorageSnapshotThreadDetail => '帖子詳情';

  @override
  String get moreStorageSnapshotUnknown => '頁面解析';

  @override
  String moreStorageComposerDraft(int count) {
    return '發文/回覆草稿（$count）';
  }

  @override
  String get moreStorageDownloadComics => '漫畫下載';

  @override
  String get moreStorageDownloadNovels => '小說下載';

  @override
  String get moreStorageDownloadFavorites => '收藏快照';

  @override
  String get moreStorageDatabase => '本機資料庫';

  @override
  String moreStorageLibraryCount(String kind, int count) {
    return '$kind：$count';
  }

  @override
  String get moreStorageLibraryComics => '漫畫作品';

  @override
  String get moreStorageLibraryComicEpisodes => '漫畫章節';

  @override
  String get moreStorageLibraryNovels => '小說作品';

  @override
  String get moreStorageLibraryNovelEpisodes => '小說章節';

  @override
  String get moreStorageLibraryFavorites => '收藏帖子';

  @override
  String get moreStorageLibraryWorkState => '作品狀態';

  @override
  String get moreStorageLibraryEpisodeState => '章節狀態';

  @override
  String get moreStorageHistoryDatabase => '記錄資料庫';

  @override
  String moreStorageHistoryEntries(int count) {
    return '瀏覽記錄：$count';
  }

  @override
  String get threadDetailTitle => '帖子詳情';

  @override
  String get threadDetailRefresh => '重新整理帖子詳情';

  @override
  String get threadDetailOnlyAuthor => '只看該作者';

  @override
  String get threadDetailAllPosts => '顯示全部樓層';

  @override
  String get threadDetailReverseOrder => '倒序瀏覽';

  @override
  String get threadDetailNormalOrder => '正序瀏覽';

  @override
  String get threadDetailPreviousPage => '上一頁';

  @override
  String get threadDetailNextPage => '下一頁';

  @override
  String get threadDetailNoMore => '沒有更多';

  @override
  String threadDetailPage(int page) {
    return '第$page頁';
  }

  @override
  String get threadDetailReply => '回覆';

  @override
  String get threadDetailReplyPost => '回覆帖子';

  @override
  String get threadDetailEdit => '編輯';

  @override
  String get threadDetailShare => '分享';

  @override
  String get threadDetailCopyLink => '複製連結';

  @override
  String get threadDetailPostLink => '帖子連結';

  @override
  String get threadDetailFloorLink => '樓層連結';

  @override
  String get threadDetailExternalLink => '外部連結';

  @override
  String get threadDetailHomeLink => '首頁連結';

  @override
  String get threadDetailReplyLink => '樓層回覆連結';

  @override
  String threadDetailCopySuccess(String target) {
    return '$target已複製';
  }

  @override
  String get threadDetailFavorite => '收藏帖子';

  @override
  String get threadDetailUnfavorite => '已收藏';

  @override
  String get threadDetailOpenSource => '開啟原帖';

  @override
  String get threadDetailMore => '更多';

  @override
  String get threadDetailDisplaySettings => '顯示設定';

  @override
  String get threadDetailBackHome => '返回首頁';

  @override
  String get threadDetailSelectCopy => '選擇複製';

  @override
  String get threadDetailCopyAll => '全部複製';

  @override
  String threadDetailLoadFailed(String error) {
    return '帖子詳情載入失敗：$error';
  }

  @override
  String threadDetailRefreshFailed(String error) {
    return '重新整理帖子詳情失敗：$error';
  }

  @override
  String threadDetailPageLoadFailed(String error) {
    return '頁面載入失敗：$error';
  }

  @override
  String get threadDetailFloorLocatorFailed => '樓層定位失敗，已開啟帖子';

  @override
  String get threadDetailUidMissing => '使用者 UID 缺失';

  @override
  String threadFavoriteFailed(String error) {
    return '收藏操作失敗：$error';
  }

  @override
  String get threadLoginRequired => '請先登入後再操作';

  @override
  String get threadPermissionDenied => '沒有執行此操作的權限';

  @override
  String get threadUnsupported => '目前暫不支援此操作';

  @override
  String get threadDetailAnonymous => '匿名';

  @override
  String get threadDetailImageLink => '圖片連結';

  @override
  String get threadDetailPostBody => '正文';

  @override
  String get threadPollVote => '投票';

  @override
  String get threadPollMultipleChoice => '可複選';

  @override
  String get threadPollDeadline => '截止時間';

  @override
  String get threadPollResults => '投票結果';

  @override
  String get threadPollSubmit => '提交';

  @override
  String threadPollMaxChoices(int count) {
    return '最多可選 $count 項';
  }

  @override
  String get threadPollSelectOption => '請選擇投票選項';

  @override
  String get threadPollVoteSuccess => '投票成功';

  @override
  String threadPollVoteFailed(String error) {
    return '投票失敗：$error';
  }

  @override
  String threadPollVotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 票',
      zero: '0 票',
    );
    return '$_temp0';
  }

  @override
  String get threadRatingTitle => '評分';

  @override
  String get threadRatingSubmit => '確定';

  @override
  String get threadRatingScore => '積分';

  @override
  String get threadRatingReasonHint => '評分理由';

  @override
  String get threadRatingNotifyAuthor => '通知作者';

  @override
  String threadRatingRange(int min, int max) {
    return '範圍 $min~$max';
  }

  @override
  String threadRatingRangeWithRemaining(String range, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining',
      zero: '0',
    );
    return '$range，今日剩餘 $_temp0';
  }

  @override
  String threadRatingRemaining(int count) {
    return '今日剩餘 $count';
  }

  @override
  String get threadRatingParticipants => '參與人數';

  @override
  String threadRatingParticipantsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '參與人數 $count',
      zero: '參與人數 0',
    );
    return '$_temp0';
  }

  @override
  String get threadRatingPoints => '積分';

  @override
  String get threadRatingReason => '理由';

  @override
  String get threadRatingLoadFailed => '完整評分載入失敗';

  @override
  String get threadRatingRetry => '重試載入完整評分';

  @override
  String get threadRatingExpand => '展開完整評分';

  @override
  String get threadRatingUnknownUser => '使用者';

  @override
  String get threadRatingSuccess => '評分成功';

  @override
  String threadRatingFailed(String error) {
    return '評分失敗：$error';
  }

  @override
  String get threadCommentTitle => '點評';

  @override
  String get threadCommentSubmit => '發佈';

  @override
  String get threadCommentContent => '點評內容';

  @override
  String get threadCommentSuccess => '點評成功';

  @override
  String threadCommentFailed(String error) {
    return '點評失敗：$error';
  }

  @override
  String get threadReplyContentRequired => '請輸入回覆內容';

  @override
  String get threadReplySuccess => '回覆成功';

  @override
  String threadReplyFailed(String error) {
    return '回覆失敗：$error';
  }

  @override
  String get threadAttachmentOpen => '開啟附件';

  @override
  String get threadImageSave => '儲存圖片';

  @override
  String get threadImageDownload => '下載目前圖片';

  @override
  String get threadImageReaderTitle => '圖片閱讀';

  @override
  String get threadImageDisplay => '顯示';

  @override
  String get threadHtmlConversionOriginal => '原文';

  @override
  String get threadHtmlConversionSimplified => '簡體';

  @override
  String get threadHtmlConversionTraditional => '繁體';

  @override
  String get threadHtmlConversionSettings => '閱讀設定';

  @override
  String get threadHtmlFontSize => '字號';

  @override
  String get threadHtmlLineSpacing => '間隔';

  @override
  String get threadHtmlPreserveAuthorFontSize => '保留作者字號';

  @override
  String get threadHtmlReset => '恢復預設';

  @override
  String get threadHtmlCollapseContent => '摺疊內容';

  @override
  String get threadHtmlRenderFailed => '正文渲染失敗，可長按樓層複製正文或開啟原帖查看。';

  @override
  String get threadSelectionCopyTitle => '選擇複製';

  @override
  String get threadDetailScrollTop => '滾動到頂部';

  @override
  String get threadDetailScrollBottom => '滾動到底部';
}
