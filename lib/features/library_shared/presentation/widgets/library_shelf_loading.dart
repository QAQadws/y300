import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/widgets/library_shelf_app_bar.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/delayed_loading_status.dart';
import 'package:y300/shared/widgets/shelf/fixed_slot_pager_header.dart';
import 'package:y300/shared/widgets/shelf/shelf_theme_palette.dart';

class LibraryShelfLoadingPage extends StatelessWidget {
  const LibraryShelfLoadingPage({super.key, required this.moduleKey});

  final LibraryModuleKey moduleKey;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: buildLibraryShelfAppBar(context, moduleKey: moduleKey),
    body: const Column(
      children: [
        LibraryShelfCategoryPlaceholder(),
        Expanded(child: LibraryShelfLoadingStatus()),
      ],
    ),
  );
}

class LibraryShelfCategoryPlaceholder extends StatelessWidget {
  const LibraryShelfCategoryPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = const ShelfThemePaletteResolver().resolve(
      Theme.of(context),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: const Key('unified-shelf-category-placeholder'),
          height: FixedSlotPagerHeader.height,
          width: double.infinity,
          child: ColoredBox(color: palette.categoryBarBackground),
        ),
        Divider(height: 1, color: palette.categoryDivider),
      ],
    );
  }
}

class LibraryShelfLoadingStatus extends StatelessWidget {
  const LibraryShelfLoadingStatus({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: DelayedLoadingStatus(
      label: AppLocalizations.of(context).libraryShelfLoading,
    ),
  );
}
