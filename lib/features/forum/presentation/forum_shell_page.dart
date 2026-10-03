import 'package:flutter/material.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';

/// The forum entry shares one UI across all client source profiles.
class ForumShellPage extends StatelessWidget {
  const ForumShellPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  Widget build(BuildContext context) => ForumHomePage(isActive: isActive);
}
