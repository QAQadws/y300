import 'package:flutter/material.dart';

class ComposerSettingsSheet extends StatelessWidget {
  const ComposerSettingsSheet({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class ComposerSettingsSwitchTile extends StatelessWidget {
  const ComposerSettingsSwitchTile({
    super.key,
    required this.tileKey,
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final Key tileKey;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: tileKey,
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(title),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

class ComposerSettingsActionTile extends StatelessWidget {
  const ComposerSettingsActionTile({
    super.key,
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.onPressed,
    this.destructive = false,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive && onPressed != null
        ? Theme.of(context).colorScheme.error
        : null;
    return ListTile(
      key: tileKey,
      leading: Icon(icon, color: color),
      title: Text(title, style: color == null ? null : TextStyle(color: color)),
      contentPadding: EdgeInsets.zero,
      dense: true,
      enabled: onPressed != null,
      onTap: onPressed,
    );
  }
}
