import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/core/preferences/preferences_store.dart';

/// Resolves shell appearance before mounting any visible application content.
Future<Widget> bootstrapApplication({
  required PreferencesStore preferencesStore,
  required Widget child,
}) async {
  final container = ProviderContainer(
    overrides: [preferencesStoreProvider.overrideWithValue(preferencesStore)],
  );
  try {
    // Warming only SharedPreferences still leaves the async controller loading
    // during the first build. Reuse this resolved controller in the app scope.
    await container.read(appAppearanceControllerProvider.future);
  } catch (_) {
    // A storage failure keeps the root's existing default-appearance fallback.
  }
  return _BootstrappedProviderScope(container: container, child: child);
}

class _BootstrappedProviderScope extends StatefulWidget {
  _BootstrappedProviderScope({required this.container, required this.child})
    : super(key: ObjectKey(container));

  final ProviderContainer container;
  final Widget child;

  @override
  State<_BootstrappedProviderScope> createState() =>
      _BootstrappedProviderScopeState();
}

class _BootstrappedProviderScopeState
    extends State<_BootstrappedProviderScope> {
  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: widget.container,
    child: widget.child,
  );

  @override
  void dispose() {
    widget.container.dispose();
    super.dispose();
  }
}
