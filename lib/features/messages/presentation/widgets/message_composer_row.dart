import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Shared action geometry for conversations and the new-message form.
class MessageComposerRow extends StatelessWidget {
  const MessageComposerRow({
    super.key,
    required this.input,
    required this.busy,
    required this.onSend,
    this.emphasized = false,
  });

  final Widget input;
  final bool busy;
  final VoidCallback? onSend;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = Theme.of(context).y300NativeContent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: input),
        const SizedBox(width: 4),
        SizedBox.square(
          dimension: 48,
          child: IconButton(
            key: const Key('message-send'),
            tooltip: busy ? l10n.messageSending : l10n.messageSend,
            onPressed: onSend,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: emphasized ? palette.onAccent : palette.accent,
              disabledForegroundColor: palette.disabled,
              backgroundColor: emphasized ? palette.accent : Colors.transparent,
              disabledBackgroundColor: emphasized
                  ? palette.panelBackground
                  : Colors.transparent,
              shape: emphasized
                  ? const CircleBorder()
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
            ),
            icon: busy
                ? SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: emphasized ? palette.onAccent : palette.accent,
                    ),
                  )
                : Icon(
                    emphasized ? Icons.arrow_upward : Icons.send_outlined,
                    size: 28,
                  ),
          ),
        ),
      ],
    );
  }
}
