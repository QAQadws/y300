import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

String? validateForumDirectory(ForumDirectoryData directory) {
  final sectionIdentities = <String>{};
  final forumIdentities = <String>{};
  for (final section in directory.sections) {
    final sectionIdentity = section.identity.trim();
    if (sectionIdentity.isEmpty || !sectionIdentities.add(sectionIdentity)) {
      return '论坛版块目录包含空或重复的分组 identity';
    }
    if (section.kind == ForumDirectorySectionKind.regular &&
        section.title.trim().isEmpty) {
      return '论坛版块目录包含空的分组标题';
    }
    for (final forum in section.forums) {
      final error = _validateForum(forum, forumIdentities);
      if (error != null) {
        return error;
      }
    }
  }
  return null;
}

String? _validateForum(ForumDirectoryForum forum, Set<String> forumIdentities) {
  final fid = forum.fid.trim();
  if (fid.isEmpty || !forumIdentities.add(fid)) {
    return '论坛版块目录包含空或重复的版块 identity';
  }
  if (forum.title.trim().isEmpty) {
    return '论坛版块目录包含空的版块标题';
  }
  if (forum.todayPosts != null && forum.todayPosts! < 0) {
    return '论坛版块目录包含无效的今日发帖数';
  }
  for (final child in forum.children) {
    final error = _validateForum(child, forumIdentities);
    if (error != null) {
      return error;
    }
  }
  return null;
}
