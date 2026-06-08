import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';

class ReaderTopOverlayBar extends StatelessWidget {
  const ReaderTopOverlayBar({
    super.key,
    required this.config,
  });

  final ReaderTopBarConfig config;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('shared-reader-top-overlay-bar'),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              IconButton(
                key: const Key('shared-reader-top-back-button'),
                tooltip: '返回',
                onPressed: config.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: InkWell(
                  key: const Key('shared-reader-title-button'),
                  onTap: config.onTitleTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.title,
                          key: const Key('shared-reader-top-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          config.subtitle,
                          key: const Key('shared-reader-top-subtitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              for (final action in config.actions)
                IconButton(
                  key: Key('shared-reader-top-action-${action.id}'),
                  tooltip: action.label,
                  onPressed: action.enabled ? action.onPressed : null,
                  icon: Icon(action.icon),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
