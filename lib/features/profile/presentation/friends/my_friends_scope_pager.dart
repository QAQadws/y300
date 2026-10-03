import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/native_primary_tab_bar.dart';

/// Synchronizes tap and swipe selection while the controller owns each feed.
class MyFriendsScopePager extends StatefulWidget {
  const MyFriendsScopePager({
    super.key,
    required this.selectedScope,
    required this.onSelected,
    required this.pageBuilder,
  });

  final ForumFriendFeedScope selectedScope;
  final ValueChanged<ForumFriendFeedScope> onSelected;
  final Widget Function(BuildContext, ForumFriendFeedScope) pageBuilder;

  @override
  State<MyFriendsScopePager> createState() => _MyFriendsScopePagerState();
}

class _MyFriendsScopePagerState extends State<MyFriendsScopePager>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: ForumFriendFeedScope.values.length,
      initialIndex: widget.selectedScope.index,
      vsync: this,
    )..addListener(_selectScope);
  }

  void _selectScope() {
    final scope = ForumFriendFeedScope.values[_tabs.index];
    if (scope != widget.selectedScope) widget.onSelected(scope);
  }

  @override
  void didUpdateWidget(covariant MyFriendsScopePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tabs.index != widget.selectedScope.index) {
      _tabs.animateTo(widget.selectedScope.index);
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
          key: const Key('my-friends-tabs'),
          controller: _tabs,
          labels: [
            l10n.profileFriendsTab,
            l10n.profileFriendsOnlineTab,
            l10n.profileFriendsVisitorsTab,
            l10n.profileFriendsFootprintsTab,
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              for (final scope in ForumFriendFeedScope.values)
                _ScopePage(
                  key: ValueKey('my-friends-scope-${scope.name}'),
                  child: widget.pageBuilder(context, scope),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScopePage extends StatefulWidget {
  const _ScopePage({super.key, required this.child});

  final Widget child;

  @override
  State<_ScopePage> createState() => _ScopePageState();
}

class _ScopePageState extends State<_ScopePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
