/// A selected destination is identified by a forum UID when it came from the
/// friend directory, and always retains the exact username used for sending.
final class PrivateMessageRecipientChoice {
  const PrivateMessageRecipientChoice({required this.username, this.userId});

  final String username;
  final String? userId;
}

enum AddPrivateMessageRecipientResult { added, duplicate, invalid, full }

/// An ephemeral selection owned by one compose route. Search and filter changes
/// do not mutate it, and no private recipient data is persisted.
final class PrivateMessageRecipientSelection {
  static const maxRecipients = 20;

  final List<PrivateMessageRecipientChoice> _items = [];

  List<PrivateMessageRecipientChoice> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get length => _items.length;

  AddPrivateMessageRecipientResult addUsername(String rawUsername) {
    if (!_validRawUsername(rawUsername)) {
      return AddPrivateMessageRecipientResult.invalid;
    }
    return _add(PrivateMessageRecipientChoice(username: rawUsername.trim()));
  }

  AddPrivateMessageRecipientResult addFriend({
    required String userId,
    required String username,
  }) {
    if (!_validRawUsername(username)) {
      return AddPrivateMessageRecipientResult.invalid;
    }
    return _add(
      PrivateMessageRecipientChoice(
        userId: userId.trim(),
        username: username.trim(),
      ),
    );
  }

  AddPrivateMessageRecipientResult _add(PrivateMessageRecipientChoice item) {
    if (!_validUsername(item.username) ||
        (item.userId != null && !_positiveId.hasMatch(item.userId!))) {
      return AddPrivateMessageRecipientResult.invalid;
    }
    if (_items.any((selected) => _sameRecipient(selected, item))) {
      return AddPrivateMessageRecipientResult.duplicate;
    }
    if (_items.length == maxRecipients) {
      return AddPrivateMessageRecipientResult.full;
    }
    _items.add(item);
    return AddPrivateMessageRecipientResult.added;
  }

  bool containsFriend(String userId, String username) {
    final candidate = PrivateMessageRecipientChoice(
      userId: userId.trim(),
      username: username.trim(),
    );
    return _items.any((selected) => _sameRecipient(selected, candidate));
  }

  bool remove(PrivateMessageRecipientChoice choice) {
    final index = _items.indexWhere((item) => _sameRecipient(item, choice));
    if (index < 0) return false;
    _items.removeAt(index);
    return true;
  }

  void clear() => _items.clear();

  /// Freeze the user-approved destination list for one command. Later UI edits
  /// cannot change the batch already being sent.
  List<String> usernameSnapshot() =>
      List.unmodifiable(_items.map((item) => item.username));
}

final _positiveId = RegExp(r'^[1-9]\d*$');
final _invalidUsernameCharacter = RegExp(r'[,\x00-\x1f\x7f-\x9f]');

bool _validUsername(String username) =>
    username.isNotEmpty &&
    username.length <= 256 &&
    !_invalidUsernameCharacter.hasMatch(username);

bool _validRawUsername(String username) =>
    !_invalidUsernameCharacter.hasMatch(username) &&
    _validUsername(username.trim());

bool _sameRecipient(
  PrivateMessageRecipientChoice first,
  PrivateMessageRecipientChoice second,
) =>
    first.username == second.username ||
    (first.userId != null &&
        second.userId != null &&
        first.userId == second.userId);
