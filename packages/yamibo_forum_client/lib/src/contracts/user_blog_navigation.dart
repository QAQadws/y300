/// Source-owned browser destinations for journals and their complete forms.
library;

import 'profile_and_blog.dart';
import 'user_blog_comments.dart';
import 'user_blog_operations.dart';

/// Builds navigation references without preparing or executing any command.
///
/// These references carry no credentials or form proofs. Opening a write form
/// is not evidence that an operation was applied. Invalid targets return null.
abstract interface class UserBlogNavigation {
  /// Resolves a supported read-only link without requesting or mutating data.
  /// Relative references use [baseUri] or the configured source root. Unknown
  /// filters, ambiguous identities and write forms return null for WebView.
  UserBlogReadReference? resolveReadReference(
    String reference, {
    Uri? baseUri,
    String? actorUserId,
  });

  /// Opens the requested feed and filter in the source's browser UI.
  Uri? directory(UserBlogDirectoryQuery query);

  /// Opens an article, including access challenges and comment pagination.
  Uri? detail(UserBlogDetailQuery query);

  /// Opens the complete publishing/editing form, retaining access controls.
  Uri? editor(UserBlogTarget target);

  /// Opens a comment form; additions use the article's comment area.
  Uri? comment(UserBlogCommentTarget target);
}

/// An explicit native reading destination decoded by the configured source.
sealed class UserBlogReadReference {
  /// Base for the source's supported native read destinations.
  const UserBlogReadReference();
}

/// One journal feed with its original supported filters and page.
final class UserBlogDirectoryReference extends UserBlogReadReference {
  /// Keeps the complete representable feed query.
  const UserBlogDirectoryReference(this.query);

  /// Scope, author, filters and initial page.
  final UserBlogDirectoryQuery query;
}

/// An article, optionally entering its comment section or a specific comment.
final class UserBlogDetailReference extends UserBlogReadReference {
  /// Keeps the article query and the original comment-entry intent.
  const UserBlogDetailReference(this.query, {this.focusComments = false});

  /// Article identity and comment selection.
  final UserBlogDetailQuery query;

  /// Whether the initial viewport should enter the comment section.
  final bool focusComments;
}

/// The public profile identified by a source-owned author link.
final class UserBlogAuthorReference extends UserBlogReadReference {
  /// Uses a verified numeric source identity, never a display name.
  const UserBlogAuthorReference(this.userId);

  /// The public profile's user identifier.
  final String userId;
}
