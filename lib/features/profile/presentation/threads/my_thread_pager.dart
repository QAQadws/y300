import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/native_primary_tab_bar.dart';

class MyThreadPager extends StatefulWidget {
  const MyThreadPager({
    super.key,
    required this.selectedType,
    required this.onSelected,
    required this.pageBuilder,
  });

  final UserThreadDirectoryType selectedType;
  final ValueChanged<UserThreadDirectoryType> onSelected;
  final Widget Function(BuildContext, UserThreadDirectoryType) pageBuilder;

  @override
  State<MyThreadPager> createState() => _MyThreadPagerState();
}

class _MyThreadPagerState extends State<MyThreadPager>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: UserThreadDirectoryType.values.length,
      initialIndex: widget.selectedType.index,
      vsync: this,
    )..addListener(_select);
  }

  void _select() {
    final type = UserThreadDirectoryType.values[_tabs.index];
    if (type != widget.selectedType) widget.onSelected(type);
  }

  @override
  void didUpdateWidget(covariant MyThreadPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tabs.index != widget.selectedType.index) {
      _tabs.animateTo(widget.selectedType.index);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        NativePrimaryTabBar(
          key: const Key('my-thread-tabs'),
          controller: _tabs,
          labels: [l10n.profileMyThreadsTab, l10n.profileMyRepliesTab],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              for (final type in UserThreadDirectoryType.values)
                _ThreadTabPage(
                  key: ValueKey(type),
                  child: widget.pageBuilder(context, type),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThreadTabPage extends StatefulWidget {
  const _ThreadTabPage({super.key, required this.child});

  final Widget child;

  @override
  State<_ThreadTabPage> createState() => _ThreadTabPageState();
}

class _ThreadTabPageState extends State<_ThreadTabPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
