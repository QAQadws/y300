import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

/// A shared navigation/entry icon for new-arrival attention, without a count.
class MessageAttentionIcon extends StatelessWidget {
  const MessageAttentionIcon({
    super.key,
    required this.icon,
    required this.showAttention,
  });

  final IconData icon;
  final bool showAttention;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // This hint merges into the surrounding destination or ListTile action;
      // the decorative dot must not create another accessibility stop.
      hint: showAttention
          ? AppLocalizations.of(context).messageAttentionAvailable
          : null,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 24,
          height: 24,
          child: Badge(
            isLabelVisible: showAttention,
            backgroundColor: Theme.of(context).colorScheme.error,
            smallSize: 7,
            alignment: Alignment.topRight,
            offset: const Offset(2, -2),
            child: Icon(icon),
          ),
        ),
      ),
    );
  }
}
