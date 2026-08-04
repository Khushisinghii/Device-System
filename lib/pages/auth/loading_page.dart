import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import '../../routes/app_router.dart';
// Import your dashboards here
import '../../pages/dashboard/admin_dashboard.dart';
import '../../pages/dashboard/user_home_page.dart';

class LoadingPage extends StatefulWidget {
  final String role;
  final int userId;

  const LoadingPage({super.key, required this.role, required this.userId});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Setup Animation: A "Breathing" pulse effect
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _opacityAnimation = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // 2. Navigation Logic
    _startLoading();
  }

  Future<void> _startLoading() async {
    final delay = Future.delayed(const Duration(milliseconds: 1800));

    Map<String, dynamic>? dashboardData;
    if (widget.role == "user") {
      try {
        final res = await ApiService
            .get(
              Uri.parse(
                ApiRoutes.userDashboard(widget.userId),
              ),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          if (json["status"] == true && json["data"] != null) {
            dashboardData = json["data"];
          }
        }
      } catch (_) {}
    }

    await delay;

    if (!mounted) return;

    if (widget.role == "admin") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminDashboard()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UserHomePage(
            userId: widget.userId,
            initialDashboardData: dashboardData,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color brandOrange = Color(0xFFFF6600);
    const Color brandDarkBg = Color(0xFF0D0F11);

    return Scaffold(
      backgroundColor: brandDarkBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- RECREATING LOGO WITH WIDGETS ---
            FadeTransition(
              opacity: _opacityAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  children: [
                    // Location Pin Icon (Top of Logo)
                    const Icon(Icons.location_on, size: 80, color: brandOrange),
                    const SizedBox(height: 10),
                    // "ScanID" Text styled like the logo
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Scan",
                          style: TextStyle(
                            fontSize: 50,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                            letterSpacing: -2,
                          ),
                        ),
                        SizedBox(width: 5),
                        Text(
                          "ID",
                          style: TextStyle(
                            fontSize: 50,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: brandOrange,
                            letterSpacing: -2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 60),

            // --- THEMED PROGRESS INDICATOR ---
            const SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(brandOrange),
                strokeWidth: 5,
              ),
            ),

            const SizedBox(height: 30),

            // --- LOADING TEXT ---
            Text(
              "TRACKING SYSTEM",
              style: TextStyle(
                fontSize: 14,
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
