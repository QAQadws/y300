import 'package:flutter/material.dart';
import 'package:y300/features/comic/presentation/comic_tab_page.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/more/presentation/more_page.dart';
import 'package:y300/features/novel/presentation/novel_tab_page.dart';

/// 应用主壳：承载论坛、漫画、小说、更多四栏 Tab，避免业务页面相互耦合。
class MainShellPage extends StatefulWidget {
  const MainShellPage({super.key});

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  int _currentIndex = 0;

  final _pages = const <Widget>[
    ForumHomePage(),
    ComicTabPage(),
    NovelTabPage(),
    MorePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: '论坛',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: '漫画',
          ),
          NavigationDestination(
            icon: SizedBox(
              width: 24,
              height: 24,
              child: Center(child: Icon(Icons.local_library_outlined)),
            ),
            selectedIcon: SizedBox(
              width: 24,
              height: 24,
              child: Center(child: Icon(Icons.local_library)),
            ),
            label: '小说',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_outlined),
            selectedIcon: Icon(Icons.more_horiz),
            label: '更多',
          ),
        ],
      ),
    );
  }
}
