import 'package:intl/intl.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_date_grouping_policy.dart';
import 'package:y300/l10n/app_localizations.dart';

final class HistoryTextResolver {
  const HistoryTextResolver._();

  static String typeLabel(AppLocalizations l10n, HistoryTargetType type) {
    return switch (type) {
      HistoryTargetType.thread => l10n.historyTypeThread,
      HistoryTargetType.comic => l10n.historyTypeComic,
      HistoryTargetType.novel => l10n.historyTypeNovel,
    };
  }

  static String dateGroupLabel(AppLocalizations l10n, HistoryDateGroup group) {
    if (group.daysAgo == 0) {
      return l10n.historyToday;
    }
    if (group.daysAgo >= 1 && group.daysAgo <= 6) {
      return l10n.historyDaysAgo(group.daysAgo);
    }
    return DateFormat.yMd(l10n.localeName).format(group.localDate);
  }

  static String unavailableMessage(
    AppLocalizations l10n,
    HistoryOpenUnavailable result,
  ) {
    return switch (result.code) {
      HistoryOpenUnavailableCode.targetMissing => l10n.historyTargetInvalid,
      HistoryOpenUnavailableCode.pageClosed => l10n.historyPageClosed,
      HistoryOpenUnavailableCode.threadExpired => l10n.historyThreadExpired,
      HistoryOpenUnavailableCode.localWorkRemoved =>
        result.targetType == null
            ? l10n.historyTargetInvalid
            : l10n.historyWorkUnavailable(typeLabel(l10n, result.targetType!)),
      HistoryOpenUnavailableCode.nativeUnavailable =>
        l10n.historyNativeUnavailable,
      HistoryOpenUnavailableCode.loginRequired => l10n.historyLoginRequired,
      HistoryOpenUnavailableCode.legacyMessage =>
        _nonEmpty(result.message) ?? l10n.historyTargetInvalid,
    };
  }

  static String? safeErrorSummary(Object? error) {
    final value = error?.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final redacted = value
        .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[url]')
        .replaceAll(
          RegExp(
            r'(cookie|formhash|uploadhash)\s*[:=]\s*\S+',
            caseSensitive: false,
          ),
          '[redacted]',
        );
    return redacted.length <= 160
        ? redacted
        : '${redacted.substring(0, 157)}...';
  }

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
