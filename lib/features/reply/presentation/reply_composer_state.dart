import 'package:y300/features/reply/domain/models/reply_models.dart';

class ReplyComposerArgs {
  const ReplyComposerArgs({
    required this.target,
    this.title,
  });

  final ReplyTarget target;
  final String? title;

  ReplyDraftIdentity get identity {
    final pid = target.pid;
    if (target.isPostReply && pid != null && pid.trim().isNotEmpty) {
      return ReplyDraftIdentity.post(
        fid: target.fid,
        tid: target.tid,
        repquote: pid,
      );
    }
    return ReplyDraftIdentity.thread(
      fid: target.fid,
      tid: target.tid,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ReplyComposerArgs &&
        other.target.kind == target.kind &&
        other.target.fid == target.fid &&
        other.target.tid == target.tid &&
        other.target.pid == target.pid &&
        other.target.sourceUri == target.sourceUri &&
        other.title == title;
  }

  @override
  int get hashCode => Object.hash(
        target.kind,
        target.fid,
        target.tid,
        target.pid,
        target.sourceUri,
        title,
      );
}

class ReplyComposerState {
  const ReplyComposerState({
    required this.target,
    required this.message,
    required this.useSignature,
    required this.isSubmitting,
    this.errorMessage,
  });

  factory ReplyComposerState.initial({
    required ReplyTarget target,
    String message = '',
    bool useSignature = true,
  }) {
    return ReplyComposerState(
      target: target,
      message: message,
      useSignature: useSignature,
      isSubmitting: false,
    );
  }

  final ReplyTarget target;
  final String message;
  final bool useSignature;
  final bool isSubmitting;
  final String? errorMessage;

  bool get canSubmit => message.trim().isNotEmpty && !isSubmitting;

  ReplyComposerState copyWith({
    String? message,
    bool? useSignature,
    bool? isSubmitting,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ReplyComposerState(
      target: target,
      message: message ?? this.message,
      useSignature: useSignature ?? this.useSignature,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ReplyComposerResult {
  const ReplyComposerResult({
    required this.sent,
    required this.message,
  });

  const ReplyComposerResult.sent(String message)
      : this(sent: true, message: message);

  final bool sent;
  final String message;
}
