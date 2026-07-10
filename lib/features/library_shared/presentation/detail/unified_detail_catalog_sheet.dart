import 'package:flutter/material.dart';

class UnifiedDetailCatalogSheet extends StatefulWidget {
  const UnifiedDetailCatalogSheet({
    super.key,
    required this.initialCatalogUrl,
    required this.sourceCatalogUrl,
    required this.onSave,
  });

  final String initialCatalogUrl;
  final String? sourceCatalogUrl;
  final Future<void> Function(String? catalogUrl) onSave;

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
              Text('配置目录', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                key: const Key('unified-detail-catalog-url-input'),
                controller: _catalogController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '目录 URL',
                  helperText: _sourceText(widget.sourceCatalogUrl),
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
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const Key('unified-detail-save-catalog'),
                      onPressed: _saving ? null : _save,
                      child: const Text('保存'),
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
      await widget.onSave(_emptyToNull(_catalogController.text));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _errorText = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorText = '保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

String _sourceText(String? sourceCatalogUrl) {
  final source = sourceCatalogUrl?.trim();
  return '来源目录：${source == null || source.isEmpty ? '无' : source}';
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
