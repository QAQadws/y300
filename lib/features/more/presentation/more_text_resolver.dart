import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_shell_destination_presentation.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/more/domain/models/about_app_info.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';
import 'package:y300/l10n/app_localizations.dart';

final class MoreTextResolver {
  const MoreTextResolver._();

  static String themeFamilyLabel(AppLocalizations l10n, AppThemeFamily family) {
    return switch (family) {
      AppThemeFamily.warmPaper => l10n.moreThemeFamilyWarmPaper,
      AppThemeFamily.moonWhite => l10n.moreThemeFamilyMoonWhite,
      AppThemeFamily.plumPurple => l10n.moreThemeFamilyPlumPurple,
    };
  }

  static String themeFamilyDescription(
    AppLocalizations l10n,
    AppThemeFamily family,
  ) {
    return switch (family) {
      AppThemeFamily.warmPaper => l10n.moreThemeFamilyWarmPaperDescription,
      AppThemeFamily.moonWhite => l10n.moreThemeFamilyMoonWhiteDescription,
      AppThemeFamily.plumPurple => l10n.moreThemeFamilyPlumPurpleDescription,
    };
  }

  static String brightnessLabel(
    AppLocalizations l10n,
    AppBrightnessPreference preference,
  ) {
    return switch (preference) {
      AppBrightnessPreference.light => l10n.moreThemeLight,
      AppBrightnessPreference.dark => l10n.moreThemeDark,
      AppBrightnessPreference.system => l10n.moreThemeSystem,
    };
  }

  static String brightnessDescription(
    AppLocalizations l10n,
    AppBrightnessPreference preference,
  ) {
    return switch (preference) {
      AppBrightnessPreference.light => l10n.moreThemeDescriptionLight,
      AppBrightnessPreference.dark => l10n.moreThemeDescriptionDark,
      AppBrightnessPreference.system => l10n.moreThemeDescriptionSystem,
    };
  }

  static String appearanceSummary(
    AppLocalizations l10n,
    AppThemeFamily family,
    AppBrightnessPreference brightness,
  ) {
    return l10n.moreThemeSummary(
      themeFamilyLabel(l10n, family),
      brightnessLabel(l10n, brightness),
    );
  }

  static String forumModeLabel(AppLocalizations l10n, ForumShellMode mode) {
    return switch (mode) {
      ForumShellMode.webview => l10n.moreForumModeWebView,
      ForumShellMode.native => l10n.moreForumModeNative,
    };
  }

  static String aboutVersion(AppLocalizations l10n, AboutAppInfo? appInfo) {
    if (appInfo == null) {
      return l10n.moreAboutVersionLoading;
    }
    final version = appInfo.version.trim();
    final buildNumber = appInfo.buildNumber.trim();
    if (buildNumber.isEmpty) {
      return l10n.moreAboutVersion(version);
    }
    return l10n.moreAboutVersionWithBuild(version, buildNumber);
  }

  static String navigationLabel(
    AppLocalizations l10n,
    MainShellDestination destination,
  ) {
    return destination.localizedLabel(l10n);
  }

  static String storageLabel(AppLocalizations l10n, StorageUsageLabelRef? ref) {
    if (ref == null) {
      return '';
    }
    return switch (ref.kind) {
      StorageUsageLabelKind.bucket => _bucketLabel(l10n, ref.code),
      StorageUsageLabelKind.imageRole => l10n.moreStorageImageRole(
        _imageRoleLabel(l10n, ref.code),
        _imageQualifierLabel(l10n, ref.qualifier),
      ),
      StorageUsageLabelKind.imageCategory => _imageCategoryLabel(
        l10n,
        ref.code,
      ),
      StorageUsageLabelKind.documentOwner => l10n.moreStorageDocumentHtml(
        _documentOwnerLabel(l10n, ref.code),
        ref.count ?? 0,
      ),
      StorageUsageLabelKind.snapshotType => l10n.moreStorageSnapshot(
        _snapshotLabel(l10n, ref.code),
        ref.count ?? 0,
      ),
      StorageUsageLabelKind.composerDraft => l10n.moreStorageComposerDraft(
        ref.count ?? 0,
      ),
      StorageUsageLabelKind.downloadKind => _downloadLabel(l10n, ref.code),
      StorageUsageLabelKind.libraryKind => l10n.moreStorageLibraryCount(
        _libraryLabel(l10n, ref.code),
        ref.count ?? 0,
      ),
      StorageUsageLabelKind.historyKind =>
        ref.code == 'entries'
            ? l10n.moreStorageHistoryEntries(ref.count ?? 0)
            : l10n.moreStorageHistoryDatabase,
      StorageUsageLabelKind.database => l10n.moreStorageDatabase,
    };
  }

  static String storageNotice(AppLocalizations l10n, DataStorageNotice notice) {
    return switch (notice.code) {
      DataStorageNoticeCode.cachePartiallyCleared =>
        l10n.moreStorageNoticeCachePartiallyCleared,
      DataStorageNoticeCode.cacheCleared => l10n.moreStorageNoticeCacheCleared,
      DataStorageNoticeCode.cacheLimitUpdated =>
        l10n.moreStorageNoticeCacheLimitUpdated,
      DataStorageNoticeCode.directoryNotSelected =>
        l10n.moreStorageNoticeDirectoryNotSelected,
      DataStorageNoticeCode.storageLocationUpdated =>
        l10n.moreStorageNoticeLocationUpdated,
      DataStorageNoticeCode.defaultStorageRestored =>
        l10n.moreStorageNoticeDefaultRestored,
      DataStorageNoticeCode.usageReloaded =>
        l10n.moreStorageNoticeUsageReloaded,
      DataStorageNoticeCode.diagnosticsExported =>
        l10n.moreStorageNoticeDiagnosticsExported(notice.path ?? ''),
    };
  }

  static String storageMigrationFailure(
    AppLocalizations l10n,
    StorageRootMigrationFailureCode? code,
  ) {
    return switch (code) {
      StorageRootMigrationFailureCode.insufficientSpace =>
        l10n.moreStorageMigrationInsufficientSpace,
      StorageRootMigrationFailureCode.permissionDenied ||
      StorageRootMigrationFailureCode.sourceUnavailable ||
      StorageRootMigrationFailureCode.targetUnavailable =>
        l10n.moreStorageMigrationLocationUnavailable,
      StorageRootMigrationFailureCode.targetConflict ||
      StorageRootMigrationFailureCode.unsupportedLayout ||
      StorageRootMigrationFailureCode.unsafeEntity ||
      StorageRootMigrationFailureCode.invalidTopology =>
        l10n.moreStorageMigrationConflict,
      _ => l10n.moreStorageMigrationFailed,
    };
  }

  static String _bucketLabel(AppLocalizations l10n, String code) {
    return switch (code) {
      'image_cache' => l10n.moreStorageBucketImageCache,
      'library_cover' => l10n.moreStorageBucketLibraryCover,
      'page_cache' => l10n.moreStorageBucketPageCache,
      'library_metadata' => l10n.moreStorageBucketLibraryMetadata,
      'history' => l10n.moreStorageBucketHistory,
      'composer_draft' => l10n.moreStorageBucketComposerDraft,
      'download' => l10n.moreStorageBucketDownload,
      'app_settings' => l10n.moreStorageBucketAppSettings,
      _ => code,
    };
  }

  static String _imageCategoryLabel(AppLocalizations l10n, String code) {
    return switch (code) {
      'clearable' => l10n.moreStorageCategoryClearable,
      'sticky' => l10n.moreStorageCategorySticky,
      'protected' => l10n.moreStorageCategoryProtected,
      _ => code,
    };
  }

  static String _imageRoleLabel(AppLocalizations l10n, String code) {
    return switch (code) {
      'cover' => l10n.moreStorageImageCover,
      'custom_cover' => l10n.moreStorageImageCustomCover,
      'comic_page' => l10n.moreStorageImageComicPage,
      'novel_inline' => l10n.moreStorageImageNovelInline,
      'thread_inline' => l10n.moreStorageImageThreadInline,
      'thread_attachment' => l10n.moreStorageImageThreadAttachment,
      'avatar' => l10n.moreStorageImageAvatar,
      'remote_smiley' => l10n.moreStorageImageRemoteSmiley,
      'forum_head_image' => l10n.moreStorageImageForumHead,
      'forum_icon' => l10n.moreStorageImageForumIcon,
      'blog_inline' => l10n.moreStorageImageBlogInline,
      'composer_unused_attachment' =>
        l10n.moreStorageImageComposerUnusedAttachment,
      _ => code.isEmpty ? l10n.moreStorageImageUnknown : code,
    };
  }

  static String _imageQualifierLabel(AppLocalizations l10n, String? code) {
    return switch (code) {
      null || '' || 'ephemeral' => '',
      'recent_reader' => l10n.moreStorageImageQualifierRecentReader,
      'sticky' => l10n.moreStorageImageQualifierSticky,
      'protected' => l10n.moreStorageImageQualifierProtected,
      'downloaded' => l10n.moreStorageImageQualifierDownloaded,
      _ => code,
    };
  }

  static String _documentOwnerLabel(AppLocalizations l10n, String code) {
    return switch (code) {
      'forum' => l10n.moreStorageDocumentForum,
      'forum_display' => l10n.moreStorageDocumentForumDisplay,
      'thread' => l10n.moreStorageDocumentThread,
      'tag' => l10n.moreStorageDocumentTag,
      'profile' => l10n.moreStorageDocumentProfile,
      'blog' => l10n.moreStorageDocumentBlog,
      _ => code.isEmpty ? l10n.moreStorageDocumentUnknown : code,
    };
  }

  static String _snapshotLabel(AppLocalizations l10n, String code) {
    return switch (code) {
      'forum.home' => l10n.moreStorageSnapshotForumHome,
      'forum.display' => l10n.moreStorageSnapshotForumDisplay,
      'thread.detail' => l10n.moreStorageSnapshotThreadDetail,
      _ => code.isEmpty ? l10n.moreStorageSnapshotUnknown : code,
    };
  }

  static String _downloadLabel(AppLocalizations l10n, String code) {
    return switch (code) {
      'comics' => l10n.moreStorageDownloadComics,
      'novels' => l10n.moreStorageDownloadNovels,
      'favorites_snapshot' => l10n.moreStorageDownloadFavorites,
      _ => code,
    };
  }

  static String _libraryLabel(AppLocalizations l10n, String code) {
    return switch (code) {
      'comics' => l10n.moreStorageLibraryComics,
      'comic_episodes' => l10n.moreStorageLibraryComicEpisodes,
      'novels' => l10n.moreStorageLibraryNovels,
      'novel_episodes' => l10n.moreStorageLibraryNovelEpisodes,
      'favorites' => l10n.moreStorageLibraryFavorites,
      'library_work_state' => l10n.moreStorageLibraryWorkState,
      'library_episode_state' => l10n.moreStorageLibraryEpisodeState,
      _ => code,
    };
  }
}
