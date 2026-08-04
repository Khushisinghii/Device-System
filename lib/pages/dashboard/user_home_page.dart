import 'package:flutter/material.dart';
import '../../pages/dashboard/user_dashboard.dart';
import '../../pages/live_tracking/map_page.dart';
import '../../pages/history/history_page.dart';
import '../../pages/geofence/geofence_page.dart';
import '../../pages/profile/profile_page.dart';

class UserHomePage extends StatefulWidget {
  final int userId;
  final Map<String, dynamic>? initialDashboardData;
  const UserHomePage({super.key, required this.userId, this.initialDashboardData});

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  int currentIndex = 0;

  static const Color _orange = Color(0xFFFF6600);
  static const Color _navBg = Color(0xFF0D0F11);
  static const Color _navBorder = Color(0xFF1E2227);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F11),
      body: IndexedStack(
        index: currentIndex,
        children: [
          UserDashboard(userId: widget.userId, initialData: widget.initialDashboardData),
          MapPage(userId: widget.userId),
          HistoryPage(userId: widget.userId),
          const GeofencePage(),
          ProfilePage(userId: widget.userId),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: _navBg,
          border: Border(top: BorderSide(color: _navBorder, width: 1)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(0, Icons.grid_view_rounded, Icons.grid_view_rounded, "Dashboard"),
                _navItem(1, Icons.location_searching_rounded, Icons.location_on_rounded, "Live Map"),
                _navItem(2, Icons.history_rounded, Icons.history_rounded, "History"),
                _navItem(3, Icons.fence_rounded, Icons.fence_rounded, "Geofence"),
                _navItem(4, Icons.person_outline_rounded, Icons.person_rounded, "Profile"),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final bool active = currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _orange.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? activeIcon : icon,
              color: active ? _orange : Colors.white38,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? _orange : Colors.white38,
                fontSize: 10,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
