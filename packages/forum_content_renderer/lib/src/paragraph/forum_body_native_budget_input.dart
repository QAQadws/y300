import 'package:flutter/painting.dart';

import 'forum_body_paragraph_cache.dart';

typedef ForumBodyNativeBudgetSlot = ({
  ForumBodyNativeBudgetInput request,
  double width,
  int minimumLineCount,
});

/// One pure contribution to the existing native cache's aggregate admission.
/// A budget input cannot acquire a resource or grant readable source authority.
abstract class ForumBodyNativeBudgetInput {
  const ForumBodyNativeBudgetInput();

  void includeBudget(
    ForumBodyParagraphBudgetProbe probe, {
    required double width,
    required TextScaler textScaler,
    int minimumLineCount = 1,
  });
}

/// An actual immutable scene specification, separate from font requests. Its
/// native keys and geometry are already frozen; the font-only arguments above
/// do not rescale or requalify it. Visible preparation still binds real source.
final class ForumBodyTextPictureBudgetInput extends ForumBodyNativeBudgetInput {
  const ForumBodyTextPictureBudgetInput(this.input);
  final ForumBodyTextPictureInput input;

  @override
  void includeBudget(
    ForumBodyParagraphBudgetProbe probe, {
    required double width,
    required TextScaler textScaler,
    int minimumLineCount = 1,
  }) => probe.includeTextPicture(input);
}
