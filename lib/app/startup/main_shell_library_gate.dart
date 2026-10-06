import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared by tab pages and pushed shelves within the owning shell.
final mainShellLibraryReadinessProvider = Provider<Future<void>?>(
  (ref) => null,
  dependencies: const [],
);

class MainShellLibraryGate extends ConsumerWidget {
  const MainShellLibraryGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(mainShellLibraryReadinessProvider);
    if (ready == null) return child;
    return FutureBuilder<void>(
      future: ready,
      builder: (context, snapshot) =>
          snapshot.connectionState == ConnectionState.done
          ? child
          : const SizedBox.expand(key: Key('main-shell-library-loading')),
    );
  }
}
