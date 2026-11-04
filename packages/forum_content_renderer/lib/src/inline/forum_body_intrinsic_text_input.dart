part of 'forum_body_inline_plan_input.dart';

final _asciiScriptWord = RegExp(r'[A-Za-z0-9]+');

// Only proven ASCII alphanumeric seams are grouped here. Other scripts keep
// their existing native input; no guessed Unicode break rule cuts their text.
Iterable<({int start, int end})> _mixedScriptWords(
  ForumBodyParagraphContent context,
) sync* {
  final spans = <({int start, int end, ForumBodyResolvedStyle style})>[];
  var end = 0;
  for (final part in context.projection.parts) {
    spans.add((
      start: end,
      end: end + part.text.length,
      style: context.runs[part.runIndex].style,
    ));
    end += part.text.length;
  }
  var rank = 0;
  for (final word in _asciiScriptWord.allMatches(context.projection.text)) {
    while (rank < spans.length && spans[rank].end <= word.start) {
      rank++;
    }
    if (rank == spans.length) break;
    final first = spans[rank].style.baselineShift;
    var changed = false, shifted = !first.isEmpty;
    for (var i = rank; i < spans.length && spans[i].start < word.end; i++) {
      shifted |= !spans[i].style.baselineShift.isEmpty;
      changed |= !identical(first, spans[i].style.baselineShift);
    }
    if (shifted &&
        changed &&
        context.projection.sourceAtUtf16(word.start).displayUtf16 ==
            word.start &&
        context.projection.sourceAtUtf16(word.end).displayUtf16 == word.end) {
      yield (start: word.start, end: word.end);
    }
  }
}

ForumBodyInlinePlanInput _flattenIntrinsicTextAtom(
  ForumBodyInlinePlanInput input,
  int index,
) {
  final request = input.atoms[index] as ForumBodyIntrinsicInlineAtomRequest;
  final outer = input.content.projection.atoms[index], inner = request.input;
  final ranges = <({int startUtf16, int endUtf16})>[];
  final requests = <ForumBodyRubyAtomRequest>[];
  final levels = <int>[];
  final soft = <int>{};
  for (var i = 0; i < input.atoms.length; i++) {
    if (i == index) {
      for (final atom in inner.content.projection.atoms) {
        if (atom.isSoftSpace) soft.add(ranges.length);
        ranges.add((
          startUtf16: outer.displayStartUtf16 + atom.displayStartUtf16,
          endUtf16: outer.displayStartUtf16 + atom.displayEndUtf16,
        ));
        requests.add(inner.atoms[atom.index]);
        levels.add(-1);
      }
    } else {
      final atom = input.content.projection.atoms[i];
      if (atom.isSoftSpace) soft.add(ranges.length);
      ranges.add((
        startUtf16: atom.displayStartUtf16,
        endUtf16: atom.displayEndUtf16,
      ));
      requests.add(input.atoms[i]);
      levels.add(input.rubyLevelIds[i]);
    }
  }
  final parent = input.content.repartitionAtoms(
    atomicRanges: ranges,
    softSpaceAtoms: soft,
  );
  return ForumBodyInlinePlanInput._(
    parent,
    requests,
    input.width,
    levels,
    input.layoutMode,
    input.sourceContexts,
    parent.projection.display.text.length +
        requests.fold<int>(0, (sum, atom) => sum + atom.extraTextCodeUnits),
    parent.runs.length +
        requests.fold<int>(0, (sum, atom) => sum + atom.extraRuns),
  );
}
