import 'package:y300/features/reply/domain/models/reply_models.dart';

class ReplyDraftValidationResult {
  const ReplyDraftValidationResult._({
    required this.isValid,
    this.message,
  });

  const ReplyDraftValidationResult.valid() : this._(isValid: true);

  const ReplyDraftValidationResult.invalid(String message)
      : this._(isValid: false, message: message);

  final bool isValid;
  final String? message;
}

class ReplyDraftValidator {
  const ReplyDraftValidator();

  ReplyDraftValidationResult validate(ReplyDraft draft) {
    if (draft.message.trim().isEmpty) {
      return const ReplyDraftValidationResult.invalid('回复内容不能为空');
    }
    return const ReplyDraftValidationResult.valid();
  }
}
