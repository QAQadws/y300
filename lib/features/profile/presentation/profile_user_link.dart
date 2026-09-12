import 'package:flutter/material.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/l10n/app_localizations.dart';

/// User references come from the source contract, never from a displayed name.
class ProfileUserLink extends StatelessWidget {
  const ProfileUserLink({
    super.key,
    required this.userId,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  final String? userId;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final id = userId;
    if (id == null || !RegExp(r'^[1-9]\d*$').hasMatch(id)) return child;
    return Tooltip(
      message: AppLocalizations.of(context).profileTitle,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => UserProfilePage(uid: id)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Align(alignment: alignment, widthFactor: 1, child: child),
          ),
        ),
      ),
    );
  }
}
