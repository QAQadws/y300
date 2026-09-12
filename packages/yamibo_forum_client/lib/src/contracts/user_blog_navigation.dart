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
  /// Opens the requested feed and filter in the source's browser UI.
  Uri? directory(UserBlogDirectoryQuery query);

  /// Opens an article, including access challenges and comment pagination.
  Uri? detail(UserBlogDetailQuery query);

  /// Opens the complete publishing/editing form, retaining access controls.
  Uri? editor(UserBlogTarget target);

  /// Opens a comment form; additions use the article's comment area.
  Uri? comment(UserBlogCommentTarget target);
}
