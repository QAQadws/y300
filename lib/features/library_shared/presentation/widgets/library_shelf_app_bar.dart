import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/services/library_shelf_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/app_popup_menu.dart';

AppBar buildLibraryShelfAppBar(
  BuildContext context, {
  required LibraryModuleKey moduleKey,
  VoidCallback? onSearch,
  VoidCallback? onFilter,
  Widget? menu,
}) {
  final l10n = AppLocalizations.of(context);
  return AppBar(
    title: Text(LibraryShelfTextResolver.moduleTitle(l10n, moduleKey)),
    actions: [
      IconButton(
        key: const Key('unified-shelf-search-button'),
        icon: const Icon(Icons.search),
        tooltip: l10n.libraryShelfSearch,
        onPressed: onSearch,
      ),
      IconButton(
        key: const Key('unified-shelf-filter-button'),
        icon: const Icon(Icons.filter_list),
        tooltip: l10n.libraryShelfFilterAndSort,
        onPressed: onFilter,
      ),
      menu ??
          AppPopupMenuButton<String>(
            key: const Key('unified-shelf-more-button'),
            enabled: false,
            itemBuilder: (_) => const [],
          ),
    ],
  );
}
