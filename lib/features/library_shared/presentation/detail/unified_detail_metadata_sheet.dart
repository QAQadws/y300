import 'package:flutter/material.dart';

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
    this.authorLabel = '作者',
    this.translationGroupLabel = '汉化组',
    this.showAuthor = true,
    this.showTranslationGroup = true,
    this.showSearchTitle = true,
    required this.onSave,
  });

  final String initialTitle;
  final String initialAuthor;
  final String initialTranslationGroup;
  final String initialSearchTitle;
  final String titleSourceText;
  final String authorSourceText;
  final String groupSourceText;
  final String authorLabel;
  final String translationGroupLabel;
  final bool showAuthor;
  final bool showTranslationGroup;
  final bool showSearchTitle;
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
              Text('编辑作品信息', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _MetadataTextField(
                fieldKey: const Key('unified-detail-custom-title-input'),
                controller: _titleController,
                label: '标题',
                sourceText: widget.titleSourceText,
              ),
              if (widget.showAuthor) ...[
                const SizedBox(height: 10),
                _MetadataTextField(
                  fieldKey: const Key('unified-detail-custom-author-input'),
                  controller: _authorController,
                  label: widget.authorLabel,
                  sourceText: widget.authorSourceText,
                ),
              ],
              if (widget.showTranslationGroup) ...[
                const SizedBox(height: 10),
                _MetadataTextField(
                  fieldKey: const Key('unified-detail-custom-group-input'),
                  controller: _groupController,
                  label: widget.translationGroupLabel,
                  sourceText: widget.groupSourceText,
                ),
              ],
              if (widget.showSearchTitle) ...[
                const SizedBox(height: 10),
                _MetadataTextField(
                  fieldKey: const Key(
                    'unified-detail-custom-search-title-input',
                  ),
                  controller: _searchController,
                  label: '更新搜索关键词',
                  sourceText: '留空时优先使用自定义标题，否则使用当前作品标题',
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
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const Key('unified-detail-save-metadata'),
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
    });
    try {
      await widget.onSave(
        customTitle: _emptyToNull(_titleController.text),
        customAuthor: _emptyToNull(_authorController.text),
        customTranslationGroup: _emptyToNull(_groupController.text),
        customSearchTitle: _emptyToNull(_searchController.text),
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
