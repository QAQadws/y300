import '../contracts/forum_message_attention.dart';
import '../parsing/discuz_message_attention_identity.dart';
import '../parsing/discuz_message_attention_source.dart';

/// Extracts navigation-attention evidence from decoded Discuz API envelopes.
///
/// This parser performs no requests or session changes. A caller remains
/// responsible for selecting fresh, successful GET responses and retaining
/// the request's owner and ordering information.
final class DiscuzMessageAttentionApiParser {
  /// Creates a parser for one forum origin.
  const DiscuzMessageAttentionApiParser({required this.siteOrigin});

  /// Origin used to reject responses from a different forum or transport.
  final Uri siteOrigin;

  /// Parses an already decoded API envelope for the expected browsing account.
  ///
  /// Returns null when identity, endpoint, or envelope structure cannot be
  /// trusted, or no supported attention field is valid. Invalid or omitted
  /// fields remain unknown; they never imply an absent navigation hint.
  ForumMessageAttentionObservation? parse(
    Object? source, {
    required Uri sourceUri,
    required String expectedUserId,
  }) {
    if (!acceptsDiscuzMessageAttentionApiSource(
      sourceUri,
      siteOrigin: siteOrigin,
    )) {
      return null;
    }
    final expected = discuzMessageAttentionIdentity(expectedUserId);
    final root = _stringKeyedMap(source);
    if (expected == null || root == null) return null;
    final message = root['Message'];
    if (message != null) {
      final details = _stringKeyedMap(message);
      if (details == null || details.isNotEmpty) return null;
    }
    if (!_acceptsVersion(root, sourceUri)) return null;
    final variables = _stringKeyedMap(root['Variables']);
    if (variables == null) return null;
    final viewer = discuzMessageAttentionIdentity(variables['member_uid']);
    if (viewer == null || viewer != expected) return null;
    final notice = _stringKeyedMap(variables['notice']);
    if (notice == null) return null;

    // newpm is a bit mask for arrival hints, never a private-message count.
    final privateMessages = _state(_nonNegativeInteger(notice['newpm']));
    final otherNotifications = _nonNegativeInteger(notice['newprompt']);
    final postNotifications = _nonNegativeInteger(notice['newmypost']);
    final notifications = _notificationState(
      otherNotifications,
      postNotifications,
    );
    if (privateMessages == ForumMessageAttentionState.unknown &&
        notifications == ForumMessageAttentionState.unknown) {
      return null;
    }

    return ForumMessageAttentionObservation(
      viewerUserId: viewer,
      source: ForumMessageAttentionSource.api,
      privateMessages: privateMessages,
      notifications: notifications,
      notificationCount: _notificationCount(
        otherNotifications,
        postNotifications,
      ),
    );
  }

  bool _acceptsVersion(Map<String, Object?> root, Uri uri) {
    final queryVersion = uri.queryParameters['version'];
    if (!root.containsKey('Version')) return true;
    final value = root['Version'];
    final envelopeVersion = switch (value) {
      String value => value,
      int value => value.toString(),
      _ => null,
    };
    return discuzMessageAttentionApiVersions.contains(envelopeVersion) &&
        (queryVersion == null || queryVersion == envelopeVersion);
  }
}

// The exact integer range shared by the Dart VM and web targets. Invalid
// values stay unknown instead of overflowing or losing notification identity.
const _maximumExactInteger = 9007199254740991;
final _decimal = RegExp(r'^[0-9]+$');

Map<String, Object?>? _stringKeyedMap(Object? value) {
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    return null;
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key as String: entry.value,
  };
}

int? _nonNegativeInteger(Object? value) {
  final int? parsed;
  switch (value) {
    case int value:
      parsed = value;
    case String value when _decimal.stringMatch(value) == value:
      parsed = int.tryParse(value);
    default:
      return null;
  }
  return parsed != null && parsed >= 0 && parsed <= _maximumExactInteger
      ? parsed
      : null;
}

ForumMessageAttentionState _state(int? value) => value == null
    ? ForumMessageAttentionState.unknown
    : value == 0
    ? ForumMessageAttentionState.absent
    : ForumMessageAttentionState.present;

ForumMessageAttentionState _notificationState(int? other, int? posts) {
  if ((other != null && other > 0) || (posts != null && posts > 0)) {
    return ForumMessageAttentionState.present;
  }
  if (other == 0 && posts == 0) return ForumMessageAttentionState.absent;
  return ForumMessageAttentionState.unknown;
}

int? _notificationCount(int? other, int? posts) {
  if (other == null || posts == null || other > _maximumExactInteger - posts) {
    return null;
  }
  return other + posts;
}
