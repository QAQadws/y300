import 'package:flutter/material.dart';

@immutable
class ForumContentAction<T> {
  const ForumContentAction({
    required this.value,
    required this.label,
    required this.icon,
    this.key,
  });

  final T value;
  final String label;
  final IconData icon;
  final Key? key;
}

class ForumContentActionSheet<T> extends StatelessWidget {
  const ForumContentActionSheet({super.key, required this.actions});

  final List<ForumContentAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in actions)
                ListTile(
                  key: action.key,
                  dense: true,
                  leading: Icon(action.icon),
                  title: Text(action.label),
                  onTap: () => Navigator.of(context).pop(action.value),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
