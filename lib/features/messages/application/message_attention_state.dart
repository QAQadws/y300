import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/auth/domain/models/verified_session_owner.dart';

/// Local request ownership includes both authentication and source lifetime.
typedef MessageAttentionOwner = ({
  VerifiedSessionOwner sessionOwner,
  int sourceGeneration,
});

/// Arrival evidence and the user's local acknowledgement for one owner.
///
/// This state is intentionally ephemeral. Neither [hasAttention] nor the
/// individual hints describe whether every message has been read.
@immutable
final class MessageAttentionState {
  const MessageAttentionState({
    this.owner,
    this.privateMessages = ForumMessageAttentionState.unknown,
    this.notifications = ForumMessageAttentionState.unknown,
    this.combined = ForumMessageAttentionState.unknown,
    this.notificationCount,
    this.attentionEpoch = 0,
    this.acknowledgedMoreEpoch = 0,
  });

  final MessageAttentionOwner? owner;

  /// Latest retained category evidence; an aggregate supersedes covered older
  /// negatives without inventing a positive category.
  final ForumMessageAttentionState privateMessages;
  final ForumMessageAttentionState notifications;

  /// The merged aggregate, calculated using request order and coverage.
  final ForumMessageAttentionState combined;
  final int? notificationCount;
  final int attentionEpoch;
  final int acknowledgedMoreEpoch;

  bool get hasAttention => combined == ForumMessageAttentionState.present;
  bool get hasUnacknowledgedAttention =>
      hasAttention && attentionEpoch > acknowledgedMoreEpoch;

  MessageAttentionProjection project({required bool messagesVisible}) =>
      MessageAttentionProjection(
        messagesNavigationDot: messagesVisible && hasAttention,
        moreNavigationDot: !messagesVisible && hasUnacknowledgedAttention,
        myMessagesDot: !messagesVisible && hasAttention,
      );

  @override
  bool operator ==(Object other) =>
      other is MessageAttentionState &&
      other.owner == owner &&
      other.privateMessages == privateMessages &&
      other.notifications == notifications &&
      other.combined == combined &&
      other.notificationCount == notificationCount &&
      other.attentionEpoch == attentionEpoch &&
      other.acknowledgedMoreEpoch == acknowledgedMoreEpoch;

  @override
  int get hashCode => Object.hash(
    owner,
    privateMessages,
    notifications,
    combined,
    notificationCount,
    attentionEpoch,
    acknowledgedMoreEpoch,
  );
}

/// One projection is shared by normal and selected navigation icons.
@immutable
final class MessageAttentionProjection {
  const MessageAttentionProjection({
    required this.messagesNavigationDot,
    required this.moreNavigationDot,
    required this.myMessagesDot,
  });

  final bool messagesNavigationDot;
  final bool moreNavigationDot;
  final bool myMessagesDot;
}
