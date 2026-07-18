import 'package:flutter/foundation.dart';

enum ComposerSurfacePreference { quill, source }

@immutable
class ComposerPreferences {
  const ComposerPreferences({
    required this.defaultSurface,
    required this.newDraftUseSignature,
  });

  factory ComposerPreferences.defaults() => const ComposerPreferences(
    defaultSurface: ComposerSurfacePreference.quill,
    newDraftUseSignature: true,
  );

  final ComposerSurfacePreference defaultSurface;
  final bool newDraftUseSignature;

  ComposerPreferences copyWith({
    ComposerSurfacePreference? defaultSurface,
    bool? newDraftUseSignature,
  }) {
    return ComposerPreferences(
      defaultSurface: defaultSurface ?? this.defaultSurface,
      newDraftUseSignature: newDraftUseSignature ?? this.newDraftUseSignature,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ComposerPreferences &&
        other.defaultSurface == defaultSurface &&
        other.newDraftUseSignature == newDraftUseSignature;
  }

  @override
  int get hashCode => Object.hash(defaultSurface, newDraftUseSignature);
}
