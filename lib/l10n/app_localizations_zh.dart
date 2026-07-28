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
  String get libraryDetailManageChaptersDescription => '显示或隐藏章节，手动添加或移除章节';

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
  String libraryChapterCurrentPageOfTotal(int page, int total) {
    return '第 $page 页，共 $total 页';
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
  String get libraryChapterShowAll => '全部显示';

  @override
  String get libraryChapterHideAll => '全部隐藏';

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
  String get libraryChapterAllHidden => '已隐藏全部章节';

  @override
  String get libraryChapterAllShown => '已显示全部章节';

  @override
  String libraryChapterBulkUpdateFailed(String error) {
    return '批量更新失败：$error';
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
  String get libraryDetailManageChaptersDescription => '顯示或隱藏章節，手動新增或移除章節';

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
  String libraryChapterCurrentPageOfTotal(int page, int total) {
    return '第 $page 頁，共 $total 頁';
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
  String get libraryChapterShowAll => '全部顯示';

  @override
  String get libraryChapterHideAll => '全部隱藏';

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
  String get libraryChapterAllHidden => '已隱藏全部章節';

  @override
  String get libraryChapterAllShown => '已顯示全部章節';

  @override
  String libraryChapterBulkUpdateFailed(String error) {
    return '批次更新失敗：$error';
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
