import 'package:flutter/material.dart';

/// Keep the scrollable mounted across the initial read and subsequent refreshes.
class ProfilePageBody extends StatelessWidget {
  const ProfilePageBody({
    super.key,
    required this.child,
    this.isRefreshing = false,
  });

  final Widget child;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ListView(
        key: const Key('user-profile-page-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: child,
            ),
          ),
        ],
      ),
      if (isRefreshing)
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: LinearProgressIndicator(
              key: Key('user-profile-refresh-progress'),
              minHeight: 2,
            ),
          ),
        ),
    ],
  );
}
