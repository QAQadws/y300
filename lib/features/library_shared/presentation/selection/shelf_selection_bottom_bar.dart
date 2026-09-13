import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/presentation/selection/selection_action_bar.dart';
import 'package:y300/features/library_shared/presentation/selection/selection_action_text_resolver.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_providers.dart';
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/features/library_shared/presentation/services/library_shelf_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Shares selection actions between tabbed and independently opened shelves.
class ShelfSelectionBottomBar extends ConsumerStatefulWidget {
  const ShelfSelectionBottomBar({super.key, this.fallback});

  final Widget? fallback;

  @override
  ConsumerState<ShelfSelectionBottomBar> createState() =>
      _ShelfSelectionBottomBarState();
}

class _ShelfSelectionBottomBarState
    extends ConsumerState<ShelfSelectionBottomBar> {
  static const String _createCategorySelectionSentinel =
      '__create-selection-category__';

  @override
  Widget build(BuildContext context) {
    final selectionHost = ref.watch(shelfSelectionHostControllerProvider);
    return ListenableBuilder(
      listenable: selectionHost,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => SlideTransition(
          position: animation.drive(
            Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: selectionHost.isActive
            ? SelectionActionBar(
                key: const ValueKey<String>('main-shell-selection-bar'),
                actions:
                    selectionHost.state?.selectionActions ??
                    const <SelectionAction>[],
                l10n: AppLocalizations.of(context),
                onActionTap: _handleSelectionActionTap,
              )
            : widget.fallback ?? const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _handleSelectionActionTap(SelectionAction action) async {
    final l10n = AppLocalizations.of(context);
    final selectionHost = ref.read(shelfSelectionHostControllerProvider);
    if (!selectionHost.isActive) {
      return;
    }
    String? targetCategoryId;

    try {
      if (action.id == SelectionActionIds.assignCategory) {
        targetCategoryId = await _pickTargetCategory(selectionHost);
        if (targetCategoryId == null || targetCategoryId.trim().isEmpty) {
          return;
        }
      }

      if (action.needsConfirm) {
        final confirmed = await _confirmSelectionAction(
          action,
          selectionHost.state,
        );
        if (confirmed != true || !mounted) {
          return;
        }
      }

      final result = await selectionHost.executeAction(
        actionId: action.id,
        targetCategoryId: targetCategoryId,
      );
      if (!mounted) {
        return;
      }
      _showSelectionMessage(
        SelectionActionTextResolver.resultMessage(l10n, action.id, result),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSelectionMessage(
        l10n.librarySelectionActionFailed(
          LibraryErrorSummary.resolve(l10n, error),
        ),
      );
    }
  }

  Future<bool?> _confirmSelectionAction(
    SelectionAction action,
    ShelfSelectionHostState? state,
  ) {
    final l10n = AppLocalizations.of(context);
    final selectedCount = state?.selectedCount ?? 0;
    final title = action.id == SelectionActionIds.unfavorite
        ? l10n.librarySelectionConfirmUnfavoriteTitle
        : l10n.librarySelectionConfirmActionTitle;
    final content = action.id == SelectionActionIds.unfavorite
        ? l10n.librarySelectionConfirmUnfavoriteBody(selectedCount)
        : l10n.librarySelectionConfirmActionBody(
            selectedCount,
            SelectionActionTextResolver.label(l10n, action.id),
          );
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonConfirm),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _pickTargetCategory(
    ShelfSelectionHostController selectionHost,
  ) async {
    final state = selectionHost.state;
    if (state == null) {
      return null;
    }
    final categories = await selectionHost.loadAvailableCategories();
    if (!mounted) {
      return null;
    }
    final available = categories
        .where((category) => category.categoryId != state.activeCategoryId)
        .toList(growable: false);
    final l10n = AppLocalizations.of(context);
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(l10n.librarySelectionSelectCategory),
                enabled: false,
              ),
              for (final category in available)
                ListTile(
                  title: Text(
                    LibraryShelfTextResolver.categoryName(l10n, category),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop(category.categoryId);
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(l10n.librarySelectionCreateCategory),
                onTap: () {
                  Navigator.of(
                    sheetContext,
                  ).pop(_createCategorySelectionSentinel);
                },
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || selected == null) {
      return null;
    }
    if (selected != _createCategorySelectionSentinel) {
      return selected;
    }
    final categoryName = await _showCreateCategoryDialog();
    if (!mounted || categoryName == null || categoryName.trim().isEmpty) {
      return null;
    }
    return selectionHost.createCategory(categoryName.trim());
  }

  Future<String?> _showCreateCategoryDialog() {
    return showDialog<String>(
      context: context,
      builder: (_) => const _CreateSelectionCategoryDialog(),
    );
  }

  void _showSelectionMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(trimmed)));
  }
}

class _CreateSelectionCategoryDialog extends StatefulWidget {
  const _CreateSelectionCategoryDialog();

  @override
  State<_CreateSelectionCategoryDialog> createState() =>
      _CreateSelectionCategoryDialogState();
}

class _CreateSelectionCategoryDialogState
    extends State<_CreateSelectionCategoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('selection-create-category-dialog'),
      title: Text(l10n.librarySelectionCreateCategory),
      content: TextField(
        key: const Key('selection-create-category-name-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.librarySelectionCategoryNameHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
