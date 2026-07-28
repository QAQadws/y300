import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

final class ComposerLinkDraft {
  const ComposerLinkDraft({required this.url, required this.label});

  final String url;
  final String label;
}

Future<ComposerLinkDraft?> showComposerLinkSheet({
  required BuildContext context,
  required String keyPrefix,
}) {
  return showModalBottomSheet<ComposerLinkDraft>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ComposerLinkSheet(keyPrefix: keyPrefix),
  );
}

class _ComposerLinkSheet extends StatefulWidget {
  const _ComposerLinkSheet({required this.keyPrefix});

  final String keyPrefix;

  @override
  State<_ComposerLinkSheet> createState() => _ComposerLinkSheetState();
}

class _ComposerLinkSheetState extends State<_ComposerLinkSheet> {
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
    final l10n = AppLocalizations.of(context);
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
            Text(
              l10n.composerLinkTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              key: Key('${widget.keyPrefix}-link-url-input'),
              controller: _urlController,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.composerLinkUrl,
                hintText: l10n.composerLinkUrlHint,
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
                labelText: l10n.composerLinkText,
                hintText: l10n.composerLinkTextHint,
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
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: Key('${widget.keyPrefix}-link-use-button'),
                  onPressed: _submit,
                  child: Text(l10n.commonUse),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _clearUrlError() {
    if (_urlErrorText != null) {
      setState(() => _urlErrorText = null);
    }
  }

  void _clearLabelError() {
    if (_labelErrorText != null) {
      setState(() => _labelErrorText = null);
    }
  }

  void _submit() {
    final url = _urlController.text.trim();
    final label = _labelController.text.trim();
    setState(() {
      final l10n = AppLocalizations.of(context);
      _urlErrorText = url.isEmpty ? l10n.composerLinkUrlRequired : null;
      _labelErrorText = label.isEmpty ? l10n.composerLinkTextRequired : null;
    });
    if (url.isEmpty || label.isEmpty) {
      return;
    }
    Navigator.of(context).pop(ComposerLinkDraft(url: url, label: label));
  }
}
