import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/l10n/app_localizations.dart';

/// A compact directory preview never loads inline images or changes identity.
class MessagePreviewText extends ConsumerStatefulWidget {
  const MessagePreviewText({super.key, required this.markup});
  final String markup;

  @override
  ConsumerState<MessagePreviewText> createState() => _MessagePreviewTextState();
}

class _MessagePreviewTextState extends ConsumerState<MessagePreviewText> {
  Object? _identity;
  String _source = '';
  Future<String>? _converted;

  @override
  Widget build(BuildContext context) {
    final preferences =
        ref.watch(forumHtmlReaderPreferencesControllerProvider).value ??
        ForumHtmlReaderPreferences.defaults();
    final converter = ref.watch(
      textConverterProvider(preferences.conversionMode),
    );
    final identity = (widget.markup, converter);
    if (_identity != identity) {
      _identity = identity;
      final fragment = html.parseFragment(widget.markup);
      for (final element in fragment.querySelectorAll('script, style')) {
        element.remove();
      }
      // Block boundaries must survive HTML-to-text extraction; otherwise
      // adjacent paragraphs and line breaks join unrelated words together.
      for (final element in fragment.querySelectorAll(
        'p, div, li, blockquote, pre, h1, h2, h3, h4, h5, h6, tr, br',
      )) {
        element.nodes.insert(0, dom.Text(' '));
        element.nodes.add(dom.Text(' '));
      }
      _source = (fragment.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final source = _source;
      // This future belongs to this row; FutureBuilder rejects older results
      // when the preview or display preference changes.
      _converted = Future.sync(
        () => converter.convertHtml(source),
      ).catchError((Object _) => source);
    }
    final style = Theme.of(context).textTheme.bodyMedium;
    return FutureBuilder<String>(
      key: ValueKey(_identity),
      future: _converted,
      initialData: _source,
      builder: (context, snapshot) => Text(
        snapshot.data?.isNotEmpty == true
            ? snapshot.data!
            : AppLocalizations.of(context).messageNoPreview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style?.copyWith(
          fontSize: (style.fontSize ?? 14) * preferences.typography.fontScale,
        ),
      ),
    );
  }
}
