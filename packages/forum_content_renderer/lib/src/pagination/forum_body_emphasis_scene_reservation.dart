part of 'forum_body_text_page_composer.dart';

/// One growing fragment, separate from the real-font native identity ledger.
/// Candidates replace its scalar reservation; they never create fake picture
/// keys. Only newly consumed complete groups are inspected, avoiding repeated
/// construction/scanning of a growing merged command list.
final class _EmphasisSceneReservation {
  _EmphasisSceneReservation(
    this.firstTop, {
    this.maxGroups = ForumBodyEmphasisFragmentInputPreparation.defaultMaxGroups,
    this.maxCommands =
        ForumBodyEmphasisFragmentInputPreparation.defaultMaxCommands,
  });
  final double firstTop;
  final int maxGroups, maxCommands;
  final _metadata = <Object, int>{};
  int _commands = 0, _groups = 0, _input = 0, _picture = 0, _metadataBytes = 0;
  int get estimatedBytes => _commands == 0
      ? 0
      : ForumBodyTextPictureInput.baseEstimatedInputBytes +
            ForumBodyTextPictureInput.baseEstimatedPictureBytes +
            _input +
            _picture +
            _metadataBytes;

  _EmphasisSceneAddition propose(
    Iterable<ForumBodyTextSceneContribution> added,
  ) {
    var commands = _commands,
        groups = _groups,
        input = _input,
        picture = _picture,
        metadataBytes = _metadataBytes;
    var depthFits = true;
    final metadata = <Object, int>{};
    for (final part in added) {
      final translated =
          part.translationOriginY != null &&
          part.translationOriginY != firstTop;
      groups++;
      commands += part.commandCount;
      input +=
          part.inputCommandBytes +
          (translated
              ? part.commandCount *
                    ForumBodyTextPictureCommand.translationInputEstimatedBytes
              : 0);
      picture +=
          part.pictureCommandBytes +
          (translated
              ? part.commandCount *
                    ForumBodyTextPictureCommand.translationPictureEstimatedBytes
              : 0);
      depthFits =
          depthFits &&
          part.maximumTranslationDepth + (translated ? 1 : 0) <=
              ForumBodyTextPictureCommand.maximumTranslationDepth;
      for (final cost in part.retainedMetadata.entries) {
        if (!_metadata.containsKey(cost.key) &&
            !metadata.containsKey(cost.key)) {
          metadata[cost.key] = cost.value;
          metadataBytes += cost.value;
        }
      }
    }
    return _EmphasisSceneAddition(
      commands,
      groups,
      input,
      picture,
      metadataBytes,
      metadata,
      depthFits,
      maxGroups,
      maxCommands,
    );
  }

  void apply(_EmphasisSceneAddition addition) {
    _commands = addition.commands;
    _groups = addition.groups;
    _input = addition.input;
    _picture = addition.picture;
    _metadataBytes = addition.metadataBytes;
    _metadata.addAll(addition.metadata);
  }
}

final class _EmphasisSceneAddition {
  const _EmphasisSceneAddition(
    this.commands,
    this.groups,
    this.input,
    this.picture,
    this.metadataBytes,
    this.metadata,
    this.depthFits,
    this.maxGroups,
    this.maxCommands,
  );
  final int commands, groups, input, picture, metadataBytes;
  final Map<Object, int> metadata;
  final bool depthFits;
  final int maxGroups, maxCommands;
  bool get withinLimits =>
      depthFits && groups > 0 && groups <= maxGroups && commands <= maxCommands;
  int get estimatedBytes => commands == 0
      ? 0
      : ForumBodyTextPictureInput.baseEstimatedInputBytes +
            ForumBodyTextPictureInput.baseEstimatedPictureBytes +
            input +
            picture +
            metadataBytes;
}
