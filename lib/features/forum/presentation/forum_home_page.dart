import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/presentation/forum_display_page.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/widgets/forum_home_widgets.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/domain/services/forum_thread_url_parser.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

class ForumHomePage extends ConsumerWidget {
  const ForumHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authSessionControllerProvider, (previous, next) {
      final wasLoggedIn = previous?.asData?.value.isLoggedIn ?? false;
      final isLoggedIn = next.asData?.value.isLoggedIn ?? false;
      if (!wasLoggedIn && isLoggedIn) {
        ref
            .read(forumHomeControllerProvider.notifier)
            .refresh(forceNetwork: true);
      }
    });

    final state = ref.watch(forumHomeControllerProvider);
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('论坛首页'),
        actions: [
          IconButton(
            key: const Key('forum-home-search-button'),
            tooltip: '搜索论坛',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ForumSearchPage(),
                ),
              );
            },
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: state.when(
        loading: () => const SizedBox.shrink(),
        error: (error, _) => _ForumHomeErrorView(
          message: error.toString(),
          onRetry: () => ref
              .read(forumHomeControllerProvider.notifier)
              .refresh(forceNetwork: true),
        ),
        data: (data) => _ForumHomeContent(
          data: data,
          imageHeaderBuilder: imageHeaderBuilder,
        ),
      ),
    );
  }
}

class _ForumHomeContent extends ConsumerStatefulWidget {
  const _ForumHomeContent({
    required this.data,
    required this.imageHeaderBuilder,
  });

  final ForumHomeViewData data;
  final ImageRequestHeaderBuilder imageHeaderBuilder;

  @override
  ConsumerState<_ForumHomeContent> createState() => _ForumHomeContentState();
}

class _ForumHomeContentState extends ConsumerState<_ForumHomeContent> {
  final Set<String> _collapsedSectionKeys = <String>{};

  @override
  void didUpdateWidget(covariant _ForumHomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeKeys = {
      for (final section in widget.data.sections) _sectionKey(section),
    };
    _collapsedSectionKeys.removeWhere((key) => !activeKeys.contains(key));
  }

  @override
  Widget build(BuildContext context) {
    final palette = ForumHomeNativePalette.resolve(Theme.of(context));
    return RefreshIndicator(
      onRefresh: () => ref
          .read(forumHomeControllerProvider.notifier)
          .refresh(forceNetwork: true),
      child: ColoredBox(
        color: palette.background,
        child: ListView(
          key: const Key('forum-home-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 10),
          children: [
            ForumHomeCarousel(
              items: widget.data.carouselItems,
              headerBuilder: widget.imageHeaderBuilder,
              onOpen: (item) => _openCarouselTarget(context, ref, item),
            ),
            for (final section in widget.data.sections)
              ForumHomeSectionCard(
                title: section.title,
                isCollapsed: _collapsedSectionKeys.contains(
                  _sectionKey(section),
                ),
                onToggle: () => _toggleSection(section),
                children: _buildRows(context, section),
              ),
          ],
        ),
      ),
    );
  }

  void _toggleSection(ForumSection section) {
    final key = _sectionKey(section);
    setState(() {
      if (!_collapsedSectionKeys.add(key)) {
        _collapsedSectionKeys.remove(key);
      }
    });
  }

  String _sectionKey(ForumSection section) {
    return '${section.type.name}:${section.title}';
  }

  List<Widget> _buildRows(BuildContext context, ForumSection section) {
    final rows = <_ForumHomeRowData>[
      for (final forum in section.favoriteItems)
        _ForumHomeRowData(
          key: Key('forum-favorite-card-${forum.fid}'),
          title: forum.title,
          description: forum.description,
          todayPosts: forum.todayPosts,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ForumDisplayPage(fid: forum.fid, title: forum.title),
              ),
            );
          },
        ),
      for (final forum in section.items)
        _ForumHomeRowData(
          key: Key('forum-card-${forum.fid}'),
          title: forum.name,
          description: forum.description,
          todayPosts: forum.todayPosts,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ForumDisplayPage(fid: forum.fid, title: forum.name),
              ),
            );
          },
        ),
    ];

    return [
      for (var index = 0; index < rows.length; index++)
        ForumHomeForumRow(
          key: rows[index].key,
          title: rows[index].title,
          description: rows[index].description,
          todayPosts: rows[index].todayPosts,
          isLast: index == rows.length - 1,
          onTap: rows[index].onTap,
        ),
    ];
  }

  Future<void> _openCarouselTarget(
    BuildContext context,
    WidgetRef ref,
    ForumHomeCarouselItem item,
  ) async {
    final parser = const ForumThreadUrlParser();
    final normalized = parser.normalizeHref(item.targetUrl);
    final tid = normalized == null ? null : parser.extractTid(normalized);
    if (tid != null && tid.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ThreadDetailPage(tid: tid)),
      );
      return;
    }

    final uri = ref.read(forumWebViewNavigatorProvider).resolve(item.targetUrl);
    await ref.read(forumWebViewExternalLauncherProvider).launch(uri);
  }
}

class _ForumHomeRowData {
  const _ForumHomeRowData({
    required this.key,
    required this.title,
    required this.description,
    required this.todayPosts,
    required this.onTap,
  });

  final Key key;
  final String title;
  final String description;
  final int todayPosts;
  final VoidCallback onTap;
}

class _ForumHomeErrorView extends StatelessWidget {
  const _ForumHomeErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('forum-home-retry-button'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
