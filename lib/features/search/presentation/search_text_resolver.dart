import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/presentation/services/library_task_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

sealed class SearchNotice {
  const SearchNotice();
}

final class SearchRateLimitedNotice extends SearchNotice {
  const SearchRateLimitedNotice(this.seconds);

  final int seconds;
}

final class SearchNoResultsNotice extends SearchNotice {
  const SearchNoResultsNotice();
}

final class SearchFailedNotice extends SearchNotice {
  const SearchFailedNotice(this.detail);

  final Object detail;
}

final class SearchLoadMoreFailedNotice extends SearchNotice {
  const SearchLoadMoreFailedNotice(this.detail);

  final Object detail;
}

final class SearchQueueWaitingNotice extends SearchNotice {
  const SearchQueueWaitingNotice({this.subject, required this.estimatedWait});

  final String? subject;
  final Duration estimatedWait;
}

final class SearchLibraryTaskNotice extends SearchNotice {
  const SearchLibraryTaskNotice(this.progress);

  final LibraryShelfTaskProgress progress;
}

abstract final class SearchTextResolver {
  static String notice(AppLocalizations l10n, SearchNotice notice) {
    return switch (notice) {
      SearchRateLimitedNotice(:final seconds) => l10n.searchRetryAfter(seconds),
      SearchNoResultsNotice() => l10n.searchNoResults,
      SearchFailedNotice(:final detail) => l10n.searchFailed(
        LocalizedErrorSummary.resolve(l10n, detail),
      ),
      SearchLoadMoreFailedNotice(:final detail) => l10n.searchLoadMoreFailed(
        LocalizedErrorSummary.resolve(l10n, detail),
      ),
      SearchQueueWaitingNotice(:final subject, :final estimatedWait) =>
        l10n.searchQueueWaiting(
          subject?.trim().isNotEmpty == true
              ? subject!.trim()
              : l10n.searchForumFallback,
          _formatSeconds(estimatedWait),
        ),
      SearchLibraryTaskNotice(:final progress) =>
        LibraryTaskTextResolver.message(l10n, progress),
    };
  }

  static String _formatSeconds(Duration duration) {
    final tenths = (duration.inMilliseconds / 100).round();
    if (tenths % 10 == 0) {
      return '${tenths ~/ 10}';
    }
    return (tenths / 10).toStringAsFixed(1);
  }
}
