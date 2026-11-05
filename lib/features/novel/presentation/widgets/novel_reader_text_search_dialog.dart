import 'package:flutter/material.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_search_service.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../services/novel_reader_background_work.dart';

class NovelReaderTextSearchDialog extends StatefulWidget {
  const NovelReaderTextSearchDialog({
    super.key,
    required this.document,
    required this.service,
    this.onClear,
  });

  final NovelReaderDocument document;
  final NovelReaderSearchService service;
  final VoidCallback? onClear;

  @override
  State<NovelReaderTextSearchDialog> createState() =>
      _NovelReaderTextSearchDialogState();
}

class _NovelReaderTextSearchDialogState
    extends State<NovelReaderTextSearchDialog> {
  var _query = '';
  var _revision = 0;
  var _loading = false;
  var _failed = false;
  List<NovelReaderSearchResult>? _results;

  Future<void> _search() async {
    final query = _query.trim();
    if (query.isEmpty || _loading) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _failed = false;
    });
    List<NovelReaderSearchResult>? results;
    try {
      results = await _searchChapter(widget.service, widget.document, query);
    } on Object {
      // The retry action uses the current query without exposing errors.
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (revision == _revision) {
        _results = results;
        _failed = results == null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final results = _results;
    return Dialog(
      child: SizedBox(
        width: 440,
        height: 400,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                key: const Key('novel-reader-text-search-field'),
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                onChanged: (query) => setState(() {
                  _query = query;
                  _revision++;
                  _failed = false;
                  _results = null;
                }),
                decoration: InputDecoration(
                  labelText: l10n.novelSearchText,
                  hintText: l10n.searchInputHint,
                  suffixIcon: IconButton(
                    tooltip: l10n.commonSearch,
                    onPressed: _query.trim().isEmpty || _loading
                        ? null
                        : _search,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: switch ((results, _loading, _failed)) {
                  (_, true, _) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  (_, false, true) => Center(
                    child: TextButton(
                      onPressed: _search,
                      child: Text(l10n.commonRetry),
                    ),
                  ),
                  (null, false, false) => const SizedBox.shrink(),
                  (final matches?, false, false) when matches.isEmpty => Center(
                    child: Text(l10n.searchNoResults),
                  ),
                  (final matches?, false, false) => ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: matches.length,
                    itemBuilder: (context, index) => ListTile(
                      title: Text(matches[index].snippet),
                      onTap: () => Navigator.pop(context, matches[index].range),
                    ),
                  ),
                },
              ),
              if (widget.onClear case final clear?)
                TextButton(
                  onPressed: () {
                    clear();
                    Navigator.pop(context);
                  },
                  child: Text(l10n.historySearchClear),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<List<NovelReaderSearchResult>> _searchChapter(
  NovelReaderSearchService service,
  NovelReaderDocument document,
  String query,
) => NovelReaderBackgroundWork.run(
  codeUnits: document.plainText.length,
  transform: () => service.search(document: document, keyword: query),
);
