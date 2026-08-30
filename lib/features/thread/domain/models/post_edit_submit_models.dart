/// App presentation state for one post-edit command.
enum PostEditSubmitResponseKind {
  confirmedSuccess,
  businessFailure,
  authenticationFailure,
  permissionFailure,
  formExpired,
  ambiguous,
  partialSuccess,
}
