import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/history_entry_router.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/message_routes.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/comic/presentation/comic_tab_page.dart';
import 'package:y300/features/favorites/presentation/favorite_shelf_page.dart';
import 'package:y300/features/forum/presentation/forum_shell_page.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/history/presentation/history_page.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_bottom_bar.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_providers.dart';
import 'package:y300/features/novel/presentation/novel_tab_page.dart';

typedef MainDestinationRouteFactory =
    Route<void> Function(MainShellDestination destination);

/// Opening a destination does not change navigation visibility or tab state.
final mainDestinationRouteFactoryProvider = Provider<MainDestinationRouteFactory>(
  (ref) => (destination) {
    if (!destination.isManaged) {
      throw ArgumentError.value(destination, 'destination');
    }
    return MaterialPageRoute<void>(
      builder: (_) => ProviderScope(
        overrides: [
          // A pushed shelf must not take over the selection owner of the shell
          // underneath it. Both the shelf and its action bar use this scope.
          shelfSelectionHostControllerProvider.overrideWith((ref) {
            final controller = ShelfSelectionHostController();
            ref.onDispose(controller.dispose);
            return controller;
          }),
          forumWebViewPopOnRootBackProvider.overrideWithValue(true),
        ],
        child: switch (destination) {
          MainShellDestination.favorites ||
          MainShellDestination.comic ||
          MainShellDestination.novel => Scaffold(
            body: MainDestinationPage(destination: destination),
            bottomNavigationBar: const ShelfSelectionBottomBar(),
          ),
          _ => MainDestinationPage(destination: destination),
        },
      ),
    );
  },
);

/// The same feature pages serve both the lazy main shell and standalone routes.
class MainDestinationPage extends ConsumerWidget {
  const MainDestinationPage({
    super.key,
    required this.destination,
    this.isActive = true,
  });

  final MainShellDestination destination;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (destination) {
      MainShellDestination.forum => ForumShellPage(isActive: isActive),
      MainShellDestination.favorites => FavoriteShelfPage(isActive: isActive),
      MainShellDestination.comic => ComicTabPage(isActive: isActive),
      MainShellDestination.novel => NovelTabPage(isActive: isActive),
      MainShellDestination.history => HistoryPage(
        onOpenEntry: ref.read(historyEntryRouterProvider).open,
        imageReferer: ref.watch(forumImageRefererProvider),
      ),
      MainShellDestination.messages => MessageCenterDestination(
        isActive: isActive,
      ),
      MainShellDestination.more => throw ArgumentError.value(
        destination,
        'destination',
      ),
    };
  }
}
