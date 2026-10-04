/// Shared cadence for scheduled forum reads and durable comic search work.
abstract final class ForumSearchTimingPolicy {
  static const Duration defaultCooldown = Duration(milliseconds: 10500);
}
