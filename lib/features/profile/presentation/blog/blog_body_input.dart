import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/profile/presentation/blog/blog_body_text_codec.dart';
import 'package:y300/l10n/app_localizations.dart';

class BlogBodyInput extends StatefulWidget {
  const BlogBodyInput({
    super.key,
    required this.html,
    required this.enabled,
    required this.readOnly,
    required this.onChanged,
  });
  final String html;
  final bool enabled;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  @override
  State<BlogBodyInput> createState() => _BlogBodyInputState();
}

class _BlogBodyInputState extends State<BlogBodyInput> {
  late final TextEditingController _text;
  late String _source;
  late bool _htmlMode;

  @override
  void initState() {
    super.initState();
    _source = widget.html;
    final plain = BlogBodyTextCodec.decode(_source);
    _htmlMode = plain == null;
    _text = TextEditingController(text: plain ?? _source);
  }

  @override
  void didUpdateWidget(covariant BlogBodyInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_source == widget.html) return;
    _source = widget.html;
    if (BlogBodyTextCodec.decode(_source) == null) _htmlMode = true;
    _replaceText();
  }

  void _replaceText() {
    final value = _htmlMode ? _source : BlogBodyTextCodec.decode(_source)!;
    _text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _changeMode(bool html) {
    if (html == _htmlMode) return;
    setState(() {
      _htmlMode = html;
      _replaceText();
    });
    // Switching representation alone does not rewrite the stored HTML.
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final native = Theme.of(context).y300NativeContent;
    final canUseText = BlogBodyTextCodec.decode(_source) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              key: const Key('blog-body-text-mode'),
              label: Text(l10n.profileBlogPlainText),
              selected: !_htmlMode,
              onSelected: widget.enabled && canUseText
                  ? (_) => _changeMode(false)
                  : null,
            ),
            ChoiceChip(
              key: const Key('blog-body-html-mode'),
              label: Text(l10n.profileBlogHtmlSource),
              selected: _htmlMode,
              onSelected: widget.enabled ? (_) => _changeMode(true) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_htmlMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.profileBlogHtmlHint,
              style: TextStyle(color: native.supportingText),
            ),
          ),
        TextField(
          key: const Key('blog-editor-body'),
          controller: _text,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          minLines: 8,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          autocorrect: !_htmlMode,
          enableSuggestions: !_htmlMode,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          style: TextStyle(color: native.body),
          decoration: InputDecoration(
            labelText: l10n.profileBlogBody,
            alignLabelWithHint: true,
          ),
          onChanged: (text) {
            if (!widget.enabled || widget.readOnly) return;
            _source = _htmlMode ? text : BlogBodyTextCodec.encode(text);
            widget.onChanged(_source);
          },
        ),
      ],
    );
  }
}
