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
  String get commonApply => '应用';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonRemove => '移除';

  @override
  String get commonUnknownError => '未知错误';

  @override
  String get networkSecurityVerificationTitle => '安全验证';

  @override
  String get networkSecurityVerificationPreparing => '正在完成站点安全验证…';

  @override
  String get networkSecurityVerificationFailed => '安全验证未完成，请重试';

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
  String get forumRefreshPage => '刷新页面';

  @override
  String get forumWebViewBackHome => '返回首页';

  @override
  String get forumWebViewFeatureInProgress => '功能开发中';

  @override
  String get forumProcessing => '处理中';

  @override
  String get forumFavoriteForum => '收藏本版';

  @override
  String get forumUnfavoriteForum => '取消收藏';

  @override
  String get forumFavoriteSuccess => '已收藏本版';

  @override
  String get forumUnfavoriteSuccess => '已取消收藏本版';

  @override
  String forumActionFailed(String error) {
    return '操作失败，请稍后重试：$error';
  }

  @override
  String get forumFavoriteForumsTitle => '取消收藏';

  @override
  String forumFavoriteForumsLoadFailed(String error) {
    return '加载收藏版块失败：$error';
  }

  @override
  String get forumNoFavoriteForums => '暂无收藏版块';

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
  String forumForumByFid(String fid) {
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
  String librarySelectionSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选 $count 项',
      zero: '未选择项目',
    );
    return '$_temp0';
  }

  @override
  String get librarySelectionExit => '退出多选';

  @override
  String get librarySelectionSelectAll => '全选当前分类';

  @override
  String get librarySelectionInvert => '反选当前分类';

  @override
  String get librarySelectionActionAssignCategory => '设置分类';

  @override
  String get librarySelectionActionMarkAllRead => '全部已读';

  @override
  String get librarySelectionActionMarkAllUnread => '全部未读';

  @override
  String get librarySelectionActionDownload => '下载';

  @override
  String get librarySelectionActionUnfavorite => '取消收藏';

  @override
  String get librarySelectionActionGeneric => '执行操作';

  @override
  String librarySelectionActionFailed(String error) {
    return '批量操作失败：$error';
  }

  @override
  String get librarySelectionConfirmUnfavoriteTitle => '确认取消收藏';

  @override
  String get librarySelectionConfirmActionTitle => '确认执行操作';

  @override
  String librarySelectionConfirmUnfavoriteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      zero: '0 项',
    );
    return '将取消已选 $_temp0收藏。若作品已无其它活跃收藏来源，相关本地作品、章节、封面缓存和下载也会被清除。是否继续？';
  }

  @override
  String librarySelectionConfirmActionBody(int count, String action) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      zero: '0 项',
    );
    return '将对已选 $_temp0执行“$action”，是否继续？';
  }

  @override
  String get librarySelectionSelectCategory => '选择分类';

  @override
  String get librarySelectionCreateCategory => '新建分类';

  @override
  String get librarySelectionCategoryNameHint => '请输入分类名称';

  @override
  String librarySelectionCategoryAssigned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已为 $count 项设置分类',
      zero: '没有项目设置分类',
    );
    return '$_temp0';
  }

  @override
  String librarySelectionCategoryAssignedPartial(
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
  String librarySelectionReadStateChanged(int count, String state) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      zero: '0 项',
    );
    return '已将 $_temp0标记为$state';
  }

  @override
  String librarySelectionReadStateChangedPartial(
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
  String get librarySelectionRead => '已读';

  @override
  String get librarySelectionUnread => '未读';

  @override
  String librarySelectionDownloadQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个章节',
      zero: '0 个章节',
    );
    return '已将 $_temp0加入下载队列';
  }

  @override
  String librarySelectionDownloadQueuedPartial(int count, int failedCount) {
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
  String get librarySelectionDownloadAlreadyQueued => '所选章节已在下载队列中';

  @override
  String get librarySelectionNothingToDownload => '没有需要下载的章节';

  @override
  String librarySelectionUnfavorite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      zero: '0 项',
    );
    return '已取消 $_temp0收藏';
  }

  @override
  String librarySelectionUnfavoritePartial(
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
  String librarySelectionUnsupported(String action) {
    return '当前不支持批量$action';
  }

  @override
  String get librarySelectionMissingTargetCategory => '请选择目标分类';

  @override
  String get librarySelectionNoValidItems => '没有可处理的项目';

  @override
  String librarySelectionNoChange(String action) {
    return '没有可执行的$action';
  }

  @override
  String libraryShelfTitle(String module) {
    String _temp0 = intl.Intl.selectLogic(module, {
      'comic': '漫画',
      'novel': '小说',
      'favorite': '收藏',
      'other': '书架',
    });
    return '$_temp0';
  }

  @override
  String libraryShelfLoadFailed(String error) {
    return '加载书架失败：$error';
  }

  @override
  String get libraryShelfEmpty => '书架为空';

  @override
  String get libraryShelfSearch => '搜索书架';

  @override
  String get libraryShelfSearchHint => '搜索作品';

  @override
  String get libraryShelfFilterAndSort => '筛选与排序';

  @override
  String get libraryShelfCreateCategory => '新建分类';

  @override
  String get libraryShelfRenameCategory => '重命名当前分类';

  @override
  String get libraryShelfDeleteCategory => '删除当前分类';

  @override
  String get libraryShelfDeleteCategoryTitle => '删除分类';

  @override
  String get libraryShelfDeleteCategoryBody => '删除后，该分类中的作品会移动到默认分类。是否继续？';

  @override
  String get libraryShelfDefaultCategory => '默认';

  @override
  String get libraryShelfDefaultCategoryCannotRename => '默认分类不支持重命名';

  @override
  String get libraryShelfDefaultCategoryCannotDelete => '默认分类不支持删除';

  @override
  String get libraryShelfCategoryNameHint => '请输入分类名称';

  @override
  String libraryShelfCategoryMatchCount(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: '0',
    );
    return '$name $_temp0';
  }

  @override
  String get libraryShelfUpdate => '更新书架';

  @override
  String get libraryShelfRandomOpen => '随机打开作品';

  @override
  String get libraryShelfNoRandomWork => '当前分类没有可打开的作品';

  @override
  String get libraryShelfFilter => '筛选';

  @override
  String get libraryShelfSort => '排序';

  @override
  String get libraryShelfDisplayMode => '显示';

  @override
  String get libraryShelfGrid => '网格';

  @override
  String get libraryShelfList => '列表';

  @override
  String get libraryShelfColumnsPerRow => '每行个数';

  @override
  String get libraryShelfFilterDownloaded => '已下载';

  @override
  String get libraryShelfFilterUnread => '未读';

  @override
  String get libraryShelfFilterRead => '阅读过';

  @override
  String get libraryShelfFilterBookmarked => '有书签';

  @override
  String get libraryShelfSortName => '名称';

  @override
  String get libraryShelfSortChapterCount => '章节数';

  @override
  String get libraryShelfSortLastReadAt => '最近阅读';

  @override
  String get libraryShelfSortLastCheckedAt => '最近检查';

  @override
  String get libraryShelfSortUnreadCount => '未读章节数';

  @override
  String get libraryShelfSortWorkUpdatedAt => '作品更新时间';

  @override
  String get libraryShelfSortFetchedAt => '获取时间';

  @override
  String get libraryShelfSortFavoriteAddedAt => '收藏日期';

  @override
  String get libraryShelfMergeDuplicates => '合并重复';

  @override
  String libraryShelfMergeDuplicatesSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个重复作品',
      zero: '0 个重复作品',
    );
    return '已合并 $_temp0';
  }

  @override
  String get libraryShelfMergeDuplicatesNoChange => '没有可合并的重复作品';

  @override
  String get libraryShelfActionUnsupported => '当前书架不支持此操作';

  @override
  String get libraryTaskCoverWarmup => '正在准备封面';

  @override
  String get libraryTaskFavoriteSyncFetching => '正在获取收藏列表';

  @override
  String get libraryTaskFavoriteSyncSaving => '正在保存收藏数据';

  @override
  String get libraryTaskFavoriteSyncLoadingDetails => '正在读取收藏详情';

  @override
  String libraryTaskFavoriteSyncLoadingDetailsSubject(String subject) {
    return '正在读取《$subject》';
  }

  @override
  String get libraryTaskFavoriteSyncFinishing => '正在完成收藏同步';

  @override
  String get libraryTaskComicSearchWaiting => '漫画搜索正在等待';

  @override
  String libraryTaskComicSearchWaitingSubject(String subject) {
    return '《$subject》正在等待搜索';
  }

  @override
  String libraryTaskComicSearchWaitingDuration(
    String subject,
    String duration,
  ) {
    return '《$subject》正在等待搜索，预计 $duration';
  }

  @override
  String libraryTaskDurationSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 秒',
      one: '1 秒',
    );
    return '$_temp0';
  }

  @override
  String libraryTaskDurationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 分钟',
      one: '1 分钟',
    );
    return '$_temp0';
  }

  @override
  String get libraryTaskFavoriteSyncNotificationTitle => '收藏同步';

  @override
  String get libraryTaskComicSearchNotificationTitle => '漫画搜索';

  @override
  String get libraryTaskNotificationTitle => '书架任务';

  @override
  String get libraryDetailDownload => '下载';

  @override
  String get libraryDetailFilterAndSort => '筛选与排序';

  @override
  String get libraryDetailRefresh => '刷新';

  @override
  String get libraryDetailChangeCategory => '修改分类';

  @override
  String get libraryDetailEditMetadata => '编辑作品信息';

  @override
  String get libraryDetailConfigureCatalog => '配置目录';

  @override
  String get libraryDetailManageChapters => '管理章节';

  @override
  String get libraryDetailSetCustomCover => '自定义封面';

  @override
  String get libraryDetailRemoveCustomCover => '取消封面';

  @override
  String get libraryDetailEditIntro => '编辑简介';

  @override
  String get libraryDetailIntroHint => '请输入简介';

  @override
  String get libraryDetailNoIntro => '暂无简介';

  @override
  String get libraryDetailContinue => '继续';

  @override
  String get libraryDetailIntro => '简介';

  @override
  String libraryDetailLoadFailed(String error) {
    return '加载详情失败：$error';
  }

  @override
  String get libraryDetailInShelf => '在书架中';

  @override
  String get libraryDetailAddToShelf => '添加到书架';

  @override
  String get libraryDetailUpdate => '更新';

  @override
  String get libraryDetailSourceThread => '原帖';

  @override
  String get libraryDetailNoNovelCover => '小说无封面';

  @override
  String get libraryDetailAuthor => '作者';

  @override
  String get libraryDetailTranslator => '翻译者';

  @override
  String get libraryDetailTranslationGroup => '汉化组';

  @override
  String get libraryDetailPublisher => '发布者';

  @override
  String libraryDetailMetadataSemantics(String label, String value) {
    return '$label：$value';
  }

  @override
  String get libraryDetailDownloadUnread => '下载未读章节';

  @override
  String get libraryDetailDownloadAll => '下载全部章节';

  @override
  String libraryDetailDeleteDownloadFailed(String error) {
    return '删除下载失败：$error';
  }

  @override
  String libraryDetailDownloadFailed(String error) {
    return '下载失败：$error';
  }

  @override
  String get libraryDetailReadStateUpdateFailed => '阅读状态更新失败';

  @override
  String get libraryDetailAllChapters => '全部章节';

  @override
  String get libraryDetailDownloaded => '已下载';

  @override
  String get libraryDetailUnread => '未读';

  @override
  String get libraryDetailBookmarked => '已加书签';

  @override
  String libraryDetailExcludeFilter(String label) {
    return '排除$label';
  }

  @override
  String get libraryDetailFilter => '筛选';

  @override
  String get libraryDetailSort => '排序';

  @override
  String get libraryDetailSortBySource => '按来源';

  @override
  String get libraryDetailAddBookmark => '添加书签';

  @override
  String get libraryDetailRemoveBookmark => '移除书签';

  @override
  String get libraryDetailResetWorkReading => '重置本作品阅读';

  @override
  String get libraryDetailDeleteChapterDownload => '删除该章节下载';

  @override
  String get libraryDetailResetReadingTitle => '重置本作品阅读？';

  @override
  String get libraryDetailResetReadingBody =>
      '全部章节将变为未读，所有阅读进度和上次阅读位置都会被清除。书签和下载不会受影响。';

  @override
  String get libraryDetailResetReadingConfirm => '重置';

  @override
  String get libraryDetailResetReadingFailed => '重置作品阅读失败';

  @override
  String libraryDetailRefreshFailed(String error) {
    return '更新失败：$error';
  }

  @override
  String get libraryDetailRefreshUpdated => '已更新';

  @override
  String libraryDetailRefreshChaptersChanged(
    int insertedCount,
    int updatedCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      insertedCount,
      locale: localeName,
      other: '已新增 $insertedCount 章',
      zero: '未新增章节',
    );
    String _temp1 = intl.Intl.pluralLogic(
      updatedCount,
      locale: localeName,
      other: '更新 $updatedCount 章',
      zero: '未更新章节',
    );
    return '$_temp0，$_temp1';
  }

  @override
  String get libraryDetailRefreshAlreadyCurrent => '已是最新章节';

  @override
  String get libraryDetailRefreshNoUpdates => '未发现新的章节';

  @override
  String libraryDetailRefreshQueued(String duration) {
    return '已加入更新队列，预计 $duration';
  }

  @override
  String libraryDetailRefreshQueuedAtPosition(int position, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      position,
      locale: localeName,
      other: '有 $position 个任务',
      zero: '没有等待任务',
    );
    return '已加入更新队列，前方 $_temp0，预计 $duration';
  }

  @override
  String get libraryDetailRefreshUnavailable => '暂无可更新内容';

  @override
  String libraryDetailCatalogLoadFailed(String error) {
    return '读取目录配置失败：$error';
  }

  @override
  String get libraryDetailMetadataTitle => '标题';

  @override
  String get libraryDetailMetadataSearchTitle => '更新搜索关键词';

  @override
  String get libraryDetailMetadataSearchHelp => '留空时优先使用自定义标题，否则使用当前作品标题';

  @override
  String get libraryDetailMetadataSourceTitle => '来源标题';

  @override
  String get libraryDetailMetadataSourceAuthor => '来源作者';

  @override
  String get libraryDetailMetadataSourceTranslationGroup => '来源汉化组';

  @override
  String libraryDetailSourceValue(String label, String value) {
    return '$label：$value';
  }

  @override
  String libraryDetailSourceEmpty(String label) {
    return '$label：无';
  }

  @override
  String get libraryDetailCatalogUrl => '目录 URL';

  @override
  String libraryDetailCatalogSource(String url) {
    return '来源目录：$url';
  }

  @override
  String get libraryDetailCatalogSourceEmpty => '来源目录：无';

  @override
  String libraryDetailCatalogSaveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get libraryDetailCatalogInvalidUrl => '请输入有效的目录 URL';

  @override
  String get libraryDetailCatalogIncompleteUrl => '目录 URL 不完整';

  @override
  String get libraryDetailCatalogUnsupportedScheme => '目录 URL 仅支持 HTTP 或 HTTPS';

  @override
  String libraryDetailCatalogUnexpectedHost(String host) {
    return '目录 URL 必须来自 $host';
  }

  @override
  String get libraryDetailCatalogNotTagCatalog => '请输入标签目录页面的 URL';

  @override
  String libraryDetailCoverUpdateFailed(String error) {
    return '封面更新失败：$error';
  }

  @override
  String get libraryDetailCoverUpdated => '封面已更新';

  @override
  String libraryDetailCoverRemoveFailed(String error) {
    return '取消封面失败：$error';
  }

  @override
  String get libraryDetailCoverRemoved => '已取消封面';

  @override
  String libraryChapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '共 $count 章',
      zero: '共 0 章',
    );
    return '$_temp0';
  }

  @override
  String libraryChapterFallbackTitle(String tid) {
    return '章节 $tid';
  }

  @override
  String get libraryChapterBookmarkSemantics => '已添加书签';

  @override
  String get libraryChapterDownloading => '正在下载';

  @override
  String get libraryChapterDownloadedDelete => '已下载，点击删除下载';

  @override
  String get libraryChapterDownload => '下载该章节';

  @override
  String get libraryChapterClearReadState => '清除阅读状态';

  @override
  String get libraryChapterMarkRead => '标记已读';

  @override
  String libraryChapterCurrentPage(int page) {
    return '第 $page 页';
  }

  @override
  String get libraryChapterLastRead => '上次阅读';

  @override
  String libraryChapterProgressSemantics(String subtitle, String progress) {
    return '$subtitle，$progress';
  }

  @override
  String get libraryChapterFilterAny => '不限';

  @override
  String libraryChapterFilterOnly(String label) {
    return '只看$label';
  }

  @override
  String libraryChapterFilterExclude(String label) {
    return '排除$label';
  }

  @override
  String get libraryChapterManagementLoading => '正在读取章节';

  @override
  String libraryChapterManagementSummary(
    int total,
    int parsed,
    int manual,
    int hidden,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '共 $total 章',
      zero: '共 0 章',
    );
    String _temp1 = intl.Intl.pluralLogic(
      parsed,
      locale: localeName,
      other: '解析 $parsed 章',
      zero: '解析 0 章',
    );
    String _temp2 = intl.Intl.pluralLogic(
      manual,
      locale: localeName,
      other: '手动 $manual 章',
      zero: '手动 0 章',
    );
    String _temp3 = intl.Intl.pluralLogic(
      hidden,
      locale: localeName,
      other: '隐藏 $hidden 章',
      zero: '隐藏 0 章',
    );
    return '$_temp0 · $_temp1 · $_temp2 · $_temp3';
  }

  @override
  String get libraryChapterFilterLabel => '筛选章节';

  @override
  String get libraryChapterFilterHint => '按标题或 TID 搜索';

  @override
  String get libraryChapterClearFilter => '清除筛选';

  @override
  String get libraryChapterAdd => '添加章节';

  @override
  String get libraryChapterAddHint => '粘贴帖子链接或直接输入 TID';

  @override
  String get libraryChapterAddHelp =>
      '支持 forum.php、thread-xxx.html、api/mobile 等链接形式';

  @override
  String get libraryChapterManagementEmpty => '暂无章节，可在上方粘贴帖子链接手动添加';

  @override
  String get libraryChapterManagementNoMatches => '没有匹配的章节';

  @override
  String get libraryChapterShow => '显示该章节';

  @override
  String get libraryChapterHide => '隐藏该章节';

  @override
  String get libraryChapterHidden => '已隐藏';

  @override
  String get libraryChapterKeepOneVisible => '至少保留一个可见章节';

  @override
  String get libraryChapterRename => '重命名该章节';

  @override
  String get libraryChapterRemove => '移除该章节';

  @override
  String get libraryChapterAdded => '已添加章节';

  @override
  String get libraryChapterDuplicate => '该章节已存在';

  @override
  String libraryChapterAddFailed(String error) {
    return '添加失败：$error';
  }

  @override
  String get libraryChapterInputEmpty => '请输入帖子链接或 TID';

  @override
  String get libraryChapterInputInvalidUrl => '请输入有效的帖子链接或 TID';

  @override
  String get libraryChapterInputUnsupportedScheme => '帖子链接仅支持 HTTP 或 HTTPS';

  @override
  String libraryChapterInputUnexpectedHost(String host) {
    return '帖子链接必须来自 $host';
  }

  @override
  String get libraryChapterInputUnsupportedThreadUrl => '不支持此帖子链接形式';

  @override
  String get libraryChapterInputMissingTid => '帖子链接中缺少有效的 TID';

  @override
  String libraryChapterVisibilityUpdateFailed(String error) {
    return '更新显示状态失败：$error';
  }

  @override
  String get libraryChapterRestoredSourceTitle => '已恢复来源章节名';

  @override
  String get libraryChapterRenamed => '已重命名章节';

  @override
  String libraryChapterRenameFailed(String error) {
    return '重命名失败：$error';
  }

  @override
  String get libraryChapterRemoveTitle => '移除该章节？';

  @override
  String libraryChapterRemoveBody(String title) {
    return '将删除手动添加的“$title”及其阅读记录与下载任务，此操作不可撤销。';
  }

  @override
  String get libraryChapterParsedCannotRemove => '解析章节不可移除，可改为隐藏';

  @override
  String get libraryChapterRemoved => '已移除章节';

  @override
  String libraryChapterRemovedWithWarnings(String warnings) {
    return '章节已移除，但$warnings';
  }

  @override
  String get libraryChapterDownloadTaskCleanupFailed => '下载任务清理失败';

  @override
  String get libraryChapterDownloadFileCleanupFailed => '章节下载文件清理失败';

  @override
  String libraryChapterRemoveFailed(String error) {
    return '移除失败：$error';
  }

  @override
  String get libraryChapterRenameTitle => '重命名章节';

  @override
  String get libraryChapterName => '章节名';

  @override
  String get libraryChapterRestoreDefaultTitleHelp => '留空恢复默认章节名';

  @override
  String libraryChapterRestoreSourceTitleHelp(String title) {
    return '留空恢复来源章节名：$title';
  }

  @override
  String get libraryChapterManual => '手动';

  @override
  String get libraryChapterParsed => '解析';

  @override
  String libraryChapterLoadFailed(String error) {
    return '读取章节失败：$error';
  }

  @override
  String get libraryCoverFocalTitle => '调整封面焦点';

  @override
  String get libraryCoverFocalHelp => '拖动选框选择封面取景区域，原图不会被裁剪';

  @override
  String get libraryCoverImageLoadFailed => '图片加载失败';

  @override
  String get libraryCoverCenter => '居中';

  @override
  String get libraryErrorRedactedLink => '[链接已隐藏]';

  @override
  String get libraryErrorRedactedSecret => '[敏感信息已隐藏]';

  @override
  String get readerBack => '返回';

  @override
  String get readerPrevious => '上一章';

  @override
  String get readerNext => '下一章';

  @override
  String readerSelectedSemantics(String label) {
    return '$label，已选择';
  }

  @override
  String readerProgressSemantics(String current, String total) {
    return '阅读进度：$current / $total';
  }

  @override
  String get readerModeVertical => '垂直';

  @override
  String get readerModeLtr => '左到右';

  @override
  String get readerModeRtl => '右到左';

  @override
  String get readerModeVerticalContinuous => '垂直连续';

  @override
  String get readerModeSingleLtr => '单页 左到右';

  @override
  String get readerModeSingleRtl => '单页 右到左';

  @override
  String get readerDisplaySettings => '显示设置';

  @override
  String get readerReadingMode => '阅读模式';

  @override
  String get readerPageFit => '页面适配';

  @override
  String get readerPageFitWidth => '宽度';

  @override
  String get readerPageFitHeight => '高度';

  @override
  String get readerPageFitContain => '屏幕';

  @override
  String get readerBackground => '背景色';

  @override
  String get readerBackgroundTheme => '主题';

  @override
  String get readerBackgroundBlack => '黑';

  @override
  String get readerBackgroundWhite => '白';

  @override
  String get readerBackgroundGray => '灰';

  @override
  String get readerPageSpacing => '页间距';

  @override
  String get readerPageIndicator => '页码浮层';

  @override
  String get readerNoImages => '没有可阅读图片';

  @override
  String get readerImageLoadFailed => '图片加载失败';

  @override
  String get readerTailContent => '末尾内容';

  @override
  String get readerContinue => '继续';

  @override
  String get readerDownloadUnsupported => '当前图片不支持下载';

  @override
  String get readerExportSaving => '正在保存当前图片';

  @override
  String readerExportSaved(String destination) {
    return '已保存到$destination';
  }

  @override
  String get readerExportDefaultDestination => '系统照片';

  @override
  String get readerExportCacheUnavailable => '图片暂不可用，请重试';

  @override
  String get readerExportPermissionDenied => '没有照片库写入权限，请在系统设置中允许';

  @override
  String get readerExportPermissionRestricted => '照片库权限受系统限制';

  @override
  String get readerExportUnsupportedPlatform => '当前平台不支持保存图片';

  @override
  String get readerExportUnsupportedFormat => '当前图片格式不支持保存';

  @override
  String get readerExportFailed => '保存图片失败，请重试';

  @override
  String comicUntitledWork(String workId) {
    return '未命名漫画（$workId）';
  }

  @override
  String comicChapterFallbackTitle(String sourceTid) {
    return '章节 $sourceTid';
  }

  @override
  String get comicAddToShelf => '加入书架';

  @override
  String get comicAlreadyInShelf => '已在书架';

  @override
  String get comicNoImages => '当前章节没有可阅读图片';

  @override
  String comicReaderLoadFailed(String error) {
    return '加载阅读器失败：$error';
  }

  @override
  String get comicReaderNetworkFailure => '网络异常，请检查后重试';

  @override
  String get comicReaderAuthFailure => '登录态已失效，请重新登录后重试';

  @override
  String get comicReaderServerFailure => '服务暂时不可用，请稍后重试';

  @override
  String get comicReaderParseFailure => '页面结构异常，无法解析章节内容';

  @override
  String get comicReaderUnknownFailure => '加载章节失败';

  @override
  String get comicReaderEpisodeUnavailable => '章节不存在或已被移除';

  @override
  String get comicBookmarkAdd => '添加书签';

  @override
  String get comicBookmarkRemove => '取消书签';

  @override
  String get comicBookmarkAdded => '已添加书签';

  @override
  String get comicBookmarkRemoved => '已移除书签';

  @override
  String get comicOpenSourceThread => '打开原帖';

  @override
  String get comicMoreActions => '更多操作';

  @override
  String get comicReaderRefreshEpisode => '刷新章节';

  @override
  String get comicReaderEpisodeRefreshed => '章节已刷新';

  @override
  String get comicReaderRefreshFailed => '刷新章节失败，已保留当前内容';

  @override
  String get comicReaderRefreshNoImages => '未解析到图片，已保留当前章节';

  @override
  String get comicMore => '更多';

  @override
  String get comicChapterList => '章节列表';

  @override
  String get comicChapterAction => '章节';

  @override
  String get comicCurrentChapter => '当前';

  @override
  String get comicDisplay => '显示';

  @override
  String get comicDownloadCurrentImage => '下载当前图片';

  @override
  String get comicPreviousEpisode => '上一话';

  @override
  String get comicNextEpisode => '下一话';

  @override
  String get comicFirstEpisode => '已是第一话';

  @override
  String get comicLastEpisode => '已是最后一话';

  @override
  String get comicMarkEpisodeRead => '标记本章已读';

  @override
  String get comicMarkEpisodeUnread => '标记本章未读';

  @override
  String get comicEpisodeMarkedRead => '已标记本章已读';

  @override
  String get comicEpisodeMarkedUnread => '已标记本章未读';

  @override
  String get comicSetCurrentPageCover => '将当前页设为封面';

  @override
  String get comicCoverImageUnavailable => '当前页图片暂不可用，无法设为封面';

  @override
  String get comicCoverUpdateFailed => '封面更新失败';

  @override
  String get comicCoverUpdated => '封面已更新';

  @override
  String get comicEpisodeSwitchFailed => '章节切换失败，已保留当前章节';

  @override
  String get comicSetCoverFocus => '调整封面焦点';

  @override
  String comicNextChapterTitle(String title) {
    return '下一章：$title';
  }

  @override
  String get comicSwitchingEpisode => '正在切换章节';

  @override
  String get comicOpenNextEpisode => '点击进入下一章';

  @override
  String get comicOpeningEpisode => '正在打开章节';

  @override
  String get comicRefreshNoNewLinks => '未提取到新的章节链接';

  @override
  String comicRefreshCompleted(int insertedCount, int updatedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      insertedCount,
      locale: localeName,
      other: '$insertedCount',
      zero: '0',
    );
    String _temp1 = intl.Intl.pluralLogic(
      updatedCount,
      locale: localeName,
      other: '$updatedCount',
      zero: '0',
    );
    return '章节刷新完成：新增 $_temp0，更新 $_temp1';
  }

  @override
  String comicRefreshFailed(String error) {
    return '刷新章节失败：$error';
  }

  @override
  String get comicComment => '评论';

  @override
  String get comicCommentLoading => '评论加载中';

  @override
  String get comicCommentEmpty => '暂无评论';

  @override
  String get comicCommentUnavailable => '评论暂不可用';

  @override
  String get comicCommentOpen => '查看评论';

  @override
  String get comicCommentUnavailableFeedback => '无法查看评论';

  @override
  String get comicCommentContinue => '继续滑动进入下一章';

  @override
  String comicCommentContinueTo(String title) {
    return '继续滑动进入：$title';
  }

  @override
  String get comicDownloadQueue => '下载队列';

  @override
  String get comicDownloadQueueEmpty => '暂无下载任务';

  @override
  String get comicDownloadActive => '正在下载';

  @override
  String get comicDownloadPending => '等待中';

  @override
  String get comicDownloadFailedSection => '下载失败';

  @override
  String get comicDownloadCanceling => '正在取消';

  @override
  String get comicDownloadCancel => '取消下载';

  @override
  String get comicDownloadRemove => '移除任务';

  @override
  String get comicDownloadRetry => '重试';

  @override
  String comicDownloadQueuePosition(String episodeTitle, int position) {
    return '$episodeTitle · 第 $position 位';
  }

  @override
  String comicDownloadFailureDetail(String episodeTitle, String error) {
    return '$episodeTitle · $error';
  }

  @override
  String get comicDownloadResolvingImages => '正在解析图片';

  @override
  String comicDownloadProgress(int completed, int total) {
    return '$completed/$total';
  }

  @override
  String comicDownloadCancelFailed(String error) {
    return '取消下载失败：$error';
  }

  @override
  String comicDownloadRemoveFailed(String error) {
    return '移除任务失败：$error';
  }

  @override
  String comicDownloadRetryFailed(String error) {
    return '重试失败：$error';
  }

  @override
  String get comicDownloadWorkUnavailable => '漫画作品不存在或已被移除';

  @override
  String get comicDownloadEpisodeUnavailable => '漫画章节不存在或已被移除';

  @override
  String get comicDownloadNoImages => '章节没有可下载图片';

  @override
  String get comicDownloadImageFailed => '部分图片下载失败';

  @override
  String get comicDownloadStorageFailed => '下载文件保存失败';

  @override
  String get comicDownloadUnknownFailure => '下载失败，请重试';

  @override
  String novelUntitledWork(String novelId) {
    return '未命名小说（$novelId）';
  }

  @override
  String novelChapterFallbackTitle(String sourceTid) {
    return '章节 $sourceTid';
  }

  @override
  String get novelOriginalBadge => '原创';

  @override
  String get novelOpenInReader => '阅读器';

  @override
  String get novelOpenSourcePost => '原帖';

  @override
  String novelSaveOpenModeFailed(String error) {
    return '保存章节打开方式失败：$error';
  }

  @override
  String get novelSourceRouteDialogTitle => '无法定位原帖楼层';

  @override
  String get novelOpenThreadHome => '打开帖子首页';

  @override
  String get novelSourceRouteInvalidTid => '章节缺少有效的来源 TID';

  @override
  String get novelSourceRouteInvalidPid => '章节缺少有效的来源 PID';

  @override
  String novelSourceRouteLocatorFailed(String error) {
    return '原帖楼层定位失败：$error';
  }

  @override
  String get novelSourceRouteEmptyResult => '原帖楼层定位结果为空';

  @override
  String get novelSourceRouteMismatchedResult => '原帖楼层定位结果与章节来源不一致';

  @override
  String get novelSourceRouteInvalidPage => '原帖楼层页码无效';

  @override
  String get novelHydrationRecoveringMetadata => '正在恢复小说来源信息';

  @override
  String get novelHydrationPreparing => '正在准备章节';

  @override
  String novelHydrationCommitting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个章节',
      zero: '0 个章节',
    );
    return '正在保存 $_temp0';
  }

  @override
  String novelHydrationLoadingPage(int currentPage, int acceptedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      acceptedCount,
      locale: localeName,
      other: '$acceptedCount 章',
      zero: '0 章',
    );
    return '正在加载第 $currentPage 页 · 已发现 $_temp0';
  }

  @override
  String novelHydrationLoadingPageOfTotal(
    int currentPage,
    int totalPages,
    int acceptedCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      acceptedCount,
      locale: localeName,
      other: '$acceptedCount 章',
      zero: '0 章',
    );
    return '正在加载第 $currentPage/$totalPages 页 · 已发现 $_temp0';
  }

  @override
  String get novelHydrationMissingSource => '缺少小说来源信息，无法加载章节';

  @override
  String get novelHydrationMissingPublisher => '来源帖子缺少有效的发布者 ID';

  @override
  String get novelHydrationMissingTid => '小说缺少来源帖子 ID';

  @override
  String get novelHydrationMissingCheckpoint => '章节同步检查点缺失，无法安全更新';

  @override
  String get novelHydrationInterrupted => '章节同步已中断，请重试';

  @override
  String novelChapterLoadFailed(String error) {
    return '章节加载失败：$error';
  }

  @override
  String get novelChapterLoadUnknown => '章节加载失败，请重试';

  @override
  String get novelReaderNoChapters => '小说没有可阅读章节';

  @override
  String get novelReaderContentMissing => '章节正文暂不可用';

  @override
  String novelReaderLoadFailed(String error) {
    return '加载阅读器失败：$error';
  }

  @override
  String get novelDisplaySettings => '显示设置';

  @override
  String get novelTypography => '排版';

  @override
  String get novelFontSize => '字号';

  @override
  String get novelLineSpacing => '间隔';

  @override
  String get novelTheme => '主题';

  @override
  String get novelThemeLight => '浅色';

  @override
  String get novelThemeSepia => '护眼';

  @override
  String get novelThemeDark => '深色';

  @override
  String get novelThemeFollowApp => '跟随应用';

  @override
  String get novelReading => '阅读';

  @override
  String get novelReadingMode => '阅读模式';

  @override
  String get novelConversionMode => '简繁';

  @override
  String get novelSafeContent => '安全显示正文';

  @override
  String get novelConversionOriginal => '原文';

  @override
  String get novelConversionSimplified => '简体';

  @override
  String get novelConversionTraditional => '繁体';

  @override
  String get novelFlowScroll => '滚动';

  @override
  String get novelFlowPagedLtr => '分页 LTR';

  @override
  String get novelFlowPagedRtl => '分页 RTL';

  @override
  String get novelBookmarkAdd => '添加章节书签';

  @override
  String get novelBookmarkRemove => '移除章节书签';

  @override
  String get novelBookmarkAdded => '已添加书签';

  @override
  String get novelBookmarkRemoved => '已移除书签';

  @override
  String get novelOpenSourceThread => '打开原帖';

  @override
  String get novelCatalog => '目录';

  @override
  String get novelDisplay => '显示';

  @override
  String get novelPageCountPending => '计算中';

  @override
  String get novelPositionChanged => '位置已变化，已保留当前页';

  @override
  String get novelChapterSwitchFailed => '章节切换失败，已保留当前章节';

  @override
  String get novelReturnToScrollFailed => '切回滚动模式失败';

  @override
  String get novelSaveDisplaySettingsFailed => '显示设置保存失败';

  @override
  String get novelLinkOpenFailed => '链接打开失败';

  @override
  String get novelImageLinkCopied => '图片链接已复制';

  @override
  String get novelWorkUpdateFailed => '作品更新失败，已保留当前章节';

  @override
  String get novelSearchChapters => '搜索章节';

  @override
  String get novelNoMatchingChapters => '没有匹配的章节';

  @override
  String get novelBookmark => '书签';

  @override
  String get novelCurrent => '当前';

  @override
  String get novelLastRead => '上次阅读';

  @override
  String novelNextChapter(String title) {
    return '下一章：$title';
  }

  @override
  String get novelChapterUnavailable => '章节暂时无法显示';

  @override
  String get novelUpdateWork => '更新作品';

  @override
  String get novelPagedWindowUnavailable => '当前窗口无法生成分页布局';

  @override
  String get novelPagedPreparing => '正在准备分页正文';

  @override
  String get novelPagedCalculating => '正在计算分页布局';

  @override
  String get novelPagedNoContent => '本章没有可显示的正文';

  @override
  String get novelPagedRestoringPosition => '正在恢复阅读位置';

  @override
  String get novelPagedLayoutFailed => '分页布局失败';

  @override
  String get novelReturnToScroll => '回到滚动';

  @override
  String novelPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      zero: '0 页',
    );
    return '$_temp0';
  }

  @override
  String novelPageSemantics(
    String chapterTitle,
    int currentPage,
    String totalPages,
  ) {
    return '$chapterTitle，第 $currentPage 页，共 $totalPages';
  }

  @override
  String novelPageValue(int currentPage, String totalPages) {
    return '第 $currentPage 页，共 $totalPages';
  }

  @override
  String novelNextPageSemantics(int page) {
    return '下一页，第 $page 页';
  }

  @override
  String novelPreviousPageSemantics(int page) {
    return '上一页，第 $page 页';
  }

  @override
  String novelPageIndicator(int currentPage, String totalPages) {
    return '$currentPage / $totalPages';
  }

  @override
  String novelChapterTurnContinue(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'next': '继续滑动进入下一章',
      'previous': '继续滑动进入上一章',
      'other': '继续滑动切换章节',
    });
    return '$_temp0';
  }

  @override
  String novelChapterTurnRelease(String direction, String title) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'next': '松手进入下一章 · $title',
      'previous': '松手进入上一章 · $title',
      'other': '松手切换章节 · $title',
    });
    return '$_temp0';
  }

  @override
  String novelPageOfTotalSemantics(int page, int total) {
    return '第 $page 页，共 $total 页';
  }

  @override
  String get libraryOperationWorkNotFound => '作品不存在或已被移除';

  @override
  String get libraryOperationChapterNotFound => '章节不存在或已被移除';

  @override
  String get libraryOperationUnsupported => '当前模块不支持此操作';

  @override
  String get libraryOperationCacheWriteFailed => '缓存写入失败，请重试';

  @override
  String get libraryOperationDefaultCategoryImmutable => '默认分类不能修改或删除';

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
  String get moreUnusedImages => '未使用图片管理';

  @override
  String get moreUnusedImagesSubtitle => '查看并删除尚未用于帖子的上传图片';

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
  String get moreColorThemeSectionTitle => '配色主题';

  @override
  String get moreAppearanceModeSectionTitle => '外观模式';

  @override
  String get moreThemeFamilyWarmPaper => '暖纸';

  @override
  String get moreThemeFamilyMoonWhite => '月白';

  @override
  String get moreThemeFamilyPlumPurple => '梅紫';

  @override
  String get moreThemeFamilyWarmPaperDescription => '温暖柔和的米色与褐色配色';

  @override
  String get moreThemeFamilyMoonWhiteDescription => '清冷克制的月白与蓝灰配色';

  @override
  String get moreThemeFamilyPlumPurpleDescription => '温润沉静的烟粉与梅紫配色';

  @override
  String moreThemeSummary(String family, String mode) {
    return '$family · $mode';
  }

  @override
  String get moreThemeLight => '日间';

  @override
  String get moreThemeDark => '夜间';

  @override
  String get moreThemeSystem => '跟随系统';

  @override
  String get moreThemeDescriptionLight => '始终使用日间外观';

  @override
  String get moreThemeDescriptionDark => '始终使用夜间外观';

  @override
  String get moreThemeDescriptionSystem => '根据系统设置切换日间或夜间外观';

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
  String get moreStorageBucketLibraryCover => '书架封面资产';

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
  String get moreStorageImageComposerUnusedAttachment => '未使用上传图片';

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
  String get threadDetailCopyFloorLink => '复制楼层链接';

  @override
  String get threadDetailCopyFloorLinkFailed => '楼层链接复制失败';

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
  String get threadFavoriteSuccess => '收藏成功';

  @override
  String get threadFavoriteSuccessSyncFailed => '收藏成功，但收藏书架同步失败';

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
  String get threadPollVoteAlreadyVoted => '已经投过票';

  @override
  String get threadPollVoteClosed => '投票已关闭';

  @override
  String get threadPollVoteExpired => '投票已过期';

  @override
  String get threadPollVoteTooMany => '选择的选项超过投票上限';

  @override
  String get threadPollVoteUnavailable => '当前投票不可用';

  @override
  String get threadPollVoteInvalidSelection => '投票选项无效，请重新选择';

  @override
  String get threadPollVoteSessionExpired => '会话已过期，请刷新后重试';

  @override
  String get threadPollVoteOutcomeUnknown => '无法确认投票结果，请刷新帖子后再决定是否重试';

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
  String get threadRatingOutcomeUnknown => '评分结果暂时无法确认，请刷新后查看';

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
  String get threadCommentOutcomeUnknown => '点评结果暂时无法确认，请刷新后查看';

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
  String get threadHtmlCollapseExpanded => '收起折叠内容';

  @override
  String get threadHtmlCollapseCollapsed => '展开折叠内容';

  @override
  String get threadHtmlRenderFailed => '正文渲染失败，可长按楼层复制正文或打开原帖查看。';

  @override
  String get threadSelectionCopyTitle => '选择复制';

  @override
  String get threadDetailScrollTop => '滚动到顶部';

  @override
  String get threadDetailScrollBottom => '滚动到底部';

  @override
  String get commonUse => '使用';

  @override
  String get commonReset => '重置';

  @override
  String get composerBold => '加粗';

  @override
  String get composerItalic => '斜体';

  @override
  String get composerUnderline => '下划线';

  @override
  String get composerStrikethrough => '删除线';

  @override
  String get composerTextColor => '字体色';

  @override
  String get composerBackgroundColor => '背景色';

  @override
  String get composerLink => '链接';

  @override
  String get composerFontSize => '字号';

  @override
  String get composerAlignment => '对齐';

  @override
  String get composerQuote => '引用';

  @override
  String get composerImage => '图片';

  @override
  String get composerSticker => '表情';

  @override
  String get composerCollapse => '折叠';

  @override
  String get composerCollapseTitleHint => '输入折叠标题';

  @override
  String get composerCollapseCreateTitle => '新建折叠';

  @override
  String get composerCollapseEditTitle => '编辑折叠';

  @override
  String get composerCollapseBodyHint => '输入折叠正文';

  @override
  String get composerCollapseDiscardTitle => '放弃折叠修改？';

  @override
  String get composerCollapseDiscardBody => '标题和正文的修改将不会保存。';

  @override
  String get composerCollapseDiscardConfirm => '放弃修改';

  @override
  String get composerCollapseDeleteTitle => '删除这个折叠？';

  @override
  String get composerCollapseDeleteBody => '折叠标题和正文将从帖子内容中删除。';

  @override
  String get composerCollapseConflict => '帖子正文已更新，无法应用本次折叠修改。请复制内容后重新打开。';

  @override
  String get composerFormat => '格式';

  @override
  String get composerPreview => '预览';

  @override
  String get composerSourceMode => '源码';

  @override
  String get composerVisualMode => '返回编辑';

  @override
  String get composerMore => '更多';

  @override
  String get composerMoreSettings => '更多设置';

  @override
  String get composerUseSignature => '使用个人签名';

  @override
  String get composerResetDraft => '重置草稿';

  @override
  String get composerResetDraftTitle => '重置草稿？';

  @override
  String get composerResetDraftBody => '当前编辑内容和已选图片将被清空，且无法恢复。';

  @override
  String get composerContinueEditing => '继续编辑';

  @override
  String get composerSaveDraftAndLeave => '保存草稿并离开';

  @override
  String get composerRestoredDraft => '已恢复未发送草稿';

  @override
  String get postingRestoredDraftWithTags => '已恢复未发送的草稿，请注意已恢复的主题标签';

  @override
  String composerPendingAttachment(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 张图片已上传，请选择位置后点击图片按钮重新插入',
      zero: '图片已上传，请选择位置后点击图片按钮重新插入',
    );
    return '$_temp0';
  }

  @override
  String get composerPendingAttachmentSelectionExpired => '当前选区无法安全恢复，请重新选择位置';

  @override
  String composerUploadingImages(int current, int total) {
    return '正在上传图片 $current/$total';
  }

  @override
  String composerImageUploaded(String fileName) {
    return '$fileName 已上传';
  }

  @override
  String composerImageUploadFailed(String fileName) {
    return '$fileName 上传失败，请重试';
  }

  @override
  String composerImageUploadFailedWithReason(String fileName, String reason) {
    return '$fileName 上传失败：$reason';
  }

  @override
  String get composerImagePickerFailed => '选择图片失败，请重试';

  @override
  String get composerImageFileMissing => '图片文件不存在，无法上传';

  @override
  String get composerImageInvalidFileType => '只能上传图片文件';

  @override
  String get composerImageExtensionNotAllowed => '当前版块不允许上传该类型图片';

  @override
  String get composerImagePermissionExpired => '上传权限已失效，请重新登录';

  @override
  String get composerImageQuotaExceeded => '附件额度不足，无法上传图片';

  @override
  String get composerImageFileTooLarge => '图片超过当前用户组或文件类型的大小限制';

  @override
  String get composerImagePermissionDenied => '当前账号没有上传图片的权限';

  @override
  String get composerImageInvalidContent => '服务器未能识别该图片，请检查文件后重试';

  @override
  String get composerImageSaveFailed => '服务器保存图片失败，请稍后重试';

  @override
  String get composerImageFileNameRejected => '图片文件名包含不允许的内容，请重命名后重试';

  @override
  String get composerImageDimensionsExceeded => '图片宽高超过服务器限制，请缩小后重试';

  @override
  String get composerImageUploadOutcomeUnknown =>
      '无法确认图片是否上传成功，请先检查未使用图片，避免重复上传';

  @override
  String get composerImageUploadTimeout => '图片上传超时，请重试';

  @override
  String get composerImageUploadNetwork => '网络异常，图片上传失败';

  @override
  String get composerImageUploadServer => '上传服务异常，请稍后重试';

  @override
  String get composerImageUploadUnknown => '图片上传失败，请重试';

  @override
  String composerLoadDraftFailed(String error) {
    return '加载草稿失败：$error';
  }

  @override
  String composerStickerLoadFailed(String error) {
    return '表情加载失败：$error';
  }

  @override
  String get composerStickerNetworkRequired => '需要联网加载表情包';

  @override
  String get composerStickerAllGroup => '表情';

  @override
  String get composerStickerDefaultGroup => '默认表情';

  @override
  String get composerStartTypingHint => '请开始输入';

  @override
  String get composerImageRetentionHint => '草稿图片本地副本最多保留 14 天，打开草稿时会联网校验';

  @override
  String get composerDraftImageVerificationFailed =>
      '草稿图片校验失败，图片预览已暂时隐藏。你仍可编辑和发送，联网后可重试。';

  @override
  String composerDraftImagesInvalidated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '发现 $count 张已失效的草稿图片，正文代码已保留',
      zero: '没有失效的草稿图片',
    );
    return '$_temp0';
  }

  @override
  String get unusedImagesPageTitle => '未使用图片管理';

  @override
  String get unusedImagesEmpty => '没有尚未用于帖子的上传图片';

  @override
  String get unusedImagesLoadFailed => '未能读取未使用图片，请检查网络或登录状态后重试';

  @override
  String get unusedImagesDeleteTooltip => '删除图片';

  @override
  String get unusedImagesDeleteTitle => '删除这张未使用图片？';

  @override
  String get unusedImagesDeleteBody => '图片将从服务器删除，草稿中的正文代码会保留。此操作不可撤销。';

  @override
  String get unusedImagesDeleteFailed => '图片删除未成功，图片仍保留';

  @override
  String get composerLinkTitle => '添加链接';

  @override
  String get composerLinkUrl => '链接';

  @override
  String get composerLinkText => '链接文字';

  @override
  String get composerLinkTextHint => '显示给别人看的文字';

  @override
  String get composerLinkUrlRequired => '请输入链接';

  @override
  String get composerLinkTextRequired => '请输入链接文字';

  @override
  String get composerAlignLeft => '左对齐';

  @override
  String get composerAlignCenter => '居中';

  @override
  String get composerAlignRight => '右对齐';

  @override
  String get composerClearFormatting => '清除状态';

  @override
  String get composerClearFontSize => '清除字号';

  @override
  String get composerClearTextColor => '清除颜色';

  @override
  String get composerClearBackgroundColor => '清除背景';

  @override
  String get composerAuthenticationRequired => '登录状态已失效，请重新登录后再试';

  @override
  String composerCredentialExpired(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '发帖凭证已失效，请刷新登录态后重试',
      'reply': '回复凭证已失效，请刷新登录态后重试',
      'other': '提交凭证已失效，请刷新登录态后重试',
    });
    return '$_temp0';
  }

  @override
  String composerRateLimited(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '发帖过于频繁，请稍后再试',
      'reply': '回复太频繁了，请稍后再试',
      'other': '操作过于频繁，请稍后再试',
    });
    return '$_temp0';
  }

  @override
  String composerPermissionDenied(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '当前账号权限不足，无法发帖',
      'reply': '当前账号权限不足，无法发送回复',
      'other': '当前账号权限不足',
    });
    return '$_temp0';
  }

  @override
  String get composerSubmissionTypeRequired => '该版块要求选择主题分类，请先选择';

  @override
  String get composerSubmissionSubjectTooShort => '标题过短，请补充后重试';

  @override
  String get composerSubmissionSubjectTooLong => '标题过长，请缩短后重试';

  @override
  String composerSubmissionContentTooShort(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '正文内容过短，请补充后重试',
      'reply': '回复内容过短，请补充后重试',
      'other': '提交内容过短，请补充后重试',
    });
    return '$_temp0';
  }

  @override
  String composerSubmissionContentTooLong(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '正文内容过长，请缩短后重试',
      'reply': '回复内容过长，请缩短后重试',
      'other': '提交内容过长，请缩短后重试',
    });
    return '$_temp0';
  }

  @override
  String composerSubmissionTargetUnavailable(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '目标版块不可用，请刷新后重试',
      'reply': '目标帖子或楼层不可用，请刷新后重试',
      'other': '提交目标不可用，请刷新后重试',
    });
    return '$_temp0';
  }

  @override
  String get composerSubmissionThreadClosed => '该帖子已关闭，无法继续回复';

  @override
  String get composerCaptchaRequired => '需要验证码，请暂时改用网页发布';

  @override
  String get composerPollInvalid => '投票配置无效，请检查选项与截止时间';

  @override
  String get composerPollOptionCountInvalid => '投票选项数量不合法';

  @override
  String get composerPollFieldsInvalid => '请正确填写投票相关字段';

  @override
  String get composerNetworkTimeout => '网络超时，请稍后重试';

  @override
  String get composerNetworkFailure => '网络异常，请稍后重试';

  @override
  String get composerServerFailure => '服务异常，请稍后重试';

  @override
  String composerUnknownFailure(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '发帖失败，请稍后重试',
      'reply': '发送回复失败，请稍后重试',
      'other': '提交失败，请稍后重试',
    });
    return '$_temp0';
  }

  @override
  String composerOutcomeUnknown(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '发帖结果无法确认，请先检查版块，避免重复发送',
      'reply': '回复结果无法确认，请先检查帖子，避免重复发送',
      'other': '提交结果无法确认，请先检查目标内容，避免重复发送',
    });
    return '$_temp0';
  }

  @override
  String get postingTitle => '发帖';

  @override
  String postingTitleWithForum(String forumName) {
    return '发帖 — $forumName';
  }

  @override
  String get postingSend => '发布';

  @override
  String get postingSubjectHint => '输入标题';

  @override
  String get postingBodyHint => '请输入正文';

  @override
  String get postingFormLoading => '正在加载发帖表单';

  @override
  String postingFormLoadFailed(String error) {
    return '加载发帖表单失败：$error';
  }

  @override
  String get postingType => '主题分类';

  @override
  String get postingTypeRequired => '主题分类（必选）';

  @override
  String get postingTypeNone => '无分类';

  @override
  String get postingTypeUnselected => '未选择';

  @override
  String get postingTags => '主题标签';

  @override
  String get postingTagsHint => '输入标签，回车或英文逗号确认';

  @override
  String get postingTagDelete => '删除标签';

  @override
  String postingTagsLimit(int maxTags, int maxLength) {
    return '最多 $maxTags 个；单个标签 ≤ $maxLength 字符';
  }

  @override
  String get postingNormalThread => '普通帖';

  @override
  String get postingPoll => '投票';

  @override
  String get postingPollConfig => '投票配置';

  @override
  String get postingThreadKind => '帖子类型';

  @override
  String postingPollConstraints(int min, int max, int maxLength) {
    return '至少 $min 个选项；最多 $max 个，单项 ≤ $maxLength 字符';
  }

  @override
  String postingPollSummary(int count, String mode) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已填 $count 项 / $mode',
      zero: '尚未填写选项 / $mode',
    );
    return '$_temp0';
  }

  @override
  String get postingPollSingle => '单选';

  @override
  String get postingPollMultipleMode => '多选';

  @override
  String postingPollOption(int index) {
    return '选项 $index';
  }

  @override
  String get postingPollAddOption => '添加选项';

  @override
  String get postingPollRemoveOption => '删除选项';

  @override
  String get postingPollMultiple => '允许多选';

  @override
  String postingPollMaxChoices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最多可选 $count 项',
      zero: '不可选择选项',
    );
    return '$_temp0';
  }

  @override
  String get postingPollDeadline => '截止天数';

  @override
  String get postingPollNeverExpires => '不限期';

  @override
  String postingPollDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 天',
      zero: '不限期',
    );
    return '$_temp0';
  }

  @override
  String get postingPollPublicVoters => '公开投票人';

  @override
  String get postingPollPublicVotersDescription => '开启后所有人可看到谁投了哪一项';

  @override
  String get postingPollShowResultsAfterVote => '投票后才显示结果';

  @override
  String get postingAllowNoticeAuthor => '允许通知作者';

  @override
  String get postingDisableBbCode => '关闭 BBCode 解析';

  @override
  String get postingDisableSmiley => '关闭表情解析';

  @override
  String get postingDisableUrl => '关闭 URL 解析';

  @override
  String get postingLeaveTitle => '保存草稿并离开？';

  @override
  String get postingLeaveBody => '当前帖子还没有发送，离开前会保存为草稿。';

  @override
  String get postingSubjectRequired => '请输入标题';

  @override
  String get postingBodyRequired => '请输入正文';

  @override
  String get postingFormStillLoading => '发帖表单还在加载，请稍候再试';

  @override
  String postingSubjectTooLong(int limit) {
    return '标题超出版块上限（最多 $limit 字符）';
  }

  @override
  String postingBodyTooLong(int limit) {
    return '正文超出版块上限（最多 $limit 字符）';
  }

  @override
  String get postingPollMissing => '投票配置缺失，请添加选项';

  @override
  String postingPollTooFewOptions(int limit) {
    return '投票至少需要 $limit 个非空选项';
  }

  @override
  String postingPollOptionTooLong(int limit) {
    return '单个投票选项不能超过 $limit 字符';
  }

  @override
  String postingPollMultipleInvalid(int limit) {
    return '多选投票的最大选择数至少为 $limit';
  }

  @override
  String get postingSubmitSuccess => '发布成功';

  @override
  String postingSubmitSuccessWithDetail(String detail) {
    return '发布成功：$detail';
  }

  @override
  String get replyThreadTitle => '回复帖子';

  @override
  String get replyFloorTitle => '回复楼层';

  @override
  String get replySubmit => '发送';

  @override
  String get replyMessageHint => '输入回复内容';

  @override
  String get replyPreparingQuote => '正在准备楼层引用';

  @override
  String replyPreparationFailed(String error) {
    return '楼层回复引用准备失败：$error';
  }

  @override
  String get replyLeaveTitle => '保存草稿并离开？';

  @override
  String get replyLeaveBody => '当前回复还没有发送，离开前会保存为草稿。';

  @override
  String get replyContentRequired => '请输入回复内容';

  @override
  String get replyReferenceUnavailable => '楼层回复引用准备失败，请重试';

  @override
  String get replySubmitSuccess => '回复成功';

  @override
  String replySubmitSuccessWithDetail(String detail) {
    return '回复成功：$detail';
  }

  @override
  String get composerPrototypeTitle => 'Quill Composer 原型';

  @override
  String get composerPrototypeSourceTitle => '源码微调';

  @override
  String composerPrototypeAttachmentInserted(String aid) {
    return '已插入测试附件 $aid';
  }

  @override
  String composerAttachmentFallback(String aid) {
    return '图片 $aid';
  }

  @override
  String get composerLinkUrlHint => 'https://example.com';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonMenu => '菜单';

  @override
  String get commonPreviousPage => '上一页';

  @override
  String get commonNextPage => '下一页';

  @override
  String commonPage(int page) {
    return '第$page页';
  }

  @override
  String commonPageOf(int page, int total) {
    return '第 $page / $total 页';
  }

  @override
  String get commonImageLoading => '图片加载中';

  @override
  String get commonNetworkError => '网络连接失败';

  @override
  String get commonTimeoutError => '请求超时';

  @override
  String get commonUnauthorizedError => '登录状态已失效';

  @override
  String get commonServerError => '服务器暂时不可用';

  @override
  String get commonParseError => '内容解析失败';

  @override
  String get commonRequestError => '请求失败';

  @override
  String get authLoginTitle => '登录';

  @override
  String get authUsername => '用户名';

  @override
  String get authUsernameHint => '请输入论坛账号';

  @override
  String get authPassword => '密码';

  @override
  String get authLoginSuccess => '登录成功';

  @override
  String get authCredentialsRequired => '请输入用户名和密码';

  @override
  String get authLoginTimeout => '登录超时，请检查网络后重试';

  @override
  String get authLoginRejected => '账号或密码错误';

  @override
  String authLoginFailed(String error) {
    return '登录失败：$error';
  }

  @override
  String authLoginWelcome(String username) {
    return '欢迎回来，$username';
  }

  @override
  String authWebViewVerificationFailed(String error) {
    return '登录校验失败：$error';
  }

  @override
  String get appUpdateDialogTitle => '发现新版本';

  @override
  String appUpdateDialogBody(
    String appName,
    String latestVersion,
    String installedVersion,
  ) {
    return '$appName v$latestVersion 已发布，当前版本为 v$installedVersion';
  }

  @override
  String get appUpdateDialogPrompt => '是否立即更新？';

  @override
  String get appUpdateDialogReleaseNotes => '更新说明';

  @override
  String get appUpdateDialogIgnore => '忽略';

  @override
  String get appUpdateDialogLater => '关闭';

  @override
  String get appUpdateDialogUpdate => '更新';

  @override
  String get appUpdateCheck => '检查更新';

  @override
  String get appUpdateVersionLoading => '当前版本：读取中';

  @override
  String appUpdateCurrentVersion(String version) {
    return '当前版本：$version';
  }

  @override
  String get appUpdateUpToDate => '已是最新版本';

  @override
  String get appUpdateReleaseNotesEmpty => '当前版本暂无更新日志';

  @override
  String get appUpdateReleaseNotesUnavailable => '更新日志暂不可用';

  @override
  String get appUpdateDownloadNetworkUnavailable => '网络不可用，无法开始下载更新';

  @override
  String get appUpdateDownloadTimeout => '更新检查超时，请稍后重试';

  @override
  String get appUpdateDownloadInvalid => '当前更新信息无效，请稍后重试';

  @override
  String get appUpdateDownloadInProgress => '更新下载正在进行中，请稍候';

  @override
  String get appUpdateDownloadFailed => '无法开始更新下载，请稍后重试';

  @override
  String get appUpdateCheckNetworkUnavailable => '网络不可用，检查更新失败';

  @override
  String get appUpdateCheckTimeout => '检查更新超时，请稍后重试';

  @override
  String get appUpdateCheckRateLimited => '检查更新过于频繁，请稍后重试';

  @override
  String get appUpdateInstalledVersionUnavailable => '无法读取当前应用版本';

  @override
  String get appUpdateCheckFailed => '检查更新失败，请稍后重试';

  @override
  String get appUpdateInvalidUrl => '更新下载地址无效，请稍后重试';

  @override
  String get appUpdateBrowserUnavailable => '无法打开下载链接，请确认设备已安装浏览器';

  @override
  String get appUpdateOpenUrlFailed => '打开下载链接失败，请稍后重试';

  @override
  String get appUpdateLaunchFailed => '打开更新下载链接失败，请稍后重试';

  @override
  String get searchTitle => '搜索';

  @override
  String get searchInputHint => '输入关键词';

  @override
  String get searchLoadMore => '查看更多';

  @override
  String searchRetryAfter(int seconds) {
    return '请 $seconds 秒后重试';
  }

  @override
  String get searchNoResults => '未找到结果';

  @override
  String searchFailed(String error) {
    return '搜索失败：$error';
  }

  @override
  String searchLoadMoreFailed(String error) {
    return '加载更多失败：$error';
  }

  @override
  String get searchForumFallback => '论坛搜索';

  @override
  String searchQueueWaiting(String subject, String seconds) {
    return '$subject 正在等待搜索，预计 $seconds 秒';
  }

  @override
  String searchResultTid(String tid) {
    return 'TID：$tid';
  }

  @override
  String get tagTitleFallback => '标签';

  @override
  String tagLoadFailed(String error) {
    return '标签页加载失败：$error';
  }

  @override
  String tagRelatedThreads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个相关帖子',
      zero: '暂无相关帖子',
    );
    return '$_temp0';
  }

  @override
  String tagReplies(int count) {
    return '回复 $count';
  }

  @override
  String tagViews(int count) {
    return '查看 $count';
  }

  @override
  String tagLastPost(String value) {
    return '最后发表 $value';
  }

  @override
  String get tagMore => '更多';

  @override
  String get tagEmpty => '暂无相关帖子';

  @override
  String get profileTitle => '个人资料';

  @override
  String get profileMyTitle => '我的资料';

  @override
  String profileUserTitle(String username) {
    return '$username的资料';
  }

  @override
  String get profileHome => '首页';

  @override
  String get profileLoginRequired => '请先登录后查看个人资料';

  @override
  String get profileMyThreads => '我的主题';

  @override
  String get profileMyBlogs => '我的日志';

  @override
  String get profileMyFavorites => '我的收藏';

  @override
  String get profileMessages => '消息提醒';

  @override
  String get profileMyFriends => '我的好友';

  @override
  String get profileDailyCheckIn => '每日签到';

  @override
  String get profileTheirThreads => 'Ta的主题';

  @override
  String get profileTheirBlogs => 'Ta的日志';

  @override
  String get profileSendMessage => '发短消息';

  @override
  String get profileAddFriend => '加为好友';

  @override
  String get profileActionUnavailable => '暂未接入该操作';

  @override
  String get profileSignature => '个人签名';

  @override
  String get profileDetails => '个人资料';

  @override
  String profileLoadFailed(String error) {
    return '资料加载失败：$error';
  }

  @override
  String get profileBlogTitle => '日志';

  @override
  String get profileBlogWrite => '写日志';

  @override
  String get profileBlogWriteUnavailable => '发表新日志暂未接入';

  @override
  String get profileBlogEmpty => '还没有相关的日志';

  @override
  String get profileBlogFriends => '好友的日志';

  @override
  String get profileBlogMine => '我的日志';

  @override
  String get profileBlogExplore => '随便看看';

  @override
  String get profileBlogLatest => '最新发表的日志';

  @override
  String get profileBlogRecommended => '推荐阅读的日志';

  @override
  String get profileBlogComments => '日志评论';

  @override
  String get profileBlogCommentUnavailable => '日志评论提交暂未接入';

  @override
  String get profileBlogComment => '评论';

  @override
  String profileBlogViews(int count) {
    return '浏览 $count';
  }

  @override
  String profileBlogCommentCount(int count) {
    return '评论 $count';
  }

  @override
  String profileBlogLoadFailed(String error) {
    return '日志加载失败：$error';
  }

  @override
  String get profileMessageCenterTitle => '消息提醒';

  @override
  String profileNotificationsTab(int count) {
    return '提醒 $count';
  }

  @override
  String profileMessagesTab(int count) {
    return '消息 $count';
  }

  @override
  String get profileNoNotifications => '暂无提醒';

  @override
  String get profileSystemNotification => '系统提醒';

  @override
  String get profileNoMessages => '暂无消息';

  @override
  String get profilePrivateMessage => '私信';

  @override
  String profileMessageTo(String name) {
    return '发给 $name';
  }

  @override
  String get profileNewBadge => '新';

  @override
  String profileMessagesLoadFailed(String error) {
    return '消息加载失败：$error';
  }

  @override
  String get threadPrototypeTitle => 'HTML 正文渲染原型';

  @override
  String threadPrototypeLoadFailed(String error) {
    return '样例加载失败：$error';
  }

  @override
  String get threadPrototypeEmptyResult => '样例加载失败：结果为空';

  @override
  String threadPrototypeMissingAsset(String sourcePath, String assetPath) {
    return '本地样例未找到，请从 $sourcePath 复制到 $assetPath';
  }

  @override
  String threadPrototypeLink(String url) {
    return '链接：$url';
  }

  @override
  String get threadPrototypeThemeLight => '浅色';

  @override
  String get threadPrototypeThemeDark => '深色';

  @override
  String threadPrototypeJitterCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已复制 $count 条抖动日志',
      zero: '未复制抖动日志',
    );
    return '$_temp0';
  }

  @override
  String threadPrototypeImageOpened(int postNumber, int index) {
    return '$postNumber# 图片：$index';
  }

  @override
  String get threadPrototypeActionUnsupported => '原型页暂不执行该帖子操作';

  @override
  String get threadPrototypeJitterTitle => '记录抖动日志';

  @override
  String get threadPrototypeJitterRecording => '记录中，关闭后复制日志';

  @override
  String threadPrototypeJitterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已记录 $count 条',
      zero: '尚未记录',
    );
    return '$_temp0';
  }

  @override
  String get threadPrototypeCopyLog => '复制日志';

  @override
  String get threadPrototypeThreadSummarySemantics => 'HTML 原型帖子样例摘要';

  @override
  String get threadPrototypeSummarySemantics => 'HTML 原型样例摘要';

  @override
  String threadPrototypeSample(String sample) {
    return '样例：$sample';
  }

  @override
  String threadPrototypeThread(String subject) {
    return '帖子：$subject';
  }

  @override
  String threadPrototypePage(int page, String total) {
    return '页码：$page/$total';
  }

  @override
  String threadPrototypePosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '楼层：$count 个',
      zero: '楼层：0 个',
    );
    return '$_temp0';
  }

  @override
  String threadPrototypeConversionMode(String mode) {
    return '转换模式：$mode';
  }

  @override
  String threadPrototypeConverter(String converterId) {
    return '转换器：$converterId';
  }

  @override
  String threadPrototypeConvertedNodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '转换文本节点：$count 个',
      zero: '转换文本节点：0 个',
    );
    return '$_temp0';
  }

  @override
  String threadPrototypePreviewTheme(String theme) {
    return '预览主题：$theme';
  }

  @override
  String threadPrototypeTypography(int fontScale, String lineHeight) {
    return '字号 $fontScale% / 间隔 $lineHeight×';
  }

  @override
  String threadPrototypeThemeAdaptation(String authorFontMode) {
    String _temp0 = intl.Intl.selectLogic(authorFontMode, {
      'preserved': '主题适配：始终启用 / 作者字号保留',
      'unified': '主题适配：始终启用 / 作者字号统一',
      'other': '主题适配：始终启用',
    });
    return '$_temp0';
  }

  @override
  String threadPrototypeRawHtmlLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '原 HTML：$count 字符',
      zero: '原 HTML：0 字符',
    );
    return '$_temp0';
  }

  @override
  String threadPrototypeFragmentLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '正文 fragment：$count 字符',
      zero: '正文 fragment：0 字符',
    );
    return '$_temp0';
  }

  @override
  String threadPrototypeAdaptedColors(
    int remappedForeground,
    int explicitForeground,
    int remappedBackground,
    int explicitBackground,
  ) {
    return '适配前景：$remappedForeground/$explicitForeground · 适配背景：$remappedBackground/$explicitBackground';
  }

  @override
  String threadPrototypeAdaptationFallbacks(
    int semanticFallback,
    int unsupported,
    int concealed,
  ) {
    return '语义回退：$semanticFallback · 不支持：$unsupported · 隐藏：$concealed';
  }

  @override
  String threadPrototypeMinimumContrast(String value) {
    return '最低可见对比度：$value';
  }

  @override
  String get postEditTitle => '编辑帖子';

  @override
  String get postEditMessageHint => '帖子内容';

  @override
  String get postEditSave => '保存';

  @override
  String get postEditSwitchToWebView => '切换到网页编辑';

  @override
  String get postEditSwitchToNative => '返回原生编辑';

  @override
  String get postEditConflictTitle => '服务器内容已变化';

  @override
  String get postEditConflictBody => '网页编辑或其他设备已经修改了这条帖子，请选择要保留的版本。';

  @override
  String get postEditUseServer => '使用服务器版本';

  @override
  String get postEditKeepLocal => '保留本地版本';

  @override
  String get postEditVerificationFailed => '无法确认网页编辑后的服务器状态，原生保存暂不可用。';

  @override
  String get postEditNativeSubmitUnavailable => '原生保存将在后续版本开放';

  @override
  String get postEditManageImages => '管理图片';

  @override
  String get postEditNoImages => '当前编辑没有图片';

  @override
  String get postEditDeleteImage => '删除图片';

  @override
  String get postEditDeleteImageTitle => '删除这张图片？';

  @override
  String get postEditDeleteImageBody => '这会删除服务器上的图片，但不会删除正文中的图片代码。';

  @override
  String get postEditDeleteImageConfirm => '确认删除';

  @override
  String get postEditDeleteImageFailed => '图片删除未成功，图片仍保留。';

  @override
  String get postEditDeleteImageUnconfirmed => '无法确认图片删除状态，请稍后重试。';

  @override
  String get postEditAttachmentDeleting => '正在删除图片';

  @override
  String get postEditDeletedImageReferenceWarning => '正文仍包含已删除图片代码。';

  @override
  String get postEditSubmitInProgress => '正在保存帖子内容…';

  @override
  String get postEditDanglingAttachmentTitle => '正文包含无法确认的图片引用';

  @override
  String get postEditDanglingAttachmentBody =>
      '部分图片引用无法关联到当前可用附件，仍要继续保存吗？正文不会被自动修改。';

  @override
  String get postEditDanglingAttachmentConfirm => '继续保存';

  @override
  String get postEditPartialSuccess => '正文已保存，但部分新图片未能确认关联，请检查后再试。';

  @override
  String get postEditSubmitUnconfirmed => '保存结果未确认，已暂时停用原生保存。请重新验证服务器版本。';

  @override
  String get postEditRetryVerification => '重新验证';

  @override
  String get postEditFormExpired => '编辑表单已过期，正在重新获取后重试一次。';

  @override
  String get postEditPermissionDenied => '没有权限保存此帖子。';

  @override
  String get postEditAuthenticationRequired => '登录状态已失效，请重新登录后再试。';

  @override
  String get postEditSubmitFailed => '帖子保存失败，当前内容已保留。';

  @override
  String postEditLoadFailed(String error) {
    return '读取帖子编辑表单失败：$error';
  }

  @override
  String get postEditServerVersion => '服务器版本';

  @override
  String get postEditLocalVersion => '本地版本';
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
  String get commonApply => '套用';

  @override
  String get commonSave => '儲存';

  @override
  String get commonDelete => '刪除';

  @override
  String get commonRemove => '移除';

  @override
  String get commonUnknownError => '未知錯誤';

  @override
  String get networkSecurityVerificationTitle => '安全驗證';

  @override
  String get networkSecurityVerificationPreparing => '正在完成網站安全驗證…';

  @override
  String get networkSecurityVerificationFailed => '安全驗證未完成，請重試';

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
  String get forumRefreshPage => '重新整理頁面';

  @override
  String get forumWebViewBackHome => '返回首頁';

  @override
  String get forumWebViewFeatureInProgress => '功能開發中';

  @override
  String get forumProcessing => '處理中';

  @override
  String get forumFavoriteForum => '收藏本版';

  @override
  String get forumUnfavoriteForum => '取消收藏';

  @override
  String get forumFavoriteSuccess => '已收藏本版';

  @override
  String get forumUnfavoriteSuccess => '已取消收藏本版';

  @override
  String forumActionFailed(String error) {
    return '操作失敗，請稍後重試：$error';
  }

  @override
  String get forumFavoriteForumsTitle => '取消收藏';

  @override
  String forumFavoriteForumsLoadFailed(String error) {
    return '載入收藏版塊失敗：$error';
  }

  @override
  String get forumNoFavoriteForums => '目前沒有收藏版塊';

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
  String forumForumByFid(String fid) {
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
  String librarySelectionSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已選 $count 項',
      zero: '未選擇項目',
    );
    return '$_temp0';
  }

  @override
  String get librarySelectionExit => '退出多選';

  @override
  String get librarySelectionSelectAll => '全選目前分類';

  @override
  String get librarySelectionInvert => '反選目前分類';

  @override
  String get librarySelectionActionAssignCategory => '設定分類';

  @override
  String get librarySelectionActionMarkAllRead => '全部已讀';

  @override
  String get librarySelectionActionMarkAllUnread => '全部未讀';

  @override
  String get librarySelectionActionDownload => '下載';

  @override
  String get librarySelectionActionUnfavorite => '取消收藏';

  @override
  String get librarySelectionActionGeneric => '執行操作';

  @override
  String librarySelectionActionFailed(String error) {
    return '批次操作失敗：$error';
  }

  @override
  String get librarySelectionConfirmUnfavoriteTitle => '確認取消收藏';

  @override
  String get librarySelectionConfirmActionTitle => '確認執行操作';

  @override
  String librarySelectionConfirmUnfavoriteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項',
      zero: '0 項',
    );
    return '將取消已選 $_temp0收藏。若作品已無其他活躍收藏來源，相關本機作品、章節、封面快取和下載也會被清除。是否繼續？';
  }

  @override
  String librarySelectionConfirmActionBody(int count, String action) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項',
      zero: '0 項',
    );
    return '將對已選 $_temp0執行「$action」，是否繼續？';
  }

  @override
  String get librarySelectionSelectCategory => '選擇分類';

  @override
  String get librarySelectionCreateCategory => '新增分類';

  @override
  String get librarySelectionCategoryNameHint => '請輸入分類名稱';

  @override
  String librarySelectionCategoryAssigned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已為 $count 項設定分類',
      zero: '沒有項目設定分類',
    );
    return '$_temp0';
  }

  @override
  String librarySelectionCategoryAssignedPartial(
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
  String librarySelectionReadStateChanged(int count, String state) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項',
      zero: '0 項',
    );
    return '已將 $_temp0標記為$state';
  }

  @override
  String librarySelectionReadStateChangedPartial(
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
  String get librarySelectionRead => '已讀';

  @override
  String get librarySelectionUnread => '未讀';

  @override
  String librarySelectionDownloadQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個章節',
      zero: '0 個章節',
    );
    return '已將 $_temp0加入下載佇列';
  }

  @override
  String librarySelectionDownloadQueuedPartial(int count, int failedCount) {
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
  String get librarySelectionDownloadAlreadyQueued => '所選章節已在下載佇列中';

  @override
  String get librarySelectionNothingToDownload => '沒有需要下載的章節';

  @override
  String librarySelectionUnfavorite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項',
      zero: '0 項',
    );
    return '已取消 $_temp0收藏';
  }

  @override
  String librarySelectionUnfavoritePartial(
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
  String librarySelectionUnsupported(String action) {
    return '目前不支援批次$action';
  }

  @override
  String get librarySelectionMissingTargetCategory => '請選擇目標分類';

  @override
  String get librarySelectionNoValidItems => '沒有可處理的項目';

  @override
  String librarySelectionNoChange(String action) {
    return '沒有可執行的$action';
  }

  @override
  String libraryShelfTitle(String module) {
    String _temp0 = intl.Intl.selectLogic(module, {
      'comic': '漫畫',
      'novel': '小說',
      'favorite': '收藏',
      'other': '書架',
    });
    return '$_temp0';
  }

  @override
  String libraryShelfLoadFailed(String error) {
    return '載入書架失敗：$error';
  }

  @override
  String get libraryShelfEmpty => '書架為空';

  @override
  String get libraryShelfSearch => '搜尋書架';

  @override
  String get libraryShelfSearchHint => '搜尋作品';

  @override
  String get libraryShelfFilterAndSort => '篩選與排序';

  @override
  String get libraryShelfCreateCategory => '新增分類';

  @override
  String get libraryShelfRenameCategory => '重新命名目前分類';

  @override
  String get libraryShelfDeleteCategory => '刪除目前分類';

  @override
  String get libraryShelfDeleteCategoryTitle => '刪除分類';

  @override
  String get libraryShelfDeleteCategoryBody => '刪除後，此分類中的作品會移至預設分類。是否繼續？';

  @override
  String get libraryShelfDefaultCategory => '預設';

  @override
  String get libraryShelfDefaultCategoryCannotRename => '預設分類不支援重新命名';

  @override
  String get libraryShelfDefaultCategoryCannotDelete => '預設分類不支援刪除';

  @override
  String get libraryShelfCategoryNameHint => '請輸入分類名稱';

  @override
  String libraryShelfCategoryMatchCount(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: '0',
    );
    return '$name $_temp0';
  }

  @override
  String get libraryShelfUpdate => '更新書架';

  @override
  String get libraryShelfRandomOpen => '隨機開啟作品';

  @override
  String get libraryShelfNoRandomWork => '目前分類沒有可開啟的作品';

  @override
  String get libraryShelfFilter => '篩選';

  @override
  String get libraryShelfSort => '排序';

  @override
  String get libraryShelfDisplayMode => '顯示';

  @override
  String get libraryShelfGrid => '網格';

  @override
  String get libraryShelfList => '列表';

  @override
  String get libraryShelfColumnsPerRow => '每列數量';

  @override
  String get libraryShelfFilterDownloaded => '已下載';

  @override
  String get libraryShelfFilterUnread => '未讀';

  @override
  String get libraryShelfFilterRead => '讀過';

  @override
  String get libraryShelfFilterBookmarked => '有書籤';

  @override
  String get libraryShelfSortName => '名稱';

  @override
  String get libraryShelfSortChapterCount => '章節數';

  @override
  String get libraryShelfSortLastReadAt => '最近閱讀';

  @override
  String get libraryShelfSortLastCheckedAt => '最近檢查';

  @override
  String get libraryShelfSortUnreadCount => '未讀章節數';

  @override
  String get libraryShelfSortWorkUpdatedAt => '作品更新時間';

  @override
  String get libraryShelfSortFetchedAt => '取得時間';

  @override
  String get libraryShelfSortFavoriteAddedAt => '收藏日期';

  @override
  String get libraryShelfMergeDuplicates => '合併重複項目';

  @override
  String libraryShelfMergeDuplicatesSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個重複作品',
      zero: '0 個重複作品',
    );
    return '已合併 $_temp0';
  }

  @override
  String get libraryShelfMergeDuplicatesNoChange => '沒有可合併的重複作品';

  @override
  String get libraryShelfActionUnsupported => '目前書架不支援此操作';

  @override
  String get libraryTaskCoverWarmup => '正在準備封面';

  @override
  String get libraryTaskFavoriteSyncFetching => '正在取得收藏列表';

  @override
  String get libraryTaskFavoriteSyncSaving => '正在儲存收藏資料';

  @override
  String get libraryTaskFavoriteSyncLoadingDetails => '正在讀取收藏詳情';

  @override
  String libraryTaskFavoriteSyncLoadingDetailsSubject(String subject) {
    return '正在讀取《$subject》';
  }

  @override
  String get libraryTaskFavoriteSyncFinishing => '正在完成收藏同步';

  @override
  String get libraryTaskComicSearchWaiting => '漫畫搜尋正在等待';

  @override
  String libraryTaskComicSearchWaitingSubject(String subject) {
    return '《$subject》正在等待搜尋';
  }

  @override
  String libraryTaskComicSearchWaitingDuration(
    String subject,
    String duration,
  ) {
    return '《$subject》正在等待搜尋，預計 $duration';
  }

  @override
  String libraryTaskDurationSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 秒',
      one: '1 秒',
    );
    return '$_temp0';
  }

  @override
  String libraryTaskDurationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 分鐘',
      one: '1 分鐘',
    );
    return '$_temp0';
  }

  @override
  String get libraryTaskFavoriteSyncNotificationTitle => '收藏同步';

  @override
  String get libraryTaskComicSearchNotificationTitle => '漫畫搜尋';

  @override
  String get libraryTaskNotificationTitle => '書架工作';

  @override
  String get libraryDetailDownload => '下載';

  @override
  String get libraryDetailFilterAndSort => '篩選與排序';

  @override
  String get libraryDetailRefresh => '重新整理';

  @override
  String get libraryDetailChangeCategory => '修改分類';

  @override
  String get libraryDetailEditMetadata => '編輯作品資訊';

  @override
  String get libraryDetailConfigureCatalog => '設定目錄';

  @override
  String get libraryDetailManageChapters => '管理章節';

  @override
  String get libraryDetailSetCustomCover => '自訂封面';

  @override
  String get libraryDetailRemoveCustomCover => '取消封面';

  @override
  String get libraryDetailEditIntro => '編輯簡介';

  @override
  String get libraryDetailIntroHint => '請輸入簡介';

  @override
  String get libraryDetailNoIntro => '目前沒有簡介';

  @override
  String get libraryDetailContinue => '繼續';

  @override
  String get libraryDetailIntro => '簡介';

  @override
  String libraryDetailLoadFailed(String error) {
    return '載入詳情失敗：$error';
  }

  @override
  String get libraryDetailInShelf => '已在書架中';

  @override
  String get libraryDetailAddToShelf => '加入書架';

  @override
  String get libraryDetailUpdate => '更新';

  @override
  String get libraryDetailSourceThread => '原帖';

  @override
  String get libraryDetailNoNovelCover => '小說無封面';

  @override
  String get libraryDetailAuthor => '作者';

  @override
  String get libraryDetailTranslator => '翻譯者';

  @override
  String get libraryDetailTranslationGroup => '漢化組';

  @override
  String get libraryDetailPublisher => '發布者';

  @override
  String libraryDetailMetadataSemantics(String label, String value) {
    return '$label：$value';
  }

  @override
  String get libraryDetailDownloadUnread => '下載未讀章節';

  @override
  String get libraryDetailDownloadAll => '下載全部章節';

  @override
  String libraryDetailDeleteDownloadFailed(String error) {
    return '刪除下載失敗：$error';
  }

  @override
  String libraryDetailDownloadFailed(String error) {
    return '下載失敗：$error';
  }

  @override
  String get libraryDetailReadStateUpdateFailed => '閱讀狀態更新失敗';

  @override
  String get libraryDetailAllChapters => '全部章節';

  @override
  String get libraryDetailDownloaded => '已下載';

  @override
  String get libraryDetailUnread => '未讀';

  @override
  String get libraryDetailBookmarked => '已加書籤';

  @override
  String libraryDetailExcludeFilter(String label) {
    return '排除$label';
  }

  @override
  String get libraryDetailFilter => '篩選';

  @override
  String get libraryDetailSort => '排序';

  @override
  String get libraryDetailSortBySource => '依來源';

  @override
  String get libraryDetailAddBookmark => '加入書籤';

  @override
  String get libraryDetailRemoveBookmark => '移除書籤';

  @override
  String get libraryDetailResetWorkReading => '重設本作品閱讀狀態';

  @override
  String get libraryDetailDeleteChapterDownload => '刪除此章節下載';

  @override
  String get libraryDetailResetReadingTitle => '重設本作品閱讀狀態？';

  @override
  String get libraryDetailResetReadingBody =>
      '全部章節將變為未讀，所有閱讀進度和上次閱讀位置都會被清除。書籤和下載不受影響。';

  @override
  String get libraryDetailResetReadingConfirm => '重設';

  @override
  String get libraryDetailResetReadingFailed => '重設作品閱讀狀態失敗';

  @override
  String libraryDetailRefreshFailed(String error) {
    return '更新失敗：$error';
  }

  @override
  String get libraryDetailRefreshUpdated => '已更新';

  @override
  String libraryDetailRefreshChaptersChanged(
    int insertedCount,
    int updatedCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      insertedCount,
      locale: localeName,
      other: '已新增 $insertedCount 章',
      zero: '未新增章節',
    );
    String _temp1 = intl.Intl.pluralLogic(
      updatedCount,
      locale: localeName,
      other: '更新 $updatedCount 章',
      zero: '未更新章節',
    );
    return '$_temp0，$_temp1';
  }

  @override
  String get libraryDetailRefreshAlreadyCurrent => '已是最新章節';

  @override
  String get libraryDetailRefreshNoUpdates => '未發現新章節';

  @override
  String libraryDetailRefreshQueued(String duration) {
    return '已加入更新佇列，預計 $duration';
  }

  @override
  String libraryDetailRefreshQueuedAtPosition(int position, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      position,
      locale: localeName,
      other: '有 $position 個工作',
      zero: '沒有等待工作',
    );
    return '已加入更新佇列，前方 $_temp0，預計 $duration';
  }

  @override
  String get libraryDetailRefreshUnavailable => '目前沒有可更新的內容';

  @override
  String libraryDetailCatalogLoadFailed(String error) {
    return '讀取目錄設定失敗：$error';
  }

  @override
  String get libraryDetailMetadataTitle => '標題';

  @override
  String get libraryDetailMetadataSearchTitle => '更新搜尋關鍵字';

  @override
  String get libraryDetailMetadataSearchHelp => '留空時優先使用自訂標題，否則使用目前作品標題';

  @override
  String get libraryDetailMetadataSourceTitle => '來源標題';

  @override
  String get libraryDetailMetadataSourceAuthor => '來源作者';

  @override
  String get libraryDetailMetadataSourceTranslationGroup => '來源漢化組';

  @override
  String libraryDetailSourceValue(String label, String value) {
    return '$label：$value';
  }

  @override
  String libraryDetailSourceEmpty(String label) {
    return '$label：無';
  }

  @override
  String get libraryDetailCatalogUrl => '目錄 URL';

  @override
  String libraryDetailCatalogSource(String url) {
    return '來源目錄：$url';
  }

  @override
  String get libraryDetailCatalogSourceEmpty => '來源目錄：無';

  @override
  String libraryDetailCatalogSaveFailed(String error) {
    return '儲存失敗：$error';
  }

  @override
  String get libraryDetailCatalogInvalidUrl => '請輸入有效的目錄 URL';

  @override
  String get libraryDetailCatalogIncompleteUrl => '目錄 URL 不完整';

  @override
  String get libraryDetailCatalogUnsupportedScheme => '目錄 URL 僅支援 HTTP 或 HTTPS';

  @override
  String libraryDetailCatalogUnexpectedHost(String host) {
    return '目錄 URL 必須來自 $host';
  }

  @override
  String get libraryDetailCatalogNotTagCatalog => '請輸入標籤目錄頁面的 URL';

  @override
  String libraryDetailCoverUpdateFailed(String error) {
    return '封面更新失敗：$error';
  }

  @override
  String get libraryDetailCoverUpdated => '封面已更新';

  @override
  String libraryDetailCoverRemoveFailed(String error) {
    return '取消封面失敗：$error';
  }

  @override
  String get libraryDetailCoverRemoved => '已取消封面';

  @override
  String libraryChapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '共 $count 章',
      zero: '共 0 章',
    );
    return '$_temp0';
  }

  @override
  String libraryChapterFallbackTitle(String tid) {
    return '章節 $tid';
  }

  @override
  String get libraryChapterBookmarkSemantics => '已加入書籤';

  @override
  String get libraryChapterDownloading => '正在下載';

  @override
  String get libraryChapterDownloadedDelete => '已下載，點擊刪除下載';

  @override
  String get libraryChapterDownload => '下載此章節';

  @override
  String get libraryChapterClearReadState => '清除閱讀狀態';

  @override
  String get libraryChapterMarkRead => '標記為已讀';

  @override
  String libraryChapterCurrentPage(int page) {
    return '第 $page 頁';
  }

  @override
  String get libraryChapterLastRead => '上次閱讀';

  @override
  String libraryChapterProgressSemantics(String subtitle, String progress) {
    return '$subtitle，$progress';
  }

  @override
  String get libraryChapterFilterAny => '不限';

  @override
  String libraryChapterFilterOnly(String label) {
    return '只看$label';
  }

  @override
  String libraryChapterFilterExclude(String label) {
    return '排除$label';
  }

  @override
  String get libraryChapterManagementLoading => '正在讀取章節';

  @override
  String libraryChapterManagementSummary(
    int total,
    int parsed,
    int manual,
    int hidden,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '共 $total 章',
      zero: '共 0 章',
    );
    String _temp1 = intl.Intl.pluralLogic(
      parsed,
      locale: localeName,
      other: '解析 $parsed 章',
      zero: '解析 0 章',
    );
    String _temp2 = intl.Intl.pluralLogic(
      manual,
      locale: localeName,
      other: '手動 $manual 章',
      zero: '手動 0 章',
    );
    String _temp3 = intl.Intl.pluralLogic(
      hidden,
      locale: localeName,
      other: '隱藏 $hidden 章',
      zero: '隱藏 0 章',
    );
    return '$_temp0 · $_temp1 · $_temp2 · $_temp3';
  }

  @override
  String get libraryChapterFilterLabel => '篩選章節';

  @override
  String get libraryChapterFilterHint => '依標題或 TID 搜尋';

  @override
  String get libraryChapterClearFilter => '清除篩選';

  @override
  String get libraryChapterAdd => '新增章節';

  @override
  String get libraryChapterAddHint => '貼上帖子連結或直接輸入 TID';

  @override
  String get libraryChapterAddHelp =>
      '支援 forum.php、thread-xxx.html、api/mobile 等連結形式';

  @override
  String get libraryChapterManagementEmpty => '目前沒有章節，可在上方貼上帖子連結手動新增';

  @override
  String get libraryChapterManagementNoMatches => '沒有符合的章節';

  @override
  String get libraryChapterShow => '顯示此章節';

  @override
  String get libraryChapterHide => '隱藏此章節';

  @override
  String get libraryChapterHidden => '已隱藏';

  @override
  String get libraryChapterKeepOneVisible => '至少保留一個可見章節';

  @override
  String get libraryChapterRename => '重新命名此章節';

  @override
  String get libraryChapterRemove => '移除此章節';

  @override
  String get libraryChapterAdded => '已新增章節';

  @override
  String get libraryChapterDuplicate => '此章節已存在';

  @override
  String libraryChapterAddFailed(String error) {
    return '新增失敗：$error';
  }

  @override
  String get libraryChapterInputEmpty => '請輸入帖子連結或 TID';

  @override
  String get libraryChapterInputInvalidUrl => '請輸入有效的帖子連結或 TID';

  @override
  String get libraryChapterInputUnsupportedScheme => '帖子連結僅支援 HTTP 或 HTTPS';

  @override
  String libraryChapterInputUnexpectedHost(String host) {
    return '帖子連結必須來自 $host';
  }

  @override
  String get libraryChapterInputUnsupportedThreadUrl => '不支援此帖子連結形式';

  @override
  String get libraryChapterInputMissingTid => '帖子連結中缺少有效的 TID';

  @override
  String libraryChapterVisibilityUpdateFailed(String error) {
    return '更新顯示狀態失敗：$error';
  }

  @override
  String get libraryChapterRestoredSourceTitle => '已恢復來源章節名';

  @override
  String get libraryChapterRenamed => '已重新命名章節';

  @override
  String libraryChapterRenameFailed(String error) {
    return '重新命名失敗：$error';
  }

  @override
  String get libraryChapterRemoveTitle => '移除此章節？';

  @override
  String libraryChapterRemoveBody(String title) {
    return '將刪除手動新增的「$title」及其閱讀記錄與下載工作，此操作無法復原。';
  }

  @override
  String get libraryChapterParsedCannotRemove => '解析章節不可移除，可改為隱藏';

  @override
  String get libraryChapterRemoved => '已移除章節';

  @override
  String libraryChapterRemovedWithWarnings(String warnings) {
    return '章節已移除，但$warnings';
  }

  @override
  String get libraryChapterDownloadTaskCleanupFailed => '下載工作清理失敗';

  @override
  String get libraryChapterDownloadFileCleanupFailed => '章節下載檔案清理失敗';

  @override
  String libraryChapterRemoveFailed(String error) {
    return '移除失敗：$error';
  }

  @override
  String get libraryChapterRenameTitle => '重新命名章節';

  @override
  String get libraryChapterName => '章節名';

  @override
  String get libraryChapterRestoreDefaultTitleHelp => '留空以恢復預設章節名';

  @override
  String libraryChapterRestoreSourceTitleHelp(String title) {
    return '留空以恢復來源章節名：$title';
  }

  @override
  String get libraryChapterManual => '手動';

  @override
  String get libraryChapterParsed => '解析';

  @override
  String libraryChapterLoadFailed(String error) {
    return '讀取章節失敗：$error';
  }

  @override
  String get libraryCoverFocalTitle => '調整封面焦點';

  @override
  String get libraryCoverFocalHelp => '拖曳選框以選擇封面取景區域，原圖不會被裁切';

  @override
  String get libraryCoverImageLoadFailed => '圖片載入失敗';

  @override
  String get libraryCoverCenter => '置中';

  @override
  String get libraryErrorRedactedLink => '[連結已隱藏]';

  @override
  String get libraryErrorRedactedSecret => '[敏感資訊已隱藏]';

  @override
  String get readerBack => '返回';

  @override
  String get readerPrevious => '上一章';

  @override
  String get readerNext => '下一章';

  @override
  String readerSelectedSemantics(String label) {
    return '$label，已選取';
  }

  @override
  String readerProgressSemantics(String current, String total) {
    return '閱讀進度：$current / $total';
  }

  @override
  String get readerModeVertical => '垂直';

  @override
  String get readerModeLtr => '由左至右';

  @override
  String get readerModeRtl => '由右至左';

  @override
  String get readerModeVerticalContinuous => '垂直連續';

  @override
  String get readerModeSingleLtr => '單頁 由左至右';

  @override
  String get readerModeSingleRtl => '單頁 由右至左';

  @override
  String get readerDisplaySettings => '顯示設定';

  @override
  String get readerReadingMode => '閱讀模式';

  @override
  String get readerPageFit => '頁面適配';

  @override
  String get readerPageFitWidth => '寬度';

  @override
  String get readerPageFitHeight => '高度';

  @override
  String get readerPageFitContain => '螢幕';

  @override
  String get readerBackground => '背景色';

  @override
  String get readerBackgroundTheme => '主題';

  @override
  String get readerBackgroundBlack => '黑';

  @override
  String get readerBackgroundWhite => '白';

  @override
  String get readerBackgroundGray => '灰';

  @override
  String get readerPageSpacing => '頁間距';

  @override
  String get readerPageIndicator => '頁碼浮層';

  @override
  String get readerNoImages => '沒有可閱讀圖片';

  @override
  String get readerImageLoadFailed => '圖片載入失敗';

  @override
  String get readerTailContent => '末尾內容';

  @override
  String get readerContinue => '繼續';

  @override
  String get readerDownloadUnsupported => '目前圖片不支援下載';

  @override
  String get readerExportSaving => '正在儲存目前圖片';

  @override
  String readerExportSaved(String destination) {
    return '已儲存到$destination';
  }

  @override
  String get readerExportDefaultDestination => '系統照片';

  @override
  String get readerExportCacheUnavailable => '圖片暫不可用，請重試';

  @override
  String get readerExportPermissionDenied => '沒有照片圖庫寫入權限，請在系統設定中允許';

  @override
  String get readerExportPermissionRestricted => '照片圖庫權限受系統限制';

  @override
  String get readerExportUnsupportedPlatform => '目前平台不支援儲存圖片';

  @override
  String get readerExportUnsupportedFormat => '目前圖片格式不支援儲存';

  @override
  String get readerExportFailed => '儲存圖片失敗，請重試';

  @override
  String comicUntitledWork(String workId) {
    return '未命名漫畫（$workId）';
  }

  @override
  String comicChapterFallbackTitle(String sourceTid) {
    return '章節 $sourceTid';
  }

  @override
  String get comicAddToShelf => '加入書架';

  @override
  String get comicAlreadyInShelf => '已在書架';

  @override
  String get comicNoImages => '目前章節沒有可閱讀圖片';

  @override
  String comicReaderLoadFailed(String error) {
    return '載入閱讀器失敗：$error';
  }

  @override
  String get comicReaderNetworkFailure => '網路異常，請檢查後重試';

  @override
  String get comicReaderAuthFailure => '登入狀態已失效，請重新登入後重試';

  @override
  String get comicReaderServerFailure => '服務暫時不可用，請稍後重試';

  @override
  String get comicReaderParseFailure => '頁面結構異常，無法解析章節內容';

  @override
  String get comicReaderUnknownFailure => '載入章節失敗';

  @override
  String get comicReaderEpisodeUnavailable => '章節不存在或已被移除';

  @override
  String get comicBookmarkAdd => '新增書籤';

  @override
  String get comicBookmarkRemove => '取消書籤';

  @override
  String get comicBookmarkAdded => '已新增書籤';

  @override
  String get comicBookmarkRemoved => '已移除書籤';

  @override
  String get comicOpenSourceThread => '開啟原帖';

  @override
  String get comicMoreActions => '更多操作';

  @override
  String get comicReaderRefreshEpisode => '重新整理章節';

  @override
  String get comicReaderEpisodeRefreshed => '章節已重新整理';

  @override
  String get comicReaderRefreshFailed => '重新整理章節失敗，已保留目前內容';

  @override
  String get comicReaderRefreshNoImages => '未解析到圖片，已保留目前章節';

  @override
  String get comicMore => '更多';

  @override
  String get comicChapterList => '章節列表';

  @override
  String get comicChapterAction => '章節';

  @override
  String get comicCurrentChapter => '目前';

  @override
  String get comicDisplay => '顯示';

  @override
  String get comicDownloadCurrentImage => '下載目前圖片';

  @override
  String get comicPreviousEpisode => '上一話';

  @override
  String get comicNextEpisode => '下一話';

  @override
  String get comicFirstEpisode => '已是第一話';

  @override
  String get comicLastEpisode => '已是最後一話';

  @override
  String get comicMarkEpisodeRead => '標記本章已讀';

  @override
  String get comicMarkEpisodeUnread => '標記本章未讀';

  @override
  String get comicEpisodeMarkedRead => '已標記本章已讀';

  @override
  String get comicEpisodeMarkedUnread => '已標記本章未讀';

  @override
  String get comicSetCurrentPageCover => '將目前頁設為封面';

  @override
  String get comicCoverImageUnavailable => '目前頁圖片暫不可用，無法設為封面';

  @override
  String get comicCoverUpdateFailed => '封面更新失敗';

  @override
  String get comicCoverUpdated => '封面已更新';

  @override
  String get comicEpisodeSwitchFailed => '章節切換失敗，已保留目前章節';

  @override
  String get comicSetCoverFocus => '調整封面焦點';

  @override
  String comicNextChapterTitle(String title) {
    return '下一章：$title';
  }

  @override
  String get comicSwitchingEpisode => '正在切換章節';

  @override
  String get comicOpenNextEpisode => '點擊進入下一章';

  @override
  String get comicOpeningEpisode => '正在開啟章節';

  @override
  String get comicRefreshNoNewLinks => '未提取到新的章節連結';

  @override
  String comicRefreshCompleted(int insertedCount, int updatedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      insertedCount,
      locale: localeName,
      other: '$insertedCount',
      zero: '0',
    );
    String _temp1 = intl.Intl.pluralLogic(
      updatedCount,
      locale: localeName,
      other: '$updatedCount',
      zero: '0',
    );
    return '章節重新整理完成：新增 $_temp0，更新 $_temp1';
  }

  @override
  String comicRefreshFailed(String error) {
    return '重新整理章節失敗：$error';
  }

  @override
  String get comicComment => '評論';

  @override
  String get comicCommentLoading => '評論載入中';

  @override
  String get comicCommentEmpty => '暫無評論';

  @override
  String get comicCommentUnavailable => '評論暫不可用';

  @override
  String get comicCommentOpen => '查看評論';

  @override
  String get comicCommentUnavailableFeedback => '無法查看評論';

  @override
  String get comicCommentContinue => '繼續滑動進入下一章';

  @override
  String comicCommentContinueTo(String title) {
    return '繼續滑動進入：$title';
  }

  @override
  String get comicDownloadQueue => '下載佇列';

  @override
  String get comicDownloadQueueEmpty => '暫無下載任務';

  @override
  String get comicDownloadActive => '正在下載';

  @override
  String get comicDownloadPending => '等待中';

  @override
  String get comicDownloadFailedSection => '下載失敗';

  @override
  String get comicDownloadCanceling => '正在取消';

  @override
  String get comicDownloadCancel => '取消下載';

  @override
  String get comicDownloadRemove => '移除任務';

  @override
  String get comicDownloadRetry => '重試';

  @override
  String comicDownloadQueuePosition(String episodeTitle, int position) {
    return '$episodeTitle · 第 $position 位';
  }

  @override
  String comicDownloadFailureDetail(String episodeTitle, String error) {
    return '$episodeTitle · $error';
  }

  @override
  String get comicDownloadResolvingImages => '正在解析圖片';

  @override
  String comicDownloadProgress(int completed, int total) {
    return '$completed/$total';
  }

  @override
  String comicDownloadCancelFailed(String error) {
    return '取消下載失敗：$error';
  }

  @override
  String comicDownloadRemoveFailed(String error) {
    return '移除任務失敗：$error';
  }

  @override
  String comicDownloadRetryFailed(String error) {
    return '重試失敗：$error';
  }

  @override
  String get comicDownloadWorkUnavailable => '漫畫作品不存在或已被移除';

  @override
  String get comicDownloadEpisodeUnavailable => '漫畫章節不存在或已被移除';

  @override
  String get comicDownloadNoImages => '章節沒有可下載圖片';

  @override
  String get comicDownloadImageFailed => '部分圖片下載失敗';

  @override
  String get comicDownloadStorageFailed => '下載檔案儲存失敗';

  @override
  String get comicDownloadUnknownFailure => '下載失敗，請重試';

  @override
  String novelUntitledWork(String novelId) {
    return '未命名小說（$novelId）';
  }

  @override
  String novelChapterFallbackTitle(String sourceTid) {
    return '章節 $sourceTid';
  }

  @override
  String get novelOriginalBadge => '原創';

  @override
  String get novelOpenInReader => '閱讀器';

  @override
  String get novelOpenSourcePost => '原帖';

  @override
  String novelSaveOpenModeFailed(String error) {
    return '儲存章節開啟方式失敗：$error';
  }

  @override
  String get novelSourceRouteDialogTitle => '無法定位原帖樓層';

  @override
  String get novelOpenThreadHome => '開啟帖子首頁';

  @override
  String get novelSourceRouteInvalidTid => '章節缺少有效的來源 TID';

  @override
  String get novelSourceRouteInvalidPid => '章節缺少有效的來源 PID';

  @override
  String novelSourceRouteLocatorFailed(String error) {
    return '原帖樓層定位失敗：$error';
  }

  @override
  String get novelSourceRouteEmptyResult => '原帖樓層定位結果為空';

  @override
  String get novelSourceRouteMismatchedResult => '原帖樓層定位結果與章節來源不一致';

  @override
  String get novelSourceRouteInvalidPage => '原帖樓層頁碼無效';

  @override
  String get novelHydrationRecoveringMetadata => '正在恢復小說來源資訊';

  @override
  String get novelHydrationPreparing => '正在準備章節';

  @override
  String novelHydrationCommitting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個章節',
      zero: '0 個章節',
    );
    return '正在儲存 $_temp0';
  }

  @override
  String novelHydrationLoadingPage(int currentPage, int acceptedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      acceptedCount,
      locale: localeName,
      other: '$acceptedCount 章',
      zero: '0 章',
    );
    return '正在載入第 $currentPage 頁 · 已發現 $_temp0';
  }

  @override
  String novelHydrationLoadingPageOfTotal(
    int currentPage,
    int totalPages,
    int acceptedCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      acceptedCount,
      locale: localeName,
      other: '$acceptedCount 章',
      zero: '0 章',
    );
    return '正在載入第 $currentPage/$totalPages 頁 · 已發現 $_temp0';
  }

  @override
  String get novelHydrationMissingSource => '缺少小說來源資訊，無法載入章節';

  @override
  String get novelHydrationMissingPublisher => '來源帖子缺少有效的發佈者 ID';

  @override
  String get novelHydrationMissingTid => '小說缺少來源帖子 ID';

  @override
  String get novelHydrationMissingCheckpoint => '章節同步檢查點缺失，無法安全更新';

  @override
  String get novelHydrationInterrupted => '章節同步已中斷，請重試';

  @override
  String novelChapterLoadFailed(String error) {
    return '章節載入失敗：$error';
  }

  @override
  String get novelChapterLoadUnknown => '章節載入失敗，請重試';

  @override
  String get novelReaderNoChapters => '小說沒有可閱讀章節';

  @override
  String get novelReaderContentMissing => '章節正文暫不可用';

  @override
  String novelReaderLoadFailed(String error) {
    return '載入閱讀器失敗：$error';
  }

  @override
  String get novelDisplaySettings => '顯示設定';

  @override
  String get novelTypography => '排版';

  @override
  String get novelFontSize => '字號';

  @override
  String get novelLineSpacing => '間隔';

  @override
  String get novelTheme => '主題';

  @override
  String get novelThemeLight => '淺色';

  @override
  String get novelThemeSepia => '護眼';

  @override
  String get novelThemeDark => '深色';

  @override
  String get novelThemeFollowApp => '跟隨應用程式';

  @override
  String get novelReading => '閱讀';

  @override
  String get novelReadingMode => '閱讀模式';

  @override
  String get novelConversionMode => '簡繁';

  @override
  String get novelSafeContent => '安全顯示正文';

  @override
  String get novelConversionOriginal => '原文';

  @override
  String get novelConversionSimplified => '簡體';

  @override
  String get novelConversionTraditional => '繁體';

  @override
  String get novelFlowScroll => '滾動';

  @override
  String get novelFlowPagedLtr => '分頁 LTR';

  @override
  String get novelFlowPagedRtl => '分頁 RTL';

  @override
  String get novelBookmarkAdd => '新增章節書籤';

  @override
  String get novelBookmarkRemove => '移除章節書籤';

  @override
  String get novelBookmarkAdded => '已新增書籤';

  @override
  String get novelBookmarkRemoved => '已移除書籤';

  @override
  String get novelOpenSourceThread => '開啟原帖';

  @override
  String get novelCatalog => '目錄';

  @override
  String get novelDisplay => '顯示';

  @override
  String get novelPageCountPending => '計算中';

  @override
  String get novelPositionChanged => '位置已變更，已保留目前頁';

  @override
  String get novelChapterSwitchFailed => '章節切換失敗，已保留目前章節';

  @override
  String get novelReturnToScrollFailed => '切回滾動模式失敗';

  @override
  String get novelSaveDisplaySettingsFailed => '顯示設定儲存失敗';

  @override
  String get novelLinkOpenFailed => '連結開啟失敗';

  @override
  String get novelImageLinkCopied => '圖片連結已複製';

  @override
  String get novelWorkUpdateFailed => '作品更新失敗，已保留目前章節';

  @override
  String get novelSearchChapters => '搜尋章節';

  @override
  String get novelNoMatchingChapters => '沒有符合的章節';

  @override
  String get novelBookmark => '書籤';

  @override
  String get novelCurrent => '目前';

  @override
  String get novelLastRead => '上次閱讀';

  @override
  String novelNextChapter(String title) {
    return '下一章：$title';
  }

  @override
  String get novelChapterUnavailable => '章節暫時無法顯示';

  @override
  String get novelUpdateWork => '更新作品';

  @override
  String get novelPagedWindowUnavailable => '目前視窗無法產生分頁版面';

  @override
  String get novelPagedPreparing => '正在準備分頁正文';

  @override
  String get novelPagedCalculating => '正在計算分頁版面';

  @override
  String get novelPagedNoContent => '本章沒有可顯示的正文';

  @override
  String get novelPagedRestoringPosition => '正在恢復閱讀位置';

  @override
  String get novelPagedLayoutFailed => '分頁版面失敗';

  @override
  String get novelReturnToScroll => '回到滾動';

  @override
  String novelPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 頁',
      zero: '0 頁',
    );
    return '$_temp0';
  }

  @override
  String novelPageSemantics(
    String chapterTitle,
    int currentPage,
    String totalPages,
  ) {
    return '$chapterTitle，第 $currentPage 頁，共 $totalPages';
  }

  @override
  String novelPageValue(int currentPage, String totalPages) {
    return '第 $currentPage 頁，共 $totalPages';
  }

  @override
  String novelNextPageSemantics(int page) {
    return '下一頁，第 $page 頁';
  }

  @override
  String novelPreviousPageSemantics(int page) {
    return '上一頁，第 $page 頁';
  }

  @override
  String novelPageIndicator(int currentPage, String totalPages) {
    return '$currentPage / $totalPages';
  }

  @override
  String novelChapterTurnContinue(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'next': '繼續滑動進入下一章',
      'previous': '繼續滑動進入上一章',
      'other': '繼續滑動切換章節',
    });
    return '$_temp0';
  }

  @override
  String novelChapterTurnRelease(String direction, String title) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'next': '鬆手進入下一章 · $title',
      'previous': '鬆手進入上一章 · $title',
      'other': '鬆手切換章節 · $title',
    });
    return '$_temp0';
  }

  @override
  String novelPageOfTotalSemantics(int page, int total) {
    return '第 $page 頁，共 $total 頁';
  }

  @override
  String get libraryOperationWorkNotFound => '作品不存在或已被移除';

  @override
  String get libraryOperationChapterNotFound => '章節不存在或已被移除';

  @override
  String get libraryOperationUnsupported => '目前模組不支援此操作';

  @override
  String get libraryOperationCacheWriteFailed => '快取寫入失敗，請重試';

  @override
  String get libraryOperationDefaultCategoryImmutable => '預設分類不能修改或刪除';

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
  String get moreUnusedImages => '未使用圖片管理';

  @override
  String get moreUnusedImagesSubtitle => '查看並刪除尚未用於帖子的上傳圖片';

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
  String get moreColorThemeSectionTitle => '配色主題';

  @override
  String get moreAppearanceModeSectionTitle => '外觀模式';

  @override
  String get moreThemeFamilyWarmPaper => '暖紙';

  @override
  String get moreThemeFamilyMoonWhite => '月白';

  @override
  String get moreThemeFamilyPlumPurple => '梅紫';

  @override
  String get moreThemeFamilyWarmPaperDescription => '溫暖柔和的米色與褐色配色';

  @override
  String get moreThemeFamilyMoonWhiteDescription => '清冷克制的月白與藍灰配色';

  @override
  String get moreThemeFamilyPlumPurpleDescription => '溫潤沉靜的煙粉與梅紫配色';

  @override
  String moreThemeSummary(String family, String mode) {
    return '$family · $mode';
  }

  @override
  String get moreThemeLight => '日間';

  @override
  String get moreThemeDark => '夜間';

  @override
  String get moreThemeSystem => '跟隨系統';

  @override
  String get moreThemeDescriptionLight => '始終使用日間外觀';

  @override
  String get moreThemeDescriptionDark => '始終使用夜間外觀';

  @override
  String get moreThemeDescriptionSystem => '根據系統設定切換日間或夜間外觀';

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
  String get moreStorageBucketLibraryCover => '書架封面資產';

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
  String get moreStorageImageComposerUnusedAttachment => '未使用上傳圖片';

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
  String get threadDetailCopyFloorLink => '複製樓層連結';

  @override
  String get threadDetailCopyFloorLinkFailed => '樓層連結複製失敗';

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
  String get threadFavoriteSuccess => '收藏成功';

  @override
  String get threadFavoriteSuccessSyncFailed => '收藏成功，但收藏書架同步失敗';

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
  String get threadPollVoteAlreadyVoted => '已經投過票';

  @override
  String get threadPollVoteClosed => '投票已關閉';

  @override
  String get threadPollVoteExpired => '投票已過期';

  @override
  String get threadPollVoteTooMany => '選擇的選項超過投票上限';

  @override
  String get threadPollVoteUnavailable => '目前投票不可用';

  @override
  String get threadPollVoteInvalidSelection => '投票選項無效，請重新選擇';

  @override
  String get threadPollVoteSessionExpired => '工作階段已過期，請重新整理後再試';

  @override
  String get threadPollVoteOutcomeUnknown => '無法確認投票結果，請重新整理帖子後再決定是否重試';

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
  String get threadRatingOutcomeUnknown => '評分結果暫時無法確認，請重新整理後查看';

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
  String get threadCommentOutcomeUnknown => '點評結果暫時無法確認，請重新整理後查看';

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
  String get threadHtmlCollapseExpanded => '收起摺疊內容';

  @override
  String get threadHtmlCollapseCollapsed => '展開摺疊內容';

  @override
  String get threadHtmlRenderFailed => '正文渲染失敗，可長按樓層複製正文或開啟原帖查看。';

  @override
  String get threadSelectionCopyTitle => '選擇複製';

  @override
  String get threadDetailScrollTop => '滾動到頂部';

  @override
  String get threadDetailScrollBottom => '滾動到底部';

  @override
  String get commonUse => '使用';

  @override
  String get commonReset => '重置';

  @override
  String get composerBold => '粗體';

  @override
  String get composerItalic => '斜體';

  @override
  String get composerUnderline => '底線';

  @override
  String get composerStrikethrough => '刪除線';

  @override
  String get composerTextColor => '字體色';

  @override
  String get composerBackgroundColor => '背景色';

  @override
  String get composerLink => '連結';

  @override
  String get composerFontSize => '字號';

  @override
  String get composerAlignment => '對齊';

  @override
  String get composerQuote => '引用';

  @override
  String get composerImage => '圖片';

  @override
  String get composerSticker => '表情';

  @override
  String get composerCollapse => '摺疊';

  @override
  String get composerCollapseTitleHint => '輸入摺疊標題';

  @override
  String get composerCollapseCreateTitle => '新增摺疊';

  @override
  String get composerCollapseEditTitle => '編輯摺疊';

  @override
  String get composerCollapseBodyHint => '輸入摺疊正文';

  @override
  String get composerCollapseDiscardTitle => '放棄摺疊修改？';

  @override
  String get composerCollapseDiscardBody => '標題和正文的修改將不會儲存。';

  @override
  String get composerCollapseDiscardConfirm => '放棄修改';

  @override
  String get composerCollapseDeleteTitle => '刪除這個摺疊？';

  @override
  String get composerCollapseDeleteBody => '摺疊標題和正文將從帖子內容中刪除。';

  @override
  String get composerCollapseConflict => '帖子正文已更新，無法套用本次摺疊修改。請複製內容後重新開啟。';

  @override
  String get composerFormat => '格式';

  @override
  String get composerPreview => '預覽';

  @override
  String get composerSourceMode => '原始碼';

  @override
  String get composerVisualMode => '返回編輯';

  @override
  String get composerMore => '更多';

  @override
  String get composerMoreSettings => '更多設定';

  @override
  String get composerUseSignature => '使用個人簽名';

  @override
  String get composerResetDraft => '重置草稿';

  @override
  String get composerResetDraftTitle => '重置草稿？';

  @override
  String get composerResetDraftBody => '目前編輯內容和已選圖片將被清空，且無法復原。';

  @override
  String get composerContinueEditing => '繼續編輯';

  @override
  String get composerSaveDraftAndLeave => '儲存草稿並離開';

  @override
  String get composerRestoredDraft => '已復原未送出草稿';

  @override
  String get postingRestoredDraftWithTags => '已復原未送出的草稿，請注意已復原的主題標籤';

  @override
  String composerPendingAttachment(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 張圖片已上傳，請選擇位置後點選圖片按鈕重新插入',
      zero: '圖片已上傳，請選擇位置後點選圖片按鈕重新插入',
    );
    return '$_temp0';
  }

  @override
  String get composerPendingAttachmentSelectionExpired =>
      '目前選取範圍無法安全復原，請重新選擇位置';

  @override
  String composerUploadingImages(int current, int total) {
    return '正在上傳圖片 $current/$total';
  }

  @override
  String composerImageUploaded(String fileName) {
    return '$fileName 已上傳';
  }

  @override
  String composerImageUploadFailed(String fileName) {
    return '$fileName 上傳失敗，請重試';
  }

  @override
  String composerImageUploadFailedWithReason(String fileName, String reason) {
    return '$fileName 上傳失敗：$reason';
  }

  @override
  String get composerImagePickerFailed => '選擇圖片失敗，請重試';

  @override
  String get composerImageFileMissing => '圖片檔案不存在，無法上傳';

  @override
  String get composerImageInvalidFileType => '只能上傳圖片檔案';

  @override
  String get composerImageExtensionNotAllowed => '目前看板不允許上傳該類型圖片';

  @override
  String get composerImagePermissionExpired => '上傳權限已失效，請重新登入';

  @override
  String get composerImageQuotaExceeded => '附件額度不足，無法上傳圖片';

  @override
  String get composerImageFileTooLarge => '圖片超過目前使用者群組或檔案類型的大小限制';

  @override
  String get composerImagePermissionDenied => '目前帳號沒有上傳圖片的權限';

  @override
  String get composerImageInvalidContent => '伺服器無法識別該圖片，請檢查檔案後重試';

  @override
  String get composerImageSaveFailed => '伺服器儲存圖片失敗，請稍後重試';

  @override
  String get composerImageFileNameRejected => '圖片檔名包含不允許的內容，請重新命名後再試';

  @override
  String get composerImageDimensionsExceeded => '圖片寬高超過伺服器限制，請縮小後再試';

  @override
  String get composerImageUploadOutcomeUnknown =>
      '無法確認圖片是否上傳成功，請先檢查未使用圖片，避免重複上傳';

  @override
  String get composerImageUploadTimeout => '圖片上傳逾時，請重試';

  @override
  String get composerImageUploadNetwork => '網路異常，圖片上傳失敗';

  @override
  String get composerImageUploadServer => '上傳服務異常，請稍後重試';

  @override
  String get composerImageUploadUnknown => '圖片上傳失敗，請重試';

  @override
  String composerLoadDraftFailed(String error) {
    return '載入草稿失敗：$error';
  }

  @override
  String composerStickerLoadFailed(String error) {
    return '表情載入失敗：$error';
  }

  @override
  String get composerStickerNetworkRequired => '需要連線載入表情包';

  @override
  String get composerStickerAllGroup => '表情';

  @override
  String get composerStickerDefaultGroup => '預設表情';

  @override
  String get composerStartTypingHint => '請開始輸入';

  @override
  String get composerImageRetentionHint => '草稿圖片本機副本最多保留 14 天，開啟草稿時會連線驗證';

  @override
  String get composerDraftImageVerificationFailed =>
      '草稿圖片驗證失敗，圖片預覽已暫時隱藏。你仍可編輯和送出，連線後可重試。';

  @override
  String composerDraftImagesInvalidated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '發現 $count 張已失效的草稿圖片，正文代碼已保留',
      zero: '沒有失效的草稿圖片',
    );
    return '$_temp0';
  }

  @override
  String get unusedImagesPageTitle => '未使用圖片管理';

  @override
  String get unusedImagesEmpty => '沒有尚未用於帖子的上傳圖片';

  @override
  String get unusedImagesLoadFailed => '無法讀取未使用圖片，請檢查網路或登入狀態後重試';

  @override
  String get unusedImagesDeleteTooltip => '刪除圖片';

  @override
  String get unusedImagesDeleteTitle => '刪除這張未使用圖片？';

  @override
  String get unusedImagesDeleteBody => '圖片將從伺服器刪除，草稿中的正文代碼會保留。此操作無法復原。';

  @override
  String get unusedImagesDeleteFailed => '圖片刪除未成功，圖片仍保留';

  @override
  String get composerLinkTitle => '新增連結';

  @override
  String get composerLinkUrl => '連結';

  @override
  String get composerLinkText => '連結文字';

  @override
  String get composerLinkTextHint => '顯示給別人看的文字';

  @override
  String get composerLinkUrlRequired => '請輸入連結';

  @override
  String get composerLinkTextRequired => '請輸入連結文字';

  @override
  String get composerAlignLeft => '靠左對齊';

  @override
  String get composerAlignCenter => '置中';

  @override
  String get composerAlignRight => '靠右對齊';

  @override
  String get composerClearFormatting => '清除狀態';

  @override
  String get composerClearFontSize => '清除字號';

  @override
  String get composerClearTextColor => '清除顏色';

  @override
  String get composerClearBackgroundColor => '清除背景';

  @override
  String get composerAuthenticationRequired => '登入狀態已失效，請重新登入後再試';

  @override
  String composerCredentialExpired(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '發帖憑證已失效，請重新整理登入狀態後重試',
      'reply': '回覆憑證已失效，請重新整理登入狀態後重試',
      'other': '送出憑證已失效，請重新整理登入狀態後重試',
    });
    return '$_temp0';
  }

  @override
  String composerRateLimited(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '發帖過於頻繁，請稍後再試',
      'reply': '回覆太頻繁，請稍後再試',
      'other': '操作過於頻繁，請稍後再試',
    });
    return '$_temp0';
  }

  @override
  String composerPermissionDenied(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '目前帳號權限不足，無法發帖',
      'reply': '目前帳號權限不足，無法送出回覆',
      'other': '目前帳號權限不足',
    });
    return '$_temp0';
  }

  @override
  String get composerSubmissionTypeRequired => '該看板要求選擇主題分類，請先選擇';

  @override
  String get composerSubmissionSubjectTooShort => '標題過短，請補充後重試';

  @override
  String get composerSubmissionSubjectTooLong => '標題過長，請縮短後重試';

  @override
  String composerSubmissionContentTooShort(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '正文內容過短，請補充後重試',
      'reply': '回覆內容過短，請補充後重試',
      'other': '送出內容過短，請補充後重試',
    });
    return '$_temp0';
  }

  @override
  String composerSubmissionContentTooLong(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '正文內容過長，請縮短後重試',
      'reply': '回覆內容過長，請縮短後重試',
      'other': '送出內容過長，請縮短後重試',
    });
    return '$_temp0';
  }

  @override
  String composerSubmissionTargetUnavailable(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '目標看板無法使用，請重新整理後再試',
      'reply': '目標帖子或樓層無法使用，請重新整理後再試',
      'other': '送出目標無法使用，請重新整理後再試',
    });
    return '$_temp0';
  }

  @override
  String get composerSubmissionThreadClosed => '該帖子已關閉，無法繼續回覆';

  @override
  String get composerCaptchaRequired => '需要驗證碼，請暫時改用網頁發佈';

  @override
  String get composerPollInvalid => '投票設定無效，請檢查選項與截止時間';

  @override
  String get composerPollOptionCountInvalid => '投票選項數量不合法';

  @override
  String get composerPollFieldsInvalid => '請正確填寫投票相關欄位';

  @override
  String get composerNetworkTimeout => '網路逾時，請稍後重試';

  @override
  String get composerNetworkFailure => '網路異常，請稍後重試';

  @override
  String get composerServerFailure => '服務異常，請稍後重試';

  @override
  String composerUnknownFailure(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '發帖失敗，請稍後重試',
      'reply': '送出回覆失敗，請稍後重試',
      'other': '送出失敗，請稍後重試',
    });
    return '$_temp0';
  }

  @override
  String composerOutcomeUnknown(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'newThread': '發帖結果無法確認，請先檢查版塊，避免重複送出',
      'reply': '回覆結果無法確認，請先檢查帖子，避免重複送出',
      'other': '送出結果無法確認，請先檢查目標內容，避免重複送出',
    });
    return '$_temp0';
  }

  @override
  String get postingTitle => '發帖';

  @override
  String postingTitleWithForum(String forumName) {
    return '發帖 — $forumName';
  }

  @override
  String get postingSend => '發佈';

  @override
  String get postingSubjectHint => '輸入標題';

  @override
  String get postingBodyHint => '請輸入正文';

  @override
  String get postingFormLoading => '正在載入發帖表單';

  @override
  String postingFormLoadFailed(String error) {
    return '載入發帖表單失敗：$error';
  }

  @override
  String get postingType => '主題分類';

  @override
  String get postingTypeRequired => '主題分類（必選）';

  @override
  String get postingTypeNone => '無分類';

  @override
  String get postingTypeUnselected => '未選擇';

  @override
  String get postingTags => '主題標籤';

  @override
  String get postingTagsHint => '輸入標籤，按 Enter 或英文逗號確認';

  @override
  String get postingTagDelete => '刪除標籤';

  @override
  String postingTagsLimit(int maxTags, int maxLength) {
    return '最多 $maxTags 個；單個標籤 ≤ $maxLength 個字';
  }

  @override
  String get postingNormalThread => '一般帖';

  @override
  String get postingPoll => '投票';

  @override
  String get postingPollConfig => '投票設定';

  @override
  String get postingThreadKind => '帖子類型';

  @override
  String postingPollConstraints(int min, int max, int maxLength) {
    return '至少 $min 個選項；最多 $max 個，單項 ≤ $maxLength 個字';
  }

  @override
  String postingPollSummary(int count, String mode) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已填 $count 項 / $mode',
      zero: '尚未填寫選項 / $mode',
    );
    return '$_temp0';
  }

  @override
  String get postingPollSingle => '單選';

  @override
  String get postingPollMultipleMode => '複選';

  @override
  String postingPollOption(int index) {
    return '選項 $index';
  }

  @override
  String get postingPollAddOption => '新增選項';

  @override
  String get postingPollRemoveOption => '刪除選項';

  @override
  String get postingPollMultiple => '允許複選';

  @override
  String postingPollMaxChoices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最多可選 $count 項',
      zero: '不可選擇選項',
    );
    return '$_temp0';
  }

  @override
  String get postingPollDeadline => '截止天數';

  @override
  String get postingPollNeverExpires => '不限期';

  @override
  String postingPollDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 天',
      zero: '不限期',
    );
    return '$_temp0';
  }

  @override
  String get postingPollPublicVoters => '公開投票人';

  @override
  String get postingPollPublicVotersDescription => '開啟後所有人可看到誰投了哪一項';

  @override
  String get postingPollShowResultsAfterVote => '投票後才顯示結果';

  @override
  String get postingAllowNoticeAuthor => '允許通知作者';

  @override
  String get postingDisableBbCode => '關閉 BBCode 解析';

  @override
  String get postingDisableSmiley => '關閉表情解析';

  @override
  String get postingDisableUrl => '關閉 URL 解析';

  @override
  String get postingLeaveTitle => '儲存草稿並離開？';

  @override
  String get postingLeaveBody => '目前帖子還沒有送出，離開前會儲存為草稿。';

  @override
  String get postingSubjectRequired => '請輸入標題';

  @override
  String get postingBodyRequired => '請輸入正文';

  @override
  String get postingFormStillLoading => '發帖表單還在載入，請稍候再試';

  @override
  String postingSubjectTooLong(int limit) {
    return '標題超出看板上限（最多 $limit 個字）';
  }

  @override
  String postingBodyTooLong(int limit) {
    return '正文超出看板上限（最多 $limit 個字）';
  }

  @override
  String get postingPollMissing => '缺少投票設定，請新增選項';

  @override
  String postingPollTooFewOptions(int limit) {
    return '投票至少需要 $limit 個非空選項';
  }

  @override
  String postingPollOptionTooLong(int limit) {
    return '單個投票選項不能超過 $limit 個字';
  }

  @override
  String postingPollMultipleInvalid(int limit) {
    return '複選投票的最大選擇數至少為 $limit';
  }

  @override
  String get postingSubmitSuccess => '發佈成功';

  @override
  String postingSubmitSuccessWithDetail(String detail) {
    return '發佈成功：$detail';
  }

  @override
  String get replyThreadTitle => '回覆帖子';

  @override
  String get replyFloorTitle => '回覆樓層';

  @override
  String get replySubmit => '送出';

  @override
  String get replyMessageHint => '輸入回覆內容';

  @override
  String get replyPreparingQuote => '正在準備樓層引用';

  @override
  String replyPreparationFailed(String error) {
    return '樓層回覆引用準備失敗：$error';
  }

  @override
  String get replyLeaveTitle => '儲存草稿並離開？';

  @override
  String get replyLeaveBody => '目前回覆還沒有送出，離開前會儲存為草稿。';

  @override
  String get replyContentRequired => '請輸入回覆內容';

  @override
  String get replyReferenceUnavailable => '樓層回覆引用準備失敗，請重試';

  @override
  String get replySubmitSuccess => '回覆成功';

  @override
  String replySubmitSuccessWithDetail(String detail) {
    return '回覆成功：$detail';
  }

  @override
  String get composerPrototypeTitle => 'Quill Composer 原型';

  @override
  String get composerPrototypeSourceTitle => '原始碼微調';

  @override
  String composerPrototypeAttachmentInserted(String aid) {
    return '已插入測試附件 $aid';
  }

  @override
  String composerAttachmentFallback(String aid) {
    return '圖片 $aid';
  }

  @override
  String get composerLinkUrlHint => 'https://example.com';

  @override
  String get commonSearch => '搜尋';

  @override
  String get commonMenu => '選單';

  @override
  String get commonPreviousPage => '上一頁';

  @override
  String get commonNextPage => '下一頁';

  @override
  String commonPage(int page) {
    return '第$page頁';
  }

  @override
  String commonPageOf(int page, int total) {
    return '第 $page / $total 頁';
  }

  @override
  String get commonImageLoading => '圖片載入中';

  @override
  String get commonNetworkError => '網路連線失敗';

  @override
  String get commonTimeoutError => '請求逾時';

  @override
  String get commonUnauthorizedError => '登入狀態已失效';

  @override
  String get commonServerError => '伺服器目前無法使用';

  @override
  String get commonParseError => '內容解析失敗';

  @override
  String get commonRequestError => '請求失敗';

  @override
  String get authLoginTitle => '登入';

  @override
  String get authUsername => '使用者名稱';

  @override
  String get authUsernameHint => '請輸入論壇帳號';

  @override
  String get authPassword => '密碼';

  @override
  String get authLoginSuccess => '登入成功';

  @override
  String get authCredentialsRequired => '請輸入使用者名稱和密碼';

  @override
  String get authLoginTimeout => '登入逾時，請檢查網路後重試';

  @override
  String get authLoginRejected => '帳號或密碼錯誤';

  @override
  String authLoginFailed(String error) {
    return '登入失敗：$error';
  }

  @override
  String authLoginWelcome(String username) {
    return '歡迎回來，$username';
  }

  @override
  String authWebViewVerificationFailed(String error) {
    return '登入驗證失敗：$error';
  }

  @override
  String get appUpdateDialogTitle => '發現新版本';

  @override
  String appUpdateDialogBody(
    String appName,
    String latestVersion,
    String installedVersion,
  ) {
    return '$appName v$latestVersion 已發佈，目前版本為 v$installedVersion';
  }

  @override
  String get appUpdateDialogPrompt => '是否立即更新？';

  @override
  String get appUpdateDialogReleaseNotes => '更新說明';

  @override
  String get appUpdateDialogIgnore => '忽略';

  @override
  String get appUpdateDialogLater => '關閉';

  @override
  String get appUpdateDialogUpdate => '更新';

  @override
  String get appUpdateCheck => '檢查更新';

  @override
  String get appUpdateVersionLoading => '目前版本：讀取中';

  @override
  String appUpdateCurrentVersion(String version) {
    return '目前版本：$version';
  }

  @override
  String get appUpdateUpToDate => '已是最新版本';

  @override
  String get appUpdateReleaseNotesEmpty => '目前版本沒有更新日誌';

  @override
  String get appUpdateReleaseNotesUnavailable => '更新日誌目前無法使用';

  @override
  String get appUpdateDownloadNetworkUnavailable => '網路無法使用，無法開始下載更新';

  @override
  String get appUpdateDownloadTimeout => '更新檢查逾時，請稍後重試';

  @override
  String get appUpdateDownloadInvalid => '目前更新資訊無效，請稍後重試';

  @override
  String get appUpdateDownloadInProgress => '更新正在下載，請稍候';

  @override
  String get appUpdateDownloadFailed => '無法開始下載更新，請稍後重試';

  @override
  String get appUpdateCheckNetworkUnavailable => '網路無法使用，檢查更新失敗';

  @override
  String get appUpdateCheckTimeout => '檢查更新逾時，請稍後重試';

  @override
  String get appUpdateCheckRateLimited => '檢查更新過於頻繁，請稍後重試';

  @override
  String get appUpdateInstalledVersionUnavailable => '無法讀取目前應用程式版本';

  @override
  String get appUpdateCheckFailed => '檢查更新失敗，請稍後重試';

  @override
  String get appUpdateInvalidUrl => '更新下載網址無效，請稍後重試';

  @override
  String get appUpdateBrowserUnavailable => '無法開啟下載連結，請確認裝置已安裝瀏覽器';

  @override
  String get appUpdateOpenUrlFailed => '開啟下載連結失敗，請稍後重試';

  @override
  String get appUpdateLaunchFailed => '開啟更新下載連結失敗，請稍後重試';

  @override
  String get searchTitle => '搜尋';

  @override
  String get searchInputHint => '輸入關鍵字';

  @override
  String get searchLoadMore => '查看更多';

  @override
  String searchRetryAfter(int seconds) {
    return '請在 $seconds 秒後重試';
  }

  @override
  String get searchNoResults => '找不到結果';

  @override
  String searchFailed(String error) {
    return '搜尋失敗：$error';
  }

  @override
  String searchLoadMoreFailed(String error) {
    return '載入更多失敗：$error';
  }

  @override
  String get searchForumFallback => '論壇搜尋';

  @override
  String searchQueueWaiting(String subject, String seconds) {
    return '$subject 正在等待搜尋，預計 $seconds 秒';
  }

  @override
  String searchResultTid(String tid) {
    return 'TID：$tid';
  }

  @override
  String get tagTitleFallback => '標籤';

  @override
  String tagLoadFailed(String error) {
    return '標籤頁載入失敗：$error';
  }

  @override
  String tagRelatedThreads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個相關帖子',
      zero: '目前沒有相關帖子',
    );
    return '$_temp0';
  }

  @override
  String tagReplies(int count) {
    return '回覆 $count';
  }

  @override
  String tagViews(int count) {
    return '瀏覽 $count';
  }

  @override
  String tagLastPost(String value) {
    return '最後發表 $value';
  }

  @override
  String get tagMore => '更多';

  @override
  String get tagEmpty => '目前沒有相關帖子';

  @override
  String get profileTitle => '個人資料';

  @override
  String get profileMyTitle => '我的資料';

  @override
  String profileUserTitle(String username) {
    return '$username 的資料';
  }

  @override
  String get profileHome => '首頁';

  @override
  String get profileLoginRequired => '請先登入後查看個人資料';

  @override
  String get profileMyThreads => '我的主題';

  @override
  String get profileMyBlogs => '我的日誌';

  @override
  String get profileMyFavorites => '我的收藏';

  @override
  String get profileMessages => '訊息提醒';

  @override
  String get profileMyFriends => '我的好友';

  @override
  String get profileDailyCheckIn => '每日簽到';

  @override
  String get profileTheirThreads => 'Ta 的主題';

  @override
  String get profileTheirBlogs => 'Ta 的日誌';

  @override
  String get profileSendMessage => '傳送短訊息';

  @override
  String get profileAddFriend => '加為好友';

  @override
  String get profileActionUnavailable => '目前尚未支援此操作';

  @override
  String get profileSignature => '個人簽名';

  @override
  String get profileDetails => '個人資料';

  @override
  String profileLoadFailed(String error) {
    return '資料載入失敗：$error';
  }

  @override
  String get profileBlogTitle => '日誌';

  @override
  String get profileBlogWrite => '寫日誌';

  @override
  String get profileBlogWriteUnavailable => '目前尚未支援發表新日誌';

  @override
  String get profileBlogEmpty => '還沒有相關日誌';

  @override
  String get profileBlogFriends => '好友的日誌';

  @override
  String get profileBlogMine => '我的日誌';

  @override
  String get profileBlogExplore => '隨便看看';

  @override
  String get profileBlogLatest => '最新發表的日誌';

  @override
  String get profileBlogRecommended => '推薦閱讀的日誌';

  @override
  String get profileBlogComments => '日誌留言';

  @override
  String get profileBlogCommentUnavailable => '目前尚未支援提交日誌留言';

  @override
  String get profileBlogComment => '留言';

  @override
  String profileBlogViews(int count) {
    return '瀏覽 $count';
  }

  @override
  String profileBlogCommentCount(int count) {
    return '留言 $count';
  }

  @override
  String profileBlogLoadFailed(String error) {
    return '日誌載入失敗：$error';
  }

  @override
  String get profileMessageCenterTitle => '訊息提醒';

  @override
  String profileNotificationsTab(int count) {
    return '提醒 $count';
  }

  @override
  String profileMessagesTab(int count) {
    return '訊息 $count';
  }

  @override
  String get profileNoNotifications => '目前沒有提醒';

  @override
  String get profileSystemNotification => '系統提醒';

  @override
  String get profileNoMessages => '目前沒有訊息';

  @override
  String get profilePrivateMessage => '私人訊息';

  @override
  String profileMessageTo(String name) {
    return '傳送給 $name';
  }

  @override
  String get profileNewBadge => '新';

  @override
  String profileMessagesLoadFailed(String error) {
    return '訊息載入失敗：$error';
  }

  @override
  String get threadPrototypeTitle => 'HTML 正文渲染原型';

  @override
  String threadPrototypeLoadFailed(String error) {
    return '範例載入失敗：$error';
  }

  @override
  String get threadPrototypeEmptyResult => '範例載入失敗：結果為空';

  @override
  String threadPrototypeMissingAsset(String sourcePath, String assetPath) {
    return '找不到本機範例，請從 $sourcePath 複製到 $assetPath';
  }

  @override
  String threadPrototypeLink(String url) {
    return '連結：$url';
  }

  @override
  String get threadPrototypeThemeLight => '淺色';

  @override
  String get threadPrototypeThemeDark => '深色';

  @override
  String threadPrototypeJitterCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已複製 $count 筆抖動記錄',
      zero: '未複製抖動記錄',
    );
    return '$_temp0';
  }

  @override
  String threadPrototypeImageOpened(int postNumber, int index) {
    return '$postNumber# 圖片：$index';
  }

  @override
  String get threadPrototypeActionUnsupported => '原型頁目前不執行該帖子操作';

  @override
  String get threadPrototypeJitterTitle => '記錄抖動資訊';

  @override
  String get threadPrototypeJitterRecording => '記錄中，關閉後可複製記錄';

  @override
  String threadPrototypeJitterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已記錄 $count 筆',
      zero: '尚未記錄',
    );
    return '$_temp0';
  }

  @override
  String get threadPrototypeCopyLog => '複製記錄';

  @override
  String get threadPrototypeThreadSummarySemantics => 'HTML 原型帖子範例摘要';

  @override
  String get threadPrototypeSummarySemantics => 'HTML 原型範例摘要';

  @override
  String threadPrototypeSample(String sample) {
    return '範例：$sample';
  }

  @override
  String threadPrototypeThread(String subject) {
    return '帖子：$subject';
  }

  @override
  String threadPrototypePage(int page, String total) {
    return '頁碼：$page/$total';
  }

  @override
  String threadPrototypePosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '樓層：$count 個',
      zero: '樓層：0 個',
    );
    return '$_temp0';
  }

  @override
  String threadPrototypeConversionMode(String mode) {
    return '轉換模式：$mode';
  }

  @override
  String threadPrototypeConverter(String converterId) {
    return '轉換器：$converterId';
  }

  @override
  String threadPrototypeConvertedNodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '轉換文字節點：$count 個',
      zero: '轉換文字節點：0 個',
    );
    return '$_temp0';
  }

  @override
  String threadPrototypePreviewTheme(String theme) {
    return '預覽主題：$theme';
  }

  @override
  String threadPrototypeTypography(int fontScale, String lineHeight) {
    return '字型大小 $fontScale% / 行距 $lineHeight×';
  }

  @override
  String threadPrototypeThemeAdaptation(String authorFontMode) {
    String _temp0 = intl.Intl.selectLogic(authorFontMode, {
      'preserved': '主題調整：一律啟用 / 保留作者字型大小',
      'unified': '主題調整：一律啟用 / 統一作者字型大小',
      'other': '主題調整：一律啟用',
    });
    return '$_temp0';
  }

  @override
  String threadPrototypeRawHtmlLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '原始 HTML：$count 個字元',
      zero: '原始 HTML：0 個字元',
    );
    return '$_temp0';
  }

  @override
  String threadPrototypeFragmentLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '正文 fragment：$count 個字元',
      zero: '正文 fragment：0 個字元',
    );
    return '$_temp0';
  }

  @override
  String threadPrototypeAdaptedColors(
    int remappedForeground,
    int explicitForeground,
    int remappedBackground,
    int explicitBackground,
  ) {
    return '調整前景：$remappedForeground/$explicitForeground · 調整背景：$remappedBackground/$explicitBackground';
  }

  @override
  String threadPrototypeAdaptationFallbacks(
    int semanticFallback,
    int unsupported,
    int concealed,
  ) {
    return '語意回退：$semanticFallback · 不支援：$unsupported · 隱藏：$concealed';
  }

  @override
  String threadPrototypeMinimumContrast(String value) {
    return '最低可見對比度：$value';
  }

  @override
  String get postEditTitle => '編輯帖子';

  @override
  String get postEditMessageHint => '帖子內容';

  @override
  String get postEditSave => '儲存';

  @override
  String get postEditSwitchToWebView => '切換到網頁編輯';

  @override
  String get postEditSwitchToNative => '返回原生編輯';

  @override
  String get postEditConflictTitle => '伺服器內容已變更';

  @override
  String get postEditConflictBody => '網頁編輯或其他裝置已修改這則帖子，請選擇要保留的版本。';

  @override
  String get postEditUseServer => '使用伺服器版本';

  @override
  String get postEditKeepLocal => '保留本地版本';

  @override
  String get postEditVerificationFailed => '無法確認網頁編輯後的伺服器狀態，原生儲存暫不可用。';

  @override
  String get postEditNativeSubmitUnavailable => '原生儲存將在後續版本開放';

  @override
  String get postEditManageImages => '管理圖片';

  @override
  String get postEditNoImages => '目前編輯沒有圖片';

  @override
  String get postEditDeleteImage => '刪除圖片';

  @override
  String get postEditDeleteImageTitle => '刪除這張圖片？';

  @override
  String get postEditDeleteImageBody => '這會刪除伺服器上的圖片，但不會刪除正文中的圖片代碼。';

  @override
  String get postEditDeleteImageConfirm => '確認刪除';

  @override
  String get postEditDeleteImageFailed => '圖片刪除未成功，圖片仍保留。';

  @override
  String get postEditDeleteImageUnconfirmed => '無法確認圖片刪除狀態，請稍後重試。';

  @override
  String get postEditAttachmentDeleting => '正在刪除圖片';

  @override
  String get postEditDeletedImageReferenceWarning => '正文仍包含已刪除圖片代碼。';

  @override
  String get postEditSubmitInProgress => '正在儲存帖子內容…';

  @override
  String get postEditDanglingAttachmentTitle => '正文包含無法確認的圖片引用';

  @override
  String get postEditDanglingAttachmentBody =>
      '部分圖片引用無法關聯到目前可用附件，仍要繼續儲存嗎？正文不會被自動修改。';

  @override
  String get postEditDanglingAttachmentConfirm => '繼續儲存';

  @override
  String get postEditPartialSuccess => '正文已儲存，但部分新圖片未能確認關聯，請檢查後再試。';

  @override
  String get postEditSubmitUnconfirmed => '儲存結果未確認，已暫時停用原生儲存。請重新驗證伺服器版本。';

  @override
  String get postEditRetryVerification => '重新驗證';

  @override
  String get postEditFormExpired => '編輯表單已過期，正在重新取得後重試一次。';

  @override
  String get postEditPermissionDenied => '沒有權限儲存此帖子。';

  @override
  String get postEditAuthenticationRequired => '登入狀態已失效，請重新登入後再試。';

  @override
  String get postEditSubmitFailed => '帖子儲存失敗，目前內容已保留。';

  @override
  String postEditLoadFailed(String error) {
    return '讀取帖子編輯表單失敗：$error';
  }

  @override
  String get postEditServerVersion => '伺服器版本';

  @override
  String get postEditLocalVersion => '本地版本';
}
