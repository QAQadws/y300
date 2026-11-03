part of 'forum_body_emphasis_paragraph_metrics.dart';

/// A complete group's pure native font estimates and scene contribution.
/// Command bytes exclude scene bases and unique retained input metadata. They
/// can be appended to ONE growing fragment reservation without rebuilding its
/// command list or fabricating a native picture identity for each candidate.
final class ForumBodyEmphasisGroupNativeEntries {
  ForumBodyEmphasisGroupNativeEntries._({
    required this.group,
    required this.fonts,
    required Map<Object, int> retainedMetadata,
    required this.commandCount,
    required this.inputCommandBytes,
    required this.pictureCommandBytes,
    required this.maximumTranslationDepth,
  }) : retainedMetadata = UnmodifiableMapView(retainedMetadata);
  final ForumBodyEmphasisParagraphGroup group;
  final List<ForumBodyNativeInputCost> fonts;

  /// Drawing-key retention only. Do not substitute it for native font costs.
  final Map<Object, int> retainedMetadata;
  final int commandCount, inputCommandBytes, pictureCommandBytes;
  final int maximumTranslationDepth;
}

/// Pure per-group budget index for the exact whole paragraph. It owns neither
/// native handles nor a cache/owner callback; current visible qualification and
/// the finalized exact-scene probe remain mandatory.
final class ForumBodyEmphasisParagraphNativeEntries {
  ForumBodyEmphasisParagraphNativeEntries._(
    this.paragraph,
    List<ForumBodyEmphasisGroupNativeEntries> groups,
  ) : groups = UnmodifiableListView(groups);
  static const revision = 1;
  final ForumBodyEmphasisParagraphMetrics paragraph;
  final List<ForumBodyEmphasisGroupNativeEntries> groups;
  Iterable<ForumBodyEmphasisGroupNativeEntries> inLines(int start, int end) {
    final range = paragraph.fragment(start, end);
    return groups.getRange(range.startGroup, range.endGroup);
  }

  Iterable<ForumBodyNativeInputCost> fontCostsInLines(
    int start,
    int end,
  ) sync* {
    for (final group in inLines(start, end)) {
      yield* group.fonts;
    }
  }
}

enum _EmphasisEntryPhase { fonts, commands, seal, ready, closed }

/// Inspects one font request or one scene command per part, using the SAME
/// existing probe and command-retention formulas as visible preparation. Each
/// complete group gets its own probe: unrelated marker styles elsewhere in the
/// paragraph do not have to fit in a single page's native budget together.
final class ForumBodyEmphasisParagraphNativeEntriesPreparation {
  ForumBodyEmphasisParagraphNativeEntriesPreparation({
    required ForumBodyEmphasisParagraphMetrics paragraph,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
  }) : _paragraph = paragraph,
       _cache = cache,
       _ensureOwner = ensureOwner;
  ForumBodyEmphasisParagraphMetrics? _paragraph;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  List<ForumBodyEmphasisGroupNativeEntries> _groups = [];
  Iterator<ForumBodyNativeRequestSlot>? _requests;
  ForumBodyParagraphBudgetProbe? _probe;
  List<ForumBodyNativeInputCost>? _fonts;
  Map<Object, int> _metadata = {};
  int _command = 0, _inputBytes = 0, _pictureBytes = 0, _depth = 0;
  var _phase = _EmphasisEntryPhase.fonts;
  bool _operating = false;
  bool get isReady => _phase == _EmphasisEntryPhase.ready;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Emphasis native entries are reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        if (_groups.length == _paragraph!.groups.length) {
          _phase = _EmphasisEntryPhase.ready;
        } else {
          final group = _paragraph!.groups[_groups.length];
          switch (_phase) {
            case _EmphasisEntryPhase.fonts:
              _requests ??= group.allocation.nativeFootprint.iterator;
              _probe ??= _cache!.createBudgetProbe(captureInputEstimates: true);
              if (_requests!.moveNext()) {
                final slot = _requests!.current;
                slot.request.includeBudget(
                  _probe!,
                  width: slot.width,
                  textScaler: _paragraph!.textScaler,
                  minimumLineCount: slot.minimumLineCount,
                );
              } else {
                _fonts = _probe!.snapshotNativeEstimates();
                _probe!.close();
                _probe = null;
                _requests = null;
                _phase = _EmphasisEntryPhase.commands;
              }
            case _EmphasisEntryPhase.commands:
              final commands = group.sceneInput.pictureInput.commands;
              if (_command < commands.length) {
                final command = commands[_command++],
                    key = command.nativeInputIdentity;
                _inputBytes += command.estimatedInputBytes;
                _pictureBytes += command.estimatedPictureBytes;
                _depth = math.max(_depth, command.translationDepth);
                _metadata.putIfAbsent(
                  key,
                  () =>
                      ForumBodyTextPictureInput.estimateRetainedMetadataBytesFor(
                        key,
                      ),
                );
              } else {
                _phase = _EmphasisEntryPhase.seal;
              }
            case _EmphasisEntryPhase.seal:
              _groups.add(
                ForumBodyEmphasisGroupNativeEntries._(
                  group: group,
                  fonts: _fonts!,
                  retainedMetadata: _metadata,
                  commandCount: _command,
                  inputCommandBytes: _inputBytes,
                  pictureCommandBytes: _pictureBytes,
                  maximumTranslationDepth: _depth,
                ),
              );
              _metadata = {};
              _fonts = null;
              _command = 0;
              _inputBytes = 0;
              _pictureBytes = 0;
              _depth = 0;
              _phase = _EmphasisEntryPhase.fonts;
            case _EmphasisEntryPhase.ready:
            case _EmphasisEntryPhase.closed:
              throw StateError('Emphasis native entries are retired');
          }
        }
        used++;
        _guard();
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyEmphasisParagraphNativeEntries take() {
    if (_operating) throw StateError('Emphasis native entries are reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Emphasis native entries are incomplete');
      final result = ForumBodyEmphasisParagraphNativeEntries._(
        _paragraph!,
        _groups,
      );
      _groups = [];
      close();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _EmphasisEntryPhase.closed) {
      throw StateError('Emphasis native entries are retired');
    }
    _ensureOwner!();
    if (_phase == _EmphasisEntryPhase.closed || _cache?.isClosed != false) {
      throw StateError('Emphasis native entry owner is retired');
    }
  }

  void close() {
    if (_phase == _EmphasisEntryPhase.closed) return;
    _phase = _EmphasisEntryPhase.closed;
    _probe?.close();
    _probe = null;
    _requests = null;
    _fonts = null;
    _metadata = {};
    _groups = [];
    _paragraph = null;
    _cache = null;
    _ensureOwner = null;
  }
}
