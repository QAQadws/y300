import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/widgets/library_shelf_loading.dart';

/// Shared by tab pages and pushed shelves within the owning shell.
final mainShellLibraryReadinessProvider = Provider<ValueListenable<bool>?>(
  (ref) => null,
  dependencies: const [],
);

class MainShellLibraryGate extends ConsumerWidget {
  const MainShellLibraryGate({
    required this.moduleKey,
    required this.child,
    super.key,
  });

  final LibraryModuleKey moduleKey;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(mainShellLibraryReadinessProvider);
    if (ready == null) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: ready,
      child: child,
      builder: (context, isReady, shelf) => isReady
          ? shelf!
          : LibraryShelfLoadingPage(
              key: const Key('main-shell-library-loading'),
              moduleKey: moduleKey,
            ),
    );
  }
}
