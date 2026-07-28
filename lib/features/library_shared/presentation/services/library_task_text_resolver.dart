import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_bridge.dart';
import 'package:y300/l10n/app_localizations.dart';

abstract final class LibraryTaskTextResolver {
  static String message(
    AppLocalizations l10n,
    LibraryShelfTaskProgress progress,
  ) {
    final subject = progress.subject;
    return switch (progress.code) {
      LibraryShelfTaskProgressCode.coverWarmup => l10n.libraryTaskCoverWarmup,
      LibraryShelfTaskProgressCode.favoriteSyncFetching =>
        l10n.libraryTaskFavoriteSyncFetching,
      LibraryShelfTaskProgressCode.favoriteSyncSaving =>
        l10n.libraryTaskFavoriteSyncSaving,
      LibraryShelfTaskProgressCode.favoriteSyncLoadingDetails =>
        subject == null || subject.trim().isEmpty
            ? l10n.libraryTaskFavoriteSyncLoadingDetails
            : l10n.libraryTaskFavoriteSyncLoadingDetailsSubject(subject),
      LibraryShelfTaskProgressCode.favoriteSyncFinishing =>
        l10n.libraryTaskFavoriteSyncFinishing,
      LibraryShelfTaskProgressCode.comicSearchWaiting => _comicSearchMessage(
        l10n,
        subject,
        progress.estimatedDuration,
      ),
    };
  }

  static LibraryTaskNotificationText notification(
    AppLocalizations l10n,
    LibraryShelfTaskProgress progress,
  ) {
    final title = switch (progress.code) {
      LibraryShelfTaskProgressCode.favoriteSyncFetching ||
      LibraryShelfTaskProgressCode.favoriteSyncSaving ||
      LibraryShelfTaskProgressCode.favoriteSyncLoadingDetails ||
      LibraryShelfTaskProgressCode.favoriteSyncFinishing =>
        l10n.libraryTaskFavoriteSyncNotificationTitle,
      LibraryShelfTaskProgressCode.comicSearchWaiting =>
        l10n.libraryTaskComicSearchNotificationTitle,
      LibraryShelfTaskProgressCode.coverWarmup =>
        l10n.libraryTaskNotificationTitle,
    };
    return LibraryTaskNotificationText(
      title: title,
      body: message(l10n, progress),
    );
  }

  static String duration(AppLocalizations l10n, Duration value) {
    final seconds = value.inMilliseconds <= 0
        ? 1
        : (value.inMilliseconds / Duration.millisecondsPerSecond).ceil();
    if (seconds < 60) {
      return l10n.libraryTaskDurationSeconds(seconds);
    }
    return l10n.libraryTaskDurationMinutes((seconds / 60).ceil());
  }

  static String _comicSearchMessage(
    AppLocalizations l10n,
    String? subject,
    Duration? estimatedDuration,
  ) {
    if (subject == null || subject.trim().isEmpty) {
      return l10n.libraryTaskComicSearchWaiting;
    }
    if (estimatedDuration == null) {
      return l10n.libraryTaskComicSearchWaitingSubject(subject);
    }
    return l10n.libraryTaskComicSearchWaitingDuration(
      subject,
      duration(l10n, estimatedDuration),
    );
  }
}
