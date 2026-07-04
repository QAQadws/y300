import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/composer_bbcode_command.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_color_picker_sheet.dart';

class ComposerBbCodeToolbar extends StatelessWidget {
  const ComposerBbCodeToolbar({
    super.key,
    required this.onStickerPressed,
    required this.onCommandSelected,
    this.enabled = true,
    this.keyPrefix = 'reply-composer',
  });

  final VoidCallback onStickerPressed;
  final ValueChanged<ComposerBbCodeCommand> onCommandSelected;
  final bool enabled;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-sticker-button'),
            tooltip: '表情',
            enabled: enabled,
            icon: Icons.mood,
            onPressed: onStickerPressed,
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-color-button'),
            tooltip: '字体色',
            enabled: enabled,
            icon: Icons.format_color_text,
            onPressed: () {
              _showColorSheet(context);
            },
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-backcolor-button'),
            tooltip: '背景色',
            enabled: enabled,
            icon: Icons.format_color_fill,
            onPressed: () {
              _showBackColorSheet(context);
            },
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-link-button'),
            tooltip: '链接',
            enabled: enabled,
            icon: Icons.add_link,
            onPressed: () {
              _showLinkSheet(context);
            },
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-size-button'),
            tooltip: '字号',
            enabled: enabled,
            icon: Icons.format_size,
            onPressed: () {
              _showSizeSheet(context);
            },
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-align-button'),
            tooltip: '对齐',
            enabled: enabled,
            icon: Icons.format_align_center,
            onPressed: () {
              _showAlignSheet(context);
            },
          ),
          _ToolbarIconButton(
            buttonKey: Key('$keyPrefix-quote-button'),
            tooltip: '引用',
            enabled: enabled,
            icon: Icons.format_quote,
            onPressed: () {
              onCommandSelected(composerQuoteBbCodeCommand);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showColorSheet(BuildContext context) async {
    final color = await showComposerBbCodeColorPickerSheet(
      context: context,
      keyPrefix: '$keyPrefix-color',
      title: '字体色',
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
      title: '背景色',
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
    final link = await showModalBottomSheet<_ComposerLinkDraft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _LinkSheet(keyPrefix: keyPrefix),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          key: Key('$keyPrefix-size-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('字号', style: Theme.of(context).textTheme.titleMedium),
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

class _ComposerLinkDraft {
  const _ComposerLinkDraft({required this.url, required this.label});

  final String url;
  final String label;
}

class _LinkSheet extends StatefulWidget {
  const _LinkSheet({required this.keyPrefix});

  final String keyPrefix;

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  final _urlController = TextEditingController();
  final _labelController = TextEditingController();
  String? _urlErrorText;
  String? _labelErrorText;

  @override
  void dispose() {
    _urlController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: Column(
          key: Key('${widget.keyPrefix}-link-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('添加链接', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              key: Key('${widget.keyPrefix}-link-url-input'),
              controller: _urlController,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '链接',
                hintText: 'https://example.com',
                errorText: _urlErrorText,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearUrlError(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: Key('${widget.keyPrefix}-link-label-input'),
              controller: _labelController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '链接文字',
                hintText: '显示给别人看的文字',
                errorText: _labelErrorText,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearLabelError(),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('${widget.keyPrefix}-link-cancel-button'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: Key('${widget.keyPrefix}-link-use-button'),
                  onPressed: _submit,
                  child: const Text('使用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _clearUrlError() {
    if (_urlErrorText == null) {
      return;
    }
    setState(() {
      _urlErrorText = null;
    });
  }

  void _clearLabelError() {
    if (_labelErrorText == null) {
      return;
    }
    setState(() {
      _labelErrorText = null;
    });
  }

  void _submit() {
    final url = _urlController.text.trim();
    final label = _labelController.text.trim();
    setState(() {
      _urlErrorText = url.isEmpty ? '请输入链接' : null;
      _labelErrorText = label.isEmpty ? '请输入链接文字' : null;
    });
    if (url.isEmpty || label.isEmpty) {
      return;
    }
    Navigator.of(context).pop(_ComposerLinkDraft(url: url, label: label));
  }
}

class _AlignSheet extends StatelessWidget {
  const _AlignSheet({required this.keyPrefix});

  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        key: Key('$keyPrefix-align-sheet'),
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: Key('$keyPrefix-align-left'),
            leading: const Icon(Icons.format_align_left),
            title: const Text('左对齐'),
            onTap: () => Navigator.of(context).pop('left'),
          ),
          ListTile(
            key: Key('$keyPrefix-align-center'),
            leading: const Icon(Icons.format_align_center),
            title: const Text('居中'),
            onTap: () => Navigator.of(context).pop('center'),
          ),
          ListTile(
            key: Key('$keyPrefix-align-right'),
            leading: const Icon(Icons.format_align_right),
            title: const Text('右对齐'),
            onTap: () => Navigator.of(context).pop('right'),
          ),
        ],
      ),
    );
  }
}
