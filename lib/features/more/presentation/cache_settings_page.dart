import 'package:flutter/widgets.dart';
import 'package:y300/features/more/presentation/data_storage_page.dart';

@Deprecated('Use DataStoragePage instead.')
class CacheSettingsPage extends StatelessWidget {
  const CacheSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DataStoragePage();
  }
}
