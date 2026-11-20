import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/widgets/library_shelf_app_bar.dart';
import 'package:y300/l10n/app_localizations.dart';
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

class LibraryShelfLoadingStatus extends StatefulWidget {
  const LibraryShelfLoadingStatus({super.key});

  @override
  State<LibraryShelfLoadingStatus> createState() =>
      _LibraryShelfLoadingStatusState();
}

class _LibraryShelfLoadingStatusState extends State<LibraryShelfLoadingStatus> {
  late final Timer _delay;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // A quick local read should go straight from the reserved space to content.
    _delay = Timer(const Duration(milliseconds: 180), () {
      setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _delay.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: _visible
        ? Semantics(
            liveRegion: true,
            child: Text(
              AppLocalizations.of(context).libraryShelfLoading,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        : null,
  );
}
