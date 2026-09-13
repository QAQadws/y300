/// One minimum reading-access threshold, shared by any number of user groups.
final class ThreadReadAccessOption {
  /// Creates a threshold with its original server group labels.
  const ThreadReadAccessOption({
    required this.value,
    this.groupNames = const [],
  });

  /// Minimum read access (0–255), never a user-group ID.
  final int value;

  /// Distinct server group labels that share this threshold.
  final List<String> groupNames;
}

/// What the current server form proves about thread-level reading access.
/// A null current value is unknown, never an alias for unrestricted access.
final class ThreadReadAccess {
  /// Creates the capabilities and confirmed value of one form.
  const ThreadReadAccess({
    required this.canModify,
    this.currentValue,
    this.options = const [],
  });

  /// No topic-level control was exposed by the form.
  static const unavailable = ThreadReadAccess(canModify: false);

  /// Whether the form offers an enabled topic permission selector.
  final bool canModify;

  /// Confirmed server value; null means unknown, and zero is unrestricted.
  final int? currentValue;

  /// Enabled choices, merged by numeric threshold.
  final List<ThreadReadAccessOption> options;

  /// Whether current-value evidence is available.
  bool get isCurrentValueConfirmed => currentValue != null;

  /// Whether the server currently offers this value for selection.
  bool allows(int value) =>
      canModify && options.any((option) => option.value == value);

  /// Attaches a value confirmed by an identity-checked thread read.
  ThreadReadAccess withCurrentValue(int value) => ThreadReadAccess(
    canModify: canModify,
    currentValue: value,
    options: options,
  );
}

/// Limits explicitly exposed by a poll form. Null means not provided.
final class ThreadPollConstraints {
  /// Creates limits only from explicit form evidence.
  const ThreadPollConstraints({this.maximumOptions, this.maximumOptionLength});

  /// Maximum poll options, or null when the form does not declare it.
  final int? maximumOptions;

  /// Maximum option length, or null when it is not declared.
  final int? maximumOptionLength;
}
