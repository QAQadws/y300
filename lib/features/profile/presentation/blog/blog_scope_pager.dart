import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/presentation/profile_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/native_primary_tab_bar.dart';

/// Keeps tap and swipe selection in sync without owning feed reads.
class BlogScopePager extends StatefulWidget {
  const BlogScopePager({
    super.key,
    required this.selectedScope,
    required this.onSelected,
    required this.pageBuilder,
  });

  final UserBlogFeedScope selectedScope;
  final ValueChanged<UserBlogFeedScope> onSelected;
  final Widget Function(BuildContext context, UserBlogFeedScope scope)
  pageBuilder;

  @override
  State<BlogScopePager> createState() => _BlogScopePagerState();
}

class _BlogScopePagerState extends State<BlogScopePager>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: UserBlogFeedScope.values.length,
      initialIndex: widget.selectedScope.index,
      vsync: this,
    )..addListener(_selectScope);
  }

  void _selectScope() {
    final scope = UserBlogFeedScope.values[_tabs.index];
    if (scope != widget.selectedScope) widget.onSelected(scope);
  }

  @override
  void didUpdateWidget(covariant BlogScopePager oldWidget) {
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
  Widget build(BuildContext context) => Column(
    children: [
      NativePrimaryTabBar(
        key: const Key('profile-blog-view-tabs'),
        controller: _tabs,
        labels: [
          for (final scope in UserBlogFeedScope.values)
            ProfileTextResolver.blogView(AppLocalizations.of(context), scope),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            for (final scope in UserBlogFeedScope.values)
              _ScopePage(
                key: ValueKey(scope),
                child: widget.pageBuilder(context, scope),
              ),
          ],
        ),
      ),
    ],
  );
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
