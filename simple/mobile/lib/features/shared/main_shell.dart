import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../lists/lists_screen.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.guestMode = false});

  final bool guestMode;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(guestMode: widget.guestMode),
      const SearchScreen(),
      LibraryScreen(guestMode: widget.guestMode),
      ListsScreen(guestMode: widget.guestMode),
      ProfileScreen(guestMode: widget.guestMode),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'خانه'),
          NavigationDestination(icon: Icon(Icons.search), label: 'جست‌وجو'),
          NavigationDestination(icon: Icon(Icons.video_library_outlined), label: 'تماشا'),
          NavigationDestination(icon: Icon(Icons.playlist_add_check_outlined), label: 'فهرست‌ها'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'پروفایل'),
        ],
      ),
    );
  }
}

class AuthRequiredView extends StatelessWidget {
  const AuthRequiredView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_person_outlined, size: 72),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              icon: const Icon(Icons.login),
              label: const Text('ورود یا ثبت‌نام'),
            ),
          ],
        ),
      ),
    );
  }
}
