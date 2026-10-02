import 'package:flutter/widgets.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_page.dart';

export 'user_thread_page.dart';

/// Current-user entry; all reading and rendering belongs to UserThreadPage.
class MyThreadPage extends StatelessWidget {
  const MyThreadPage({
    super.key,
    this.initialType = UserThreadDirectoryType.threads,
    this.isActive = true,
    this.onOpenThread,
  });

  final UserThreadDirectoryType initialType;
  final bool isActive;
  final UserThreadOpener? onOpenThread;

  @override
  Widget build(BuildContext context) => UserThreadPage(
    initialType: initialType,
    isActive: isActive,
    onOpenThread: onOpenThread,
  );
}
