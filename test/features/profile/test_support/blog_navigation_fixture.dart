import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

final class BlogNavigationFixture implements UserBlogNavigation {
  UserBlogCommentTarget? commentTarget;
  UserBlogDetailQuery? detailQuery;
  UserBlogDirectoryQuery? directoryQuery;
  UserBlogTarget? editorTarget;
  final Uri uri = Uri.parse('https://example.test/fixture');

  @override
  Uri? comment(UserBlogCommentTarget target) {
    commentTarget = target;
    return uri;
  }

  @override
  Uri? detail(UserBlogDetailQuery query) {
    detailQuery = query;
    return uri;
  }

  @override
  Uri? directory(UserBlogDirectoryQuery query) {
    directoryQuery = query;
    return uri;
  }

  @override
  Uri? editor(UserBlogTarget target) {
    editorTarget = target;
    return uri;
  }
}
