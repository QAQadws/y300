import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/presentation/services/library_detail_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

class UnifiedDetailCatalogSheet extends StatefulWidget {
  const UnifiedDetailCatalogSheet({
    super.key,
    required this.initialCatalogUrl,
    required this.sourceCatalogUrl,
    required this.onSave,
  });

  final String initialCatalogUrl;
  final String? sourceCatalogUrl;
  final Future<DetailCatalogUpdateOutcome> Function(String? catalogUrl) onSave;

  @override
  State<UnifiedDetailCatalogSheet> createState() =>
      _UnifiedDetailCatalogSheetState();
}

class _UnifiedDetailCatalogSheetState extends State<UnifiedDetailCatalogSheet> {
  late final TextEditingController _catalogController;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _catalogController = TextEditingController(text: widget.initialCatalogUrl);
  }

  @override
  void dispose() {
    _catalogController.dispose();
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
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('unified-detail-catalog-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.libraryDetailConfigureCatalog,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('unified-detail-catalog-url-input'),
                controller: _catalogController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.libraryDetailCatalogUrl,
                  helperText: _sourceText(l10n, widget.sourceCatalogUrl),
                  helperMaxLines: 3,
                  errorText: _errorText,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) {
                  if (!_saving) {
                    _save();
                  }
                },
              ),
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
                      key: const Key('unified-detail-save-catalog'),
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
      _errorText = null;
    });
    try {
      final outcome = await widget.onSave(
        _emptyToNull(_catalogController.text),
      );
      if (!mounted) {
        return;
      }
      if (outcome.code == DetailCatalogUpdateOutcomeCode.invalidInput) {
        setState(() {
          _errorText = LibraryDetailTextResolver.catalogInputError(
            AppLocalizations.of(context),
            outcome,
          );
        });
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _errorText = l10n.libraryDetailCatalogSaveFailed(
            LibraryDetailTextResolver.safeError(l10n, error),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

String _sourceText(AppLocalizations l10n, String? sourceCatalogUrl) {
  final source = sourceCatalogUrl?.trim();
  return source == null || source.isEmpty
      ? l10n.libraryDetailCatalogSourceEmpty
      : l10n.libraryDetailCatalogSource(source);
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
