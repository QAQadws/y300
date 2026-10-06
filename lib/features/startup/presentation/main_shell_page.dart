import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/main_destination_page.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_navigation_settings_controller.dart';
import 'package:y300/app/navigation/main_shell_destination_presentation.dart';
import 'package:y300/app/startup/main_shell_startup_coordinator.dart';
import 'package:y300/app/startup/main_shell_startup_host.dart';
import 'package:y300/app/startup/main_shell_library_gate.dart';
import 'package:y300/app/startup/main_shell_startup_providers.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_bottom_bar.dart';
import 'package:y300/features/more/presentation/more_page.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 应用主壳：承载可配置业务入口和固定的“更多”入口。
class MainShellPage extends ConsumerStatefulWidget {
  const MainShellPage({super.key});

  @override
  ConsumerState<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends ConsumerState<MainShellPage> {
  MainShellDestination? _currentDestination;
  final Set<MainShellDestination> _builtDestinations = <MainShellDestination>{};
  late final MainShellStartupCoordinator _startup;
  late final Future<void> _coverMigrationReady;

  @override
  void initState() {
    super.initState();
    _startup = ref.read(mainShellStartupCoordinatorFactoryProvider).call();
    _coverMigrationReady = _startup.start();
  }

  @override
  void dispose() {
    _startup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        mainShellLibraryReadinessProvider.overrideWithValue(
          _coverMigrationReady,
        ),
      ],
      child: MainShellStartupHost(
        child: FutureBuilder<void>(
          future: _coverMigrationReady,
          builder: (context, snapshot) {
            final libraryReady =
                snapshot.connectionState == ConnectionState.done;
            return MainShellReadyTaskHost(
              isReady: libraryReady,
              child: _buildReadyShell(context),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReadyShell(BuildContext context) {
    final navigationState = ref
        .watch(mainNavigationSettingsControllerProvider)
        .value;
    if (navigationState == null) {
      return const Scaffold(
        body: SizedBox.expand(key: Key('main-shell-navigation-loading')),
      );
    }
    final settings = navigationState.settings;
    final visibleDestinations = settings.visibleDestinations;
    final visibleSet = visibleDestinations.toSet();
    _builtDestinations.removeWhere(
      (destination) => !visibleSet.contains(destination),
    );
    final currentDestination = _resolveCurrentDestination(settings);
    _currentDestination = currentDestination;
    _builtDestinations.add(currentDestination);

    return Scaffold(
      body: IndexedStack(
        index: MainShellDestination.values.indexOf(currentDestination),
        children: _buildIndexedPages(
          settings,
          currentDestination: currentDestination,
        ),
      ),
      bottomNavigationBar: ShelfSelectionBottomBar(
        fallback: NavigationBar(
          key: const ValueKey<String>('main-shell-navigation-bar'),
          selectedIndex: visibleDestinations.indexOf(currentDestination),
          onDestinationSelected: (index) {
            final destination = visibleDestinations[index];
            setState(() {
              _currentDestination = destination;
              _builtDestinations.add(destination);
            });
          },
          destinations: visibleDestinations
              .map(_buildNavigationDestination)
              .toList(growable: false),
        ),
      ),
    );
  }

  MainShellDestination _resolveCurrentDestination(
    MainNavigationSettings settings,
  ) {
    final current = _currentDestination;
    if (current != null && settings.visibleDestinations.contains(current)) {
      return current;
    }
    return settings.visibleManagedDestinations.first;
  }

  NavigationDestination _buildNavigationDestination(
    MainShellDestination destination,
  ) {
    return NavigationDestination(
      icon: _buildNavigationIcon(destination.icon),
      selectedIcon: _buildNavigationIcon(destination.selectedIcon),
      label: destination.localizedLabel(AppLocalizations.of(context)),
    );
  }

  Widget _buildNavigationIcon(IconData icon) {
    return SizedBox(width: 24, height: 24, child: Center(child: Icon(icon)));
  }

  List<Widget> _buildIndexedPages(
    MainNavigationSettings settings, {
    required MainShellDestination currentDestination,
  }) {
    return MainShellDestination.values
        .map((destination) {
          if (!settings.isVisible(destination) ||
              !_builtDestinations.contains(destination)) {
            return SizedBox.shrink(
              key: ValueKey<String>('main-shell-empty-${destination.name}'),
            );
          }
          final isActive = destination == currentDestination;
          return KeyedSubtree(
            key: ValueKey<String>('main-shell-page-${destination.name}'),
            child: TickerMode(
              enabled: isActive,
              child: _buildPage(destination, isActive: isActive),
            ),
          );
        })
        .toList(growable: false);
  }

  Widget _buildPage(
    MainShellDestination destination, {
    required bool isActive,
  }) {
    return switch (destination) {
      MainShellDestination.more => const MorePage(),
      _ => MainDestinationPage(destination: destination, isActive: isActive),
    };
  }
}
