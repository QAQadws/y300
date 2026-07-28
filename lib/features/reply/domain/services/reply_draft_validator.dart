import 'package:y300/features/reply/domain/models/reply_models.dart';

enum ReplyValidationCode { emptyMessage }

class ReplyDraftValidationResult {
  const ReplyDraftValidationResult._({required this.isValid, this.code});

  const ReplyDraftValidationResult.valid() : this._(isValid: true);

  const ReplyDraftValidationResult.invalid(ReplyValidationCode code)
    : this._(isValid: false, code: code);

  final bool isValid;
  final ReplyValidationCode? code;
}

class ReplyDraftValidator {
  const ReplyDraftValidator();

  ReplyDraftValidationResult validate(ReplyDraft draft) {
    if (draft.message.trim().isEmpty) {
      return const ReplyDraftValidationResult.invalid(
        ReplyValidationCode.emptyMessage,
      );
    }
    return const ReplyDraftValidationResult.valid();
  }
}
