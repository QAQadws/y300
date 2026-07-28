import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_image.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

class ComposerStickerGroupPanel extends StatefulWidget {
  const ComposerStickerGroupPanel({
    super.key,
    required this.keyPrefix,
    required this.groups,
    required this.initialGroupId,
    required this.onGroupChanged,
    required this.onSelected,
  });

  final String keyPrefix;
  final List<StickerGroup> groups;
  final String? initialGroupId;
  final ValueChanged<String> onGroupChanged;
  final ValueChanged<StickerItem> onSelected;

  @override
  State<ComposerStickerGroupPanel> createState() =>
      _ComposerStickerGroupPanelState();
}

class _ComposerStickerGroupPanelState extends State<ComposerStickerGroupPanel> {
  TabController? _tabController;
  int? _lastReportedIndex;

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).composerStickerNetworkRequired,
        ),
      );
    }
    return DefaultTabController(
      key: Key('${widget.keyPrefix}-sticker-sheet'),
      length: widget.groups.length,
      initialIndex: _initialIndex(),
      child: Builder(
        builder: (context) {
          _bindTabController(DefaultTabController.of(context));
          return Column(
            children: [
              TabBar(
                key: Key('${widget.keyPrefix}-sticker-tabs'),
                isScrollable: true,
                onTap: _reportGroupAt,
                tabs: [
                  for (final group in widget.groups)
                    Tab(
                      key: Key(
                        '${widget.keyPrefix}-sticker-group-tab-${group.id}',
                      ),
                      text: ComposerTextResolver.stickerGroupTitle(
                        AppLocalizations.of(context),
                        group,
                      ),
                    ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  key: Key('${widget.keyPrefix}-sticker-pages'),
                  children: [
                    for (final group in widget.groups)
                      _ComposerStickerGrid(
                        keyPrefix: widget.keyPrefix,
                        stickers: group.stickers,
                        onSelected: widget.onSelected,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  int _initialIndex() {
    final groupId = widget.initialGroupId?.trim();
    if (groupId == null || groupId.isEmpty) {
      return 0;
    }
    final index = widget.groups.indexWhere((group) => group.id == groupId);
    return index < 0 ? 0 : index;
  }

  void _bindTabController(TabController controller) {
    if (identical(_tabController, controller)) {
      return;
    }
    _tabController?.removeListener(_handleTabChanged);
    _tabController = controller;
    _lastReportedIndex = controller.index;
    controller.addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    final controller = _tabController;
    if (controller == null || controller.indexIsChanging) {
      return;
    }
    _reportGroupAt(controller.index);
  }

  void _reportGroupAt(int index) {
    if (index < 0 ||
        index >= widget.groups.length ||
        _lastReportedIndex == index) {
      return;
    }
    _lastReportedIndex = index;
    widget.onGroupChanged(widget.groups[index].id);
  }
}

class _ComposerStickerGrid extends StatelessWidget {
  const _ComposerStickerGrid({
    required this.keyPrefix,
    required this.stickers,
    required this.onSelected,
  });

  final String keyPrefix;
  final List<StickerItem> stickers;
  final ValueChanged<StickerItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 64,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return IconButton(
          key: Key('$keyPrefix-sticker-item-${sticker.code}'),
          constraints: const BoxConstraints.tightFor(width: 56, height: 56),
          padding: EdgeInsets.zero,
          onPressed: () => onSelected(sticker),
          icon: ComposerStickerImage(
            sticker: sticker,
            width: 48,
            height: 48,
            fit: BoxFit.contain,
            placeholder: const SizedBox.shrink(),
            errorPlaceholder: const Icon(Icons.broken_image_outlined),
          ),
        );
      },
    );
  }
}
