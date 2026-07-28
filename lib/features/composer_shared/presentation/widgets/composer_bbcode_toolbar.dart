import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/composer_bbcode_command.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_color_picker_sheet.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_link_sheet.dart';
import 'package:y300/l10n/app_localizations.dart';

class ComposerBbCodeToolbar extends StatelessWidget {
  const ComposerBbCodeToolbar({
    super.key,
    required this.onStickerPressed,
    required this.onCommandSelected,
    this.onImagePressed,
    this.enabled = true,
    this.keyPrefix = 'reply-composer',
  });

  final VoidCallback onStickerPressed;
  final ValueChanged<ComposerBbCodeCommand> onCommandSelected;
  final VoidCallback? onImagePressed;
  final bool enabled;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-sticker-button'),
            tooltip: l10n.composerSticker,
            enabled: enabled,
            icon: Icons.mood,
            onPressed: onStickerPressed,
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-color-button'),
            tooltip: l10n.composerTextColor,
            enabled: enabled,
            icon: Icons.format_color_text,
            onPressed: () {
              _showColorSheet(context);
            },
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-backcolor-button'),
            tooltip: l10n.composerBackgroundColor,
            enabled: enabled,
            icon: Icons.format_color_fill,
            onPressed: () {
              _showBackColorSheet(context);
            },
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-link-button'),
            tooltip: l10n.composerLink,
            enabled: enabled,
            icon: Icons.add_link,
            onPressed: () {
              _showLinkSheet(context);
            },
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-size-button'),
            tooltip: l10n.composerFontSize,
            enabled: enabled,
            icon: Icons.format_size,
            onPressed: () {
              _showSizeSheet(context);
            },
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-align-button'),
            tooltip: l10n.composerAlignment,
            enabled: enabled,
            icon: Icons.format_align_center,
            onPressed: () {
              _showAlignSheet(context);
            },
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-quote-button'),
            tooltip: l10n.composerQuote,
            enabled: enabled,
            icon: Icons.format_quote,
            onPressed: () {
              onCommandSelected(composerQuoteBbCodeCommand);
            },
          ),
          if (onImagePressed != null)
            _ToolbarIconButton(
              buttonKey: Key('$keyPrefix-image-button'),
              tooltip: l10n.composerImage,
              enabled: enabled,
              icon: Icons.image_outlined,
              onPressed: onImagePressed!,
            ),
        ],
      ),
    );
  }

  Future<void> _showColorSheet(BuildContext context) async {
    final color = await showComposerBbCodeColorPickerSheet(
      context: context,
      keyPrefix: '$keyPrefix-color',
      title: AppLocalizations.of(context).composerTextColor,
      initialColor: const Color(0xffd32f2f),
    );
    if (color == null) {
      return;
    }
    onCommandSelected(
      ComposerBbCodeCommand(
        openingTag: '[color=$color]',
        closingTag: '[/color]',
      ),
    );
  }

  Future<void> _showBackColorSheet(BuildContext context) async {
    final color = await showComposerBbCodeColorPickerSheet(
      context: context,
      keyPrefix: '$keyPrefix-backcolor',
      title: AppLocalizations.of(context).composerBackgroundColor,
      initialColor: const Color(0xfffff3b0),
    );
    if (color == null) {
      return;
    }
    onCommandSelected(
      ComposerBbCodeCommand(
        openingTag: '[backcolor=$color]',
        closingTag: '[/backcolor]',
      ),
    );
  }

  Future<void> _showLinkSheet(BuildContext context) async {
    final link = await showComposerLinkSheet(
      context: context,
      keyPrefix: keyPrefix,
    );
    if (link == null) {
      return;
    }
    onCommandSelected(
      ComposerBbCodeCommand(
        openingTag: '[url=${link.url}]',
        closingTag: '[/url]',
        body: link.label,
      ),
    );
  }

  Future<void> _showSizeSheet(BuildContext context) async {
    final size = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => _SizeSheet(keyPrefix: keyPrefix),
    );
    if (size == null) {
      return;
    }
    onCommandSelected(
      ComposerBbCodeCommand(openingTag: '[size=$size]', closingTag: '[/size]'),
    );
  }

  Future<void> _showAlignSheet(BuildContext context) async {
    final align = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _AlignSheet(keyPrefix: keyPrefix),
    );
    if (align == null) {
      return;
    }
    onCommandSelected(
      ComposerBbCodeCommand(
        openingTag: '[align=$align]',
        closingTag: '[/align]',
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.enabled,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
    );
  }
}

class _SizeSheet extends StatelessWidget {
  const _SizeSheet({required this.keyPrefix});

  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          key: Key('$keyPrefix-size-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.composerFontSize,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var size = 1; size <= 7; size += 1)
                  ChoiceChip(
                    key: Key('$keyPrefix-size-$size'),
                    label: Text(size.toString()),
                    selected: size == 3,
                    onSelected: (_) {
                      Navigator.of(context).pop(size);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AlignSheet extends StatelessWidget {
  const _AlignSheet({required this.keyPrefix});

  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        key: Key('$keyPrefix-align-sheet'),
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: Key('$keyPrefix-align-left'),
            leading: const Icon(Icons.format_align_left),
            title: Text(l10n.composerAlignLeft),
            onTap: () => Navigator.of(context).pop('left'),
          ),
          ListTile(
            key: Key('$keyPrefix-align-center'),
            leading: const Icon(Icons.format_align_center),
            title: Text(l10n.composerAlignCenter),
            onTap: () => Navigator.of(context).pop('center'),
          ),
          ListTile(
            key: Key('$keyPrefix-align-right'),
            leading: const Icon(Icons.format_align_right),
            title: Text(l10n.composerAlignRight),
            onTap: () => Navigator.of(context).pop('right'),
          ),
        ],
      ),
    );
  }
}
