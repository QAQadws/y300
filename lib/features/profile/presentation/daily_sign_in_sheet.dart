import 'package:flutter/material.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_page.dart';

class DailySignInSheet extends StatelessWidget {
  const DailySignInSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ListView(
      key: const Key('daily-sign-in-sheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: const [DailySignInPanel(showCard: false)],
    ),
  );
}
