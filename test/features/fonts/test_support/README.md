# Font test fixtures

`material_icons_subset_1.ttf` and `material_icons_subset_2.ttf` are unmodified
copies of Flutter engine's `tools/font_subset/fixtures/1.ttf` and `2.ttf`.
These tiny TrueType fonts contain one and two Material Icons glyphs respectively;
Flutter's `tools/font_subset/test.py` documents their source and subsets.

- Fixture source: <https://github.com/flutter/flutter/tree/master/engine/src/flutter/tools/font_subset/fixtures>
- Original typeface: Material Icons, version 1.015.
- Embedded copyright: Copyright 2015 Google, Inc. All Rights Reserved.
- Original project and license: <https://github.com/google/material-design-icons/blob/master/LICENSE>
- License: Apache License 2.0, included as `materialicons_license.txt`.

The subset operation was performed upstream. These files are test inputs only,
are not declared as Flutter assets, and are not shipped with the application.

`flutter_test_cff.otf` is an unmodified copy of Flutter engine's
`impeller/fixtures/wtf.otf`, a tiny CFF-based OpenType font named WhatTheFlutter.
Its embedded notice is Copyright (c) 2022, The Flutter Authors. All rights
reserved. The engine's BSD license is included as `flutter_fixture_license.txt`.
Source: <https://github.com/flutter/flutter/blob/master/engine/src/flutter/impeller/fixtures/wtf.otf>.

`font_test_fixtures.dart` reads fresh bytes for each test so corruption cases can
mutate one copy without contaminating other tests.
