/// Muting future notifications without deleting messages or changing PM rules.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';

/// Which authors are covered by one notification-type filter.
enum ForumNotificationIgnoreScope {
  /// Future notifications of this type from the selected author.
  author,

  /// Future notifications of this type from any author.
  allAuthors,
}

/// A user-selected notification filter derived from a notification row.
final class ForumNotificationIgnoreSubmission {
  /// Creates an explicit notification filter request.
  const ForumNotificationIgnoreSubmission({
    required this.notificationId,
    required this.type,
    required this.authorId,
    required this.scope,
    this.cancellation,
  });

  /// Notification that supplied the type and author; not a deletion target.
  final String notificationId;

  /// Source notification type, retained without translation.
  final String type;

  /// Original author; zero is permitted only for
  /// [ForumNotificationIgnoreScope.allAuthors].
  final String authorId;

  /// Explicitly selected author scope.
  final ForumNotificationIgnoreScope scope;

  /// Cancels local waiting; cannot roll back an already accepted filter.
  final ForumRequestCancellation? cancellation;
}

/// Proven type/author filter returned by the server's success callback.
final class ForumNotificationIgnoreReceipt {
  /// Records the confirmed filter, without claiming old reminders were removed.
  const ForumNotificationIgnoreReceipt({
    required this.notificationId,
    required this.type,
    required this.authorId,
  });

  /// Notification that initiated the action.
  final String notificationId;

  /// Filtered notification type.
  final String type;

  /// Filtered author, or zero for every author.
  final String authorId;
}

/// Installs a notification filter using the shared authenticated transport.
abstract interface class ForumNotificationIgnoreCommand {
  /// Returns applied only after proving the matching type/author mutation.
  Future<DataCommandResult<ForumNotificationIgnoreReceipt>> execute(
    ForumNotificationIgnoreSubmission submission,
  );
}
