import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';

class LibraryTaskNotificationText {
  const LibraryTaskNotificationText({required this.title, required this.body});

  final String title;
  final String body;
}

typedef LibraryTaskNotificationTextResolver =
    LibraryTaskNotificationText Function(LibraryShelfTaskProgress progress);

/// Connects [LibraryTaskProgressHub] progress to the system notification
/// service, so long-running favorite-sync and comic-search-queue tasks surface
/// in the OS notification shade.
///
/// The bridge is a thin presentation adapter: it only listens to hub progress
/// and forwards to [LibraryTaskNotificationService]. It does not know how tasks
/// run and never touches repositories. Implementations start listening on
/// construction (or [start]) and stop on [dispose].
abstract class LibraryTaskNotificationBridge {
  /// Begins listening to the progress hub. Safe to call more than once.
  ///
  /// Passing a different [localeId] updates the locale snapshot used for new
  /// notifications and republishes any currently active task.
  void start({
    required String localeId,
    required LibraryTaskNotificationTextResolver textResolver,
  });

  /// Stops listening and clears any notifications still showing.
  void dispose();
}
