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
  void start();

  /// Stops listening and clears any notifications still showing.
  void dispose();
}
