import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_page.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_renderer_prototype_page.dart';
import 'package:y300/l10n/app_localizations.dart';

class MoreDebugTools {
  const MoreDebugTools();

  List<Widget> buildTiles(BuildContext context, AppLocalizations l10n) {
    if (!kDebugMode) {
      return const <Widget>[];
    }
    return <Widget>[
      ListTile(
        key: const Key('more-composer-quill-prototype-entry'),
        leading: const Icon(Icons.edit_note_outlined),
        title: Text(l10n.moreDebugQuillComposer),
        subtitle: Text(l10n.moreDebugQuillComposerSubtitle),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ComposerQuillPrototypePage(),
            ),
          );
        },
      ),
      ListTile(
        key: const Key('more-html-renderer-prototype-entry'),
        leading: const Icon(Icons.article_outlined),
        title: Text(l10n.moreDebugHtmlRenderer),
        subtitle: Text(l10n.moreDebugHtmlRendererSubtitle),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ForumHtmlRendererPrototypePage(),
            ),
          );
        },
      ),
    ];
  }
}
