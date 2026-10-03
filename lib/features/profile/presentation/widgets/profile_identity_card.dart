import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// The profile shares More's avatar/statistics composition without its account state.
class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    super.key,
    required this.profile,
    required this.metrics,
    required this.avatarUrl,
    required this.imageReferer,
    required this.onCopyUid,
    this.footer,
  });

  final ForumUserProfileData profile;
  final List<ForumUserProfileMetric> metrics;
  final String? avatarUrl;
  final String imageReferer;
  final VoidCallback onCopyUid;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const Key('user-profile-identity'),
      margin: EdgeInsets.zero,
      color: theme.y300NativeContent.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final avatar = Semantics(
              image: true,
              label: l10n.moreAccountAvatar(
                profile.identity.displayName ?? profile.identity.userId,
              ),
              excludeSemantics: true,
              child: ForumCachedAvatar(
                key: const Key('user-profile-avatar'),
                imageUrl: avatarUrl,
                ownerId: profile.identity.userId,
                ownerType: ImageCacheOwnerType.profile,
                size: 72,
                imageReferer: imageReferer,
                fallbackPolicy: ForumAvatarFallbackPolicy.localDefaultAvatar,
              ),
            );
            final heading = _IdentityHeading(
              profile: profile,
              onCopyUid: onCopyUid,
            );
            final customTitle = profile.customTitle?.trim() ?? '';
            final inline =
                metrics.isNotEmpty &&
                constraints.maxWidth >= 280 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20 &&
                _statisticsFit(context, metrics, constraints.maxWidth - 88);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    avatar,
                    if (inline) ...[
                      const SizedBox(width: 16),
                      Expanded(child: _Statistics(metrics: metrics)),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                heading,
                const SizedBox(height: 4),
                _CustomTitle(title: customTitle),
                if (!inline && metrics.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _Statistics(metrics: metrics),
                ],
                if (footer != null) ...[const SizedBox(height: 12), footer!],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IdentityHeading extends StatelessWidget {
  const _IdentityHeading({required this.profile, required this.onCopyUid});
  final ForumUserProfileData profile;
  final VoidCallback onCopyUid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final displayName = profile.identity.displayName ?? profile.identity.userId;
    final nameStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: theme.y300NativeContent.itemTitle,
    );
    final name = Tooltip(
      message: displayName,
      excludeFromSemantics: true,
      child: Text(
        displayName,
        key: const Key('user-profile-name'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: nameStyle,
      ),
    );
    final group = profile.groupName?.trim() ?? '';
    final labels = [
      if (group.isNotEmpty) group,
      if (profile.isOnline == true) l10n.profileOnline,
    ];
    final identity = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        name,
        for (final label in labels) _Badge(label: label),
      ],
    );
    final uid = l10n.profileUid(profile.identity.userId);
    final copyUid = Tooltip(
      message: l10n.profileCopyUid,
      child: TextButton(
        key: const Key('user-profile-copy-uid'),
        onPressed: onCopyUid,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(
          uid,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final uidWidth =
            _textWidth(context, uid, theme.textTheme.bodySmall) + 16;
        final identityWidth = labels.fold<double>(
          _textWidth(context, displayName, nameStyle),
          (width, label) =>
              width +
              8 +
              _textWidth(context, label, theme.textTheme.labelSmall) +
              12,
        );
        final inline =
            scaler.scale(14) <= 20 &&
            identityWidth + 8 + uidWidth <= constraints.maxWidth;
        if (inline) {
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 8),
              copyUid,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            Align(alignment: Alignment.centerRight, child: copyUid),
          ],
        );
      },
    );
  }
}

class _CustomTitle extends StatelessWidget {
  const _CustomTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: title,
      excludeFromSemantics: true,
      child: Text(
        // Keep one line so an absent title does not change the identity card height.
        title.isEmpty ? ' ' : title,
        key: const Key('user-profile-custom-title'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.y300NativeContent.supportingText,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _Statistics extends StatelessWidget {
  const _Statistics({required this.metrics});
  final List<ForumUserProfileMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('user-profile-metrics'),
      builder: (context, constraints) {
        // Reflow rather than split an ordinary balance or shrink accessibility text.
        if (!_statisticsFit(context, metrics, constraints.maxWidth)) {
          return Column(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                _Statistic(metric: metrics[index], stacked: true),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              if (index > 0)
                const SizedBox(
                  height: 32,
                  width: 16,
                  child: VerticalDivider(indent: 5, endIndent: 5),
                ),
              Expanded(child: _Statistic(metric: metrics[index])),
            ],
          ],
        );
      },
    );
  }
}

class _Statistic extends StatelessWidget {
  const _Statistic({required this.metric, this.stacked = false});
  final ForumUserProfileMetric metric;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayValue = _statisticValue(metric);
    final description = AppLocalizations.of(
      context,
    ).moreAccountStatistic(metric.label, displayValue);
    final value = Text(
      displayValue,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: stacked ? TextAlign.end : TextAlign.center,
      style: _statisticValueStyle(theme),
    );
    final label = Text(
      metric.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: stacked ? TextAlign.start : TextAlign.center,
      style: _statisticLabelStyle(theme),
    );
    return Semantics(
      label: description,
      excludeSemantics: true,
      child: Tooltip(
        message: description,
        excludeFromSemantics: true,
        child: stacked
            ? Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 16),
                  Flexible(child: value),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [value, const SizedBox(height: 2), label],
              ),
      ),
    );
  }
}

TextStyle? _statisticValueStyle(ThemeData theme) => theme.textTheme.bodyMedium
    ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

TextStyle? _statisticLabelStyle(ThemeData theme) =>
    theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    );

final _creditPoints = RegExp(r'^([+-]?\d[\d,]*(?:\.\d+)?)\s*点$');

String _statisticValue(ForumUserProfileMetric metric) {
  const creditLabels = {'积分', '積分'};
  if (!creditLabels.contains(metric.label.trim())) return metric.value;
  return _creditPoints.firstMatch(metric.value.trim())?.group(1) ??
      metric.value;
}

bool _statisticsFit(
  BuildContext context,
  List<ForumUserProfileMetric> metrics,
  double width,
) {
  final theme = Theme.of(context);
  final columnWidth = (width - (metrics.length - 1) * 16) / metrics.length;
  for (final metric in metrics) {
    for (final entry in [
      (_statisticValue(metric), _statisticValueStyle(theme)),
      (metric.label, _statisticLabelStyle(theme)),
    ]) {
      if (_textWidth(context, entry.$1, entry.$2) + 2 > columnWidth) {
        return false;
      }
    }
  }
  return true;
}

double _textWidth(BuildContext context, String text, TextStyle? style) {
  // Match Text's inherited style and accessibility overrides before deciding to reflow.
  var effectiveStyle = style == null || style.inherit
      ? DefaultTextStyle.of(context).style.merge(style)
      : style;
  if (MediaQuery.boldTextOf(context)) {
    effectiveStyle = effectiveStyle.merge(
      const TextStyle(fontWeight: FontWeight.bold),
    );
  }
  effectiveStyle = effectiveStyle.copyWith(
    letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
    wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
  );
  final measurement = TextPainter(
    text: TextSpan(text: text, style: effectiveStyle),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout();
  final width = measurement.width;
  measurement.dispose();
  return width;
}
