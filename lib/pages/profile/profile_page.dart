import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import '../../core/services/api_service.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/app_loading_widget.dart';
import '../../widgets/app_dialogs.dart';
import '../../pages/auth/login_page.dart';
import '../../pages/settings/settings_page.dart';
import '../../pages/profile/device_info_page.dart';
import '../../pages/settings/sos_page.dart';
import '../../pages/profile/edit_profile_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../routes/app_router.dart';

class ProfilePage extends StatefulWidget {
  final int userId;
  const ProfilePage({super.key, required this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const Color _bg = Color(0xFF0D0F11);
  static const Color _card = Color(0xFF1A1D21);
  static const Color _orange = Color(0xFFFF6600);

  final String baseUrl =
      "https://b58k998z-5000.inc1.devtunnels.ms";
  Map<String, dynamic>? data;
  bool loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadProfile(isFirst: true);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadProfile(isFirst: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile({bool isFirst = false}) async {
    if (isFirst) {
      setState(() => loading = true);
    }
    try {
      final res = await ApiService.get(
        Uri.parse(ApiRoutes.userDashboard(widget.userId)),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json["status"] == true && json["data"] != null) {
          if (!mounted) return;
          setState(() {
            data = json["data"];
            loading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    if (isFirst) {
      setState(() => loading = false);
    }
  }


  Future<void> _makePhoneCall(String phoneNumber) async {
    await FlutterPhoneDirectCaller.callNumber(phoneNumber);
  }

  @override
  Widget build(BuildContext context) {
    final String name = data?["name"] ?? "User";
    final String username = data?["username"] ?? "username";

    return Scaffold(
      backgroundColor: _bg,
      body: loading
          ? const AppLoadingWidget()
          : RefreshIndicator(
              onRefresh: _loadProfile,
              color: _orange,
              backgroundColor: _card,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // ── APP BAR ──
                    Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 12,
                        left: 20,
                        right: 20,
                        bottom: 14,
                      ),
                      color: _bg,
                      child: Row(
                        children: [
                          const Text(
                            "Profile",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── AVATAR + NAME ──
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(
                        vertical: 28,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.07),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _orange, width: 2),
                            ),
                            child: CircleAvatar(
                              radius: 34,
                              backgroundColor: _orange.withOpacity(0.12),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : "U",
                                style: const TextStyle(
                                  color: _orange,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "@$username",
                                  style: TextStyle(
                                    color: _orange,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final updated = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EditProfilePage(
                                    userId: widget.userId,
                                    currentData: data ?? {},
                                  ),
                                ),
                              );
                              if (updated == true) {
                                _loadProfile(isFirst: true);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                color: _orange,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── INFO TABLE ──
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.07),
                        ),
                      ),
                      child: Column(
                        children: [
                          _row(
                            Icons.fingerprint_rounded,
                            "IMEI",
                            data?["imei"] ?? "-",
                            isFirst: true,
                          ),
                          _divider(),
                          _row(
                            Icons.location_on_outlined,
                            "Address",
                            data?["user_address"] ?? "Not provided",
                          ),
                          _divider(),
                          _row(
                            Icons.sim_card_outlined,
                            "SIM Number",
                            data?["sim_number"] ?? "-",
                            actionWidget:
                                (data?["sim_number"] != null &&
                                    data!["sim_number"].toString().isNotEmpty &&
                                    data!["sim_number"] != "-")
                                ? GestureDetector(
                                    onTap: () => _makePhoneCall(
                                      data!["sim_number"].toString(),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.call,
                                        color: Colors.green,
                                        size: 16,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          _divider(),
                          _row(
                            Icons.calendar_today_outlined,
                            "Account Created",
                            data?["account_created"] ?? "-",
                            isLast: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── QUICK ACTIONS ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _quickAction(
                              icon: Icons.developer_board_rounded,
                              label: "Device\nInfo",
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DeviceInfoPage(userId: widget.userId),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _quickAction(
                              icon: Icons.settings_rounded,
                              label: "Settings",
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SettingsPage(userId: widget.userId),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _quickAction(
                              icon: Icons.sos_rounded,
                              label: "SOS",
                              iconColor: Colors.redAccent,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        SosPage(userId: widget.userId),
                                  ),
                                );
                                _loadProfile(isFirst: false);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── LOGOUT ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFFFF6600),
                              width: 1.5,
                            ),
                            foregroundColor: _orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => _logout(context),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text(
                            "LOGOUT",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _row(
    IconData icon,
    String label,
    String value, {
    bool isFirst = false,
    bool isLast = false,
    Widget? actionWidget,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 4 : 0, bottom: isLast ? 4 : 0),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: _orange, size: 18),
        title: Text(
          label,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (actionWidget != null) ...[
              const SizedBox(width: 8),
              actionWidget,
            ],
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
    color: Colors.white.withOpacity(0.06),
    height: 1,
    indent: 16,
    endIndent: 16,
  );

  Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor ?? _orange, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await AppDialogs.showConfirm(
      context,
      title: "Logout?",
      message: "Are you sure you want to logout from your account?",
      confirmText: "Logout",
      cancelText: "Cancel",
      isDeleteAction: true,
    );
    if (confirm == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (r) => false,
        );
      }
    }
  }
}
