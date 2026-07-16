class HistoryRetentionPolicy {
  const HistoryRetentionPolicy({this.maxEntries = 2000})
    : assert(maxEntries > 0);

  final int maxEntries;
}
