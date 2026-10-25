import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/fonts/application/font_library_providers.dart';
import 'package:y300/features/fonts/domain/models/font_identity.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/resolved_font.dart';
import 'package:y300/features/fonts/presentation/font_selector_controller.dart';
import 'package:y300/l10n/app_localizations.dart';

Future<ResolvedFont?> showBodyFontSelector({
  required BuildContext context,
  String? initialFontId,
  TextStyle? previewStyle,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final service = container.read(fontLibraryServiceProvider);
  final picker = container.read(fontImportPickerProvider);
  final controller = FontSelectorController(
    listFonts: service.listFonts,
    resolveFont: service.resolveFont,
    importFont: service.importFont,
    deleteFont: service.deleteFont,
    pickFont: picker.pickFont,
    initialFontId: initialFontId,
    changes: service.changes,
  );
  unawaited(controller.initialize());
  try {
    return await showModalBottomSheet<ResolvedFont>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (_) =>
          BodyFontSelector(controller: controller, previewStyle: previewStyle),
    );
  } finally {
    controller.dispose();
  }
}

/// The host owns [controller] and initializes/disposes its dialog-local draft.
class BodyFontSelector extends StatelessWidget {
  const BodyFontSelector({
    required this.controller,
    this.previewStyle,
    super.key,
  });

  final FontSelectorController controller;
  final TextStyle? previewStyle;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final failure = controller.failure;
        final selected = controller.selectedFont;
        // copyWith(null) retains the caller's family, so explicitly reset it
        // when previewing the system font after a custom font was selected.
        final sampleStyle =
            (previewStyle ?? theme.textTheme.bodyLarge ?? const TextStyle())
                .copyWith(
                  fontFamily: selected.fontFamily ?? '',
                  fontFamilyFallback: const [],
                );
        return ConstrainedBox(
          key: const Key('body-font-selector'),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.fontSelectorTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('body-font-import'),
                      onPressed: controller.canMutate
                          ? controller.importFont
                          : null,
                      icon: controller.isImporting
                          ? SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: l10n.fontSelectorLoading,
                              ),
                            )
                          : const Icon(Icons.add),
                      label: Text(l10n.fontSelectorImport),
                    ),
                  ],
                ),
              ),
              if (failure != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _failureMessage(l10n, failure),
                          key: const Key('body-font-error'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                      TextButton(
                        key: const Key('body-font-retry'),
                        onPressed: controller.canMutate
                            ? controller.retry
                            : null,
                        child: Text(l10n.commonRetry),
                      ),
                    ],
                  ),
                ),
              // A short library sets the sheet height. Only the list consumes
              // remaining space and scrolls once the screen limit is reached.
              Flexible(
                child: ListView(
                  key: const Key('body-font-list'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _fontRow(
                      context,
                      id: FontIdentity.system,
                      label: l10n.fontSelectorSystemDefault,
                    ),
                    for (final font in controller.fonts)
                      _fontRow(
                        context,
                        id: font.id,
                        label: font.displayName,
                        removable: true,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              l10n.fontSelectorPreview,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedFontLabel(l10n),
                                key: const Key('body-font-preview-name'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.24,
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              l10n.fontSelectorSample,
                              key: const Key('body-font-preview'),
                              style: sampleStyle,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.fontSelectorGlyphSample,
                          key: const Key('body-font-preview-glyphs'),
                          style: sampleStyle.copyWith(
                            fontSize: theme.textTheme.bodySmall?.fontSize ?? 12,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    children: [
                      TextButton(
                        key: const Key('body-font-cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.commonCancel),
                      ),
                      FilledButton(
                        key: const Key('body-font-apply'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(112, 44),
                        ),
                        onPressed: controller.canConfirm
                            ? () => _confirm(context)
                            : null,
                        child: Text(l10n.commonApply),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _fontRow(
    BuildContext context, {
    required String id,
    required String label,
    bool removable = false,
  }) {
    final selected = controller.requestedFontId == id;
    final pending =
        selected &&
        (controller.isLoading ||
            controller.isResolving ||
            controller.isConfirming);
    final confirmed = selected && !pending && controller.selectedFont.id == id;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          checked: confirmed,
          inMutuallyExclusiveGroup: true,
          child: ListTile(
            key: Key('body-font-item-$id'),
            selected: selected,
            selectedTileColor: Colors.transparent,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            minTileHeight: 52,
            minLeadingWidth: 18,
            horizontalTitleGap: 12,
            leading: SizedBox.square(
              dimension: 18,
              child: pending
                  ? CircularProgressIndicator(
                      key: Key('body-font-loading-$id'),
                      strokeWidth: 2,
                      semanticsLabel: AppLocalizations.of(context)
                          .fontSelectorLoading,
                    )
                  : confirmed
                  ? Icon(Icons.check, key: Key('body-font-check-$id'), size: 18)
                  : null,
            ),
            title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: controller.canSelect
                ? () => controller.selectFont(id)
                : null,
            trailing: !removable
                ? null
                : IconButton(
                    key: Key('body-font-delete-$id'),
                    iconSize: 20,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    tooltip: AppLocalizations.of(context).commonDelete,
                    onPressed: controller.canMutate
                        ? () => controller.deleteFont(id)
                        : null,
                    icon: controller.deletingFontId == id
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: AppLocalizations.of(context)
                                  .fontSelectorLoading,
                            ),
                          )
                        : const Icon(Icons.delete_outline),
                  ),
          ),
        ),
      ),
    );
  }

  String _selectedFontLabel(AppLocalizations l10n) {
    for (final font in controller.fonts) {
      if (font.id == controller.selectedFont.id) return font.displayName;
    }
    return l10n.fontSelectorSystemDefault;
  }

  Future<void> _confirm(BuildContext context) async {
    final selection = await controller.confirmSelection();
    if (selection != null && context.mounted) {
      Navigator.of(context).pop(selection);
    }
  }

  String _failureMessage(AppLocalizations l10n, FontLibraryFailure failure) =>
      switch (failure) {
        FontLibraryFailure.unsupportedFormat =>
          l10n.fontSelectorUnsupportedFormat,
        FontLibraryFailure.invalidFont => l10n.fontSelectorInvalidFont,
        FontLibraryFailure.tooLarge => l10n.fontSelectorTooLarge,
        FontLibraryFailure.notFound => l10n.fontSelectorNotFound,
        FontLibraryFailure.storage => l10n.fontSelectorStorageFailure,
        FontLibraryFailure.corruptLibrary => l10n.fontSelectorCorruptLibrary,
        FontLibraryFailure.unsupportedLibraryVersion =>
          l10n.fontSelectorUnsupportedLibraryVersion,
        FontLibraryFailure.loadFailed => l10n.fontSelectorLoadFailed,
      };
}
