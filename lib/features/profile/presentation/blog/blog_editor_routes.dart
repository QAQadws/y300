import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

Future<BlogEditorResult?> openBlogEditorPage(
  BuildContext context,
  WidgetRef ref, {
  String? ownerUserId,
  String? blogId,
}) async {
  final actor = ref.read(blogAccountIdProvider);
  if (actor == null) {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const LoginPage()));
    return null;
  }
  return Navigator.of(context).push<BlogEditorResult>(
    MaterialPageRoute(
      builder: (_) => BlogEditorPage(
        target: UserBlogTarget(
          actorUserId: actor,
          ownerUserId: blogId == null ? actor : ownerUserId!,
          blogId: blogId,
          action: blogId == null ? UserBlogAction.create : UserBlogAction.edit,
        ),
      ),
    ),
  );
}
