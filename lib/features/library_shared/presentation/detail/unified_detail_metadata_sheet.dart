import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/presentation/services/library_detail_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

class UnifiedDetailMetadataSheet extends StatefulWidget {
  const UnifiedDetailMetadataSheet({
    super.key,
    required this.initialTitle,
    required this.initialAuthor,
    required this.initialTranslationGroup,
    required this.initialSearchTitle,
    required this.titleSourceText,
    required this.authorSourceText,
    required this.groupSourceText,
    required this.fields,
    required this.onSave,
  });

  final String initialTitle;
  final String initialAuthor;
  final String initialTranslationGroup;
  final String initialSearchTitle;
  final String titleSourceText;
  final String authorSourceText;
  final String groupSourceText;
  final Set<LibraryMetadataField> fields;
  final Future<void> Function({
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  })
  onSave;

  @override
  State<UnifiedDetailMetadataSheet> createState() =>
      _UnifiedDetailMetadataSheetState();
}

class _UnifiedDetailMetadataSheetState
    extends State<UnifiedDetailMetadataSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _authorController;
  late final TextEditingController _groupController;
  late final TextEditingController _searchController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _authorController = TextEditingController(text: widget.initialAuthor);
    _groupController = TextEditingController(
      text: widget.initialTranslationGroup,
    );
    _searchController = TextEditingController(text: widget.initialSearchTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _groupController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('unified-detail-metadata-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.libraryDetailEditMetadata,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (widget.fields.contains(LibraryMetadataField.title))
                _MetadataTextField(
                  fieldKey: const Key('unified-detail-custom-title-input'),
                  controller: _titleController,
                  label: LibraryDetailTextResolver.metadataField(
                    l10n,
                    LibraryMetadataField.title,
                  ),
                  sourceText: widget.titleSourceText,
                ),
              if (widget.fields.contains(LibraryMetadataField.author)) ...[
                const SizedBox(height: 10),
                _MetadataTextField(
                  fieldKey: const Key('unified-detail-custom-author-input'),
                  controller: _authorController,
                  label: LibraryDetailTextResolver.metadataField(
                    l10n,
                    LibraryMetadataField.author,
                  ),
                  sourceText: widget.authorSourceText,
                ),
              ],
              if (widget.fields.contains(
                LibraryMetadataField.translationGroup,
              )) ...[
                const SizedBox(height: 10),
                _MetadataTextField(
                  fieldKey: const Key('unified-detail-custom-group-input'),
                  controller: _groupController,
                  label: LibraryDetailTextResolver.metadataField(
                    l10n,
                    LibraryMetadataField.translationGroup,
                  ),
                  sourceText: widget.groupSourceText,
                ),
              ],
              if (widget.fields.contains(LibraryMetadataField.searchTitle)) ...[
                const SizedBox(height: 10),
                _MetadataTextField(
                  fieldKey: const Key(
                    'unified-detail-custom-search-title-input',
                  ),
                  controller: _searchController,
                  label: LibraryDetailTextResolver.metadataField(
                    l10n,
                    LibraryMetadataField.searchTitle,
                  ),
                  sourceText: l10n.libraryDetailMetadataSearchHelp,
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const Key('unified-detail-save-metadata'),
                      onPressed: _saving ? null : _save,
                      child: Text(l10n.commonSave),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      await widget.onSave(
        customTitle: widget.fields.contains(LibraryMetadataField.title)
            ? _emptyToNull(_titleController.text)
            : null,
        customAuthor: widget.fields.contains(LibraryMetadataField.author)
            ? _emptyToNull(_authorController.text)
            : null,
        customTranslationGroup:
            widget.fields.contains(LibraryMetadataField.translationGroup)
            ? _emptyToNull(_groupController.text)
            : null,
        customSearchTitle:
            widget.fields.contains(LibraryMetadataField.searchTitle)
            ? _emptyToNull(_searchController.text)
            : null,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}

class _MetadataTextField extends StatelessWidget {
  const _MetadataTextField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.sourceText,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String sourceText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: sourceText,
        helperMaxLines: 2,
      ),
    );
  }
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
