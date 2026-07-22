import 'package:flutter/foundation.dart';

enum MainShellDestination {
  forum,
  favorites,
  comic,
  novel,
  history,
  more;

  static const List<MainShellDestination> defaultManagedOrder =
      <MainShellDestination>[forum, favorites, comic, novel, history];

  bool get isManaged => this != MainShellDestination.more;
}

@immutable
final class MainNavigationSettings {
  factory MainNavigationSettings({
    required Iterable<MainShellDestination> managedOrder,
    required Iterable<MainShellDestination> hiddenDestinations,
  }) {
    final normalizedOrder = _normalizeOrder(managedOrder);
    final normalizedHidden = hiddenDestinations
        .where((destination) => destination.isManaged)
        .toSet();
    if (normalizedHidden.length == normalizedOrder.length) {
      normalizedHidden.remove(normalizedOrder.first);
    }
    return MainNavigationSettings._(
      List<MainShellDestination>.unmodifiable(normalizedOrder),
      Set<MainShellDestination>.unmodifiable(normalizedHidden),
    );
  }

  factory MainNavigationSettings.defaults() {
    return MainNavigationSettings(
      managedOrder: MainShellDestination.defaultManagedOrder,
      hiddenDestinations: const <MainShellDestination>{},
    );
  }

  const MainNavigationSettings._(this.managedOrder, this.hiddenDestinations);

  final List<MainShellDestination> managedOrder;
  final Set<MainShellDestination> hiddenDestinations;

  List<MainShellDestination> get visibleManagedDestinations =>
      List<MainShellDestination>.unmodifiable(
        managedOrder.where(
          (destination) => !hiddenDestinations.contains(destination),
        ),
      );

  List<MainShellDestination> get visibleDestinations =>
      List<MainShellDestination>.unmodifiable(<MainShellDestination>[
        ...visibleManagedDestinations,
        MainShellDestination.more,
      ]);

  bool isVisible(MainShellDestination destination) {
    return destination == MainShellDestination.more ||
        !hiddenDestinations.contains(destination);
  }

  MainNavigationSettings copyWith({
    Iterable<MainShellDestination>? managedOrder,
    Iterable<MainShellDestination>? hiddenDestinations,
  }) {
    return MainNavigationSettings(
      managedOrder: managedOrder ?? this.managedOrder,
      hiddenDestinations: hiddenDestinations ?? this.hiddenDestinations,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MainNavigationSettings &&
            listEquals(other.managedOrder, managedOrder) &&
            setEquals(other.hiddenDestinations, hiddenDestinations);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(managedOrder),
    Object.hashAllUnordered(hiddenDestinations),
  );

  static List<MainShellDestination> _normalizeOrder(
    Iterable<MainShellDestination> candidates,
  ) {
    final seen = <MainShellDestination>{};
    final normalized = <MainShellDestination>[];
    for (final destination in candidates) {
      if (destination.isManaged && seen.add(destination)) {
        normalized.add(destination);
      }
    }
    for (final destination in MainShellDestination.defaultManagedOrder) {
      if (seen.add(destination)) {
        normalized.add(destination);
      }
    }
    return normalized;
  }
}

final class MainNavigationMinimumVisibleException implements Exception {
  const MainNavigationMinimumVisibleException();

  @override
  String toString() =>
      'At least one managed navigation destination is required';
}

final class MainNavigationMutationInProgressException implements Exception {
  const MainNavigationMutationInProgressException();

  @override
  String toString() => 'A navigation settings mutation is already in progress';
}
