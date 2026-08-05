import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/services/api_service.dart';
import '../../pages/auth/login_page.dart';
import '../../pages/profile/device_info_page.dart';
import '../../pages/geofence/geofence_page.dart';
import '../../pages/dashboard/alerts_page.dart';
import '../../pages/settings/sos_page.dart';
import '../../pages/auth/forgot_password.dart';
import '../../widgets/app_loading_widget.dart';
import '../../widgets/app_dialogs.dart';
import '../../routes/app_router.dart';

class SettingsPage extends StatefulWidget {
  final int userId;
  const SettingsPage({super.key, required this.userId});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const Color _bg = Color(0xFF0D0F11);
  static const Color _card = Color(0xFF1A1D21);
  static const Color _orange = Color(0xFFFF6600);

  final String baseUrl =
      "https://partners-vegetables-algebra-dryer.trycloudflare.com";

  bool _notifyLowBattery = true;
  bool _notifyFullBattery = true;
  bool _notifyGeofence = true;
  bool _notifySpeed = true;
  bool _loadingSettings = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final res = await ApiService.get(
        Uri.parse(ApiRoutes.userDashboard(widget.userId)),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json["status"] == true && json["data"] != null) {
          final d = json["data"];
          setState(() {
            _notifyLowBattery = (d["notify_low_battery"] ?? 1) == 1;
            _notifyFullBattery = (d["notify_full_battery"] ?? 1) == 1;
            _notifyGeofence = (d["notify_geofence"] ?? 1) == 1;
            _notifySpeed = (d["notify_speed"] ?? 1) == 1;
            _loadingSettings = false;
          });
          return;
        }
      }
    } catch (_) {}
    setState(() => _loadingSettings = false);
  }

  Future<void> _updateSettings() async {
    try {
      final headers = {"Content-Type": "application/json"};
      final body = jsonEncode({
        "notify_low_battery": _notifyLowBattery ? 1 : 0,
        "notify_full_battery": _notifyFullBattery ? 1 : 0,
        "notify_geofence": _notifyGeofence ? 1 : 0,
        "notify_speed": _notifySpeed ? 1 : 0,
      });
      await ApiService.put(
        Uri.parse(ApiRoutes.userSettings(widget.userId)),
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Settings",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: _loadingSettings
          ? const AppLoadingWidget()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- DEVICE SECTION ---
                  _sectionLabel("Device"),
                  const SizedBox(height: 10),
                  _settingsCard([
                    _menuItem(
                      context,
                      icon: Icons.developer_board_rounded,
                      label: "Device Information",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeviceInfoPage(userId: widget.userId),
                        ),
                      ),
                    ),
                    _divider(),
                    _menuItem(
                      context,
                      icon: Icons.fence_rounded,
                      label: "Geofence Settings",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GeofencePage()),
                      ),
                    ),
                    _divider(),
                    _menuItem(
                      context,
                      icon: Icons.notifications_rounded,
                      label: "Alerts & Notifications",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AlertsPage()),
                      ),
                    ),
                    _divider(),
                    _menuItem(
                      context,
                      icon: Icons.sos_rounded,
                      label: "SOS Emergency",
                      iconColor: Colors.redAccent,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SosPage(userId: widget.userId),
                        ),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // --- NOTIFICATIONS SECTION ---
                  _sectionLabel("Notification Toggles"),
                  const SizedBox(height: 10),
                  _settingsCard([
                    _toggleItem(
                      icon: Icons.battery_alert_rounded,
                      iconColor: Colors.redAccent,
                      label: "Low Battery Notifications",
                      value: _notifyLowBattery,
                      onChanged: (val) {
                        setState(() => _notifyLowBattery = val);
                        _updateSettings();
                      },
                    ),
                    _divider(),
                    _toggleItem(
                      icon: Icons.battery_charging_full_rounded,
                      iconColor: Colors.green,
                      label: "Full Battery Notifications",
                      value: _notifyFullBattery,
                      onChanged: (val) {
                        setState(() => _notifyFullBattery = val);
                        _updateSettings();
                      },
                    ),
                    _divider(),
                    _toggleItem(
                      icon: Icons.fence_rounded,
                      iconColor: Colors.blueAccent,
                      label: "Geofence Alerts",
                      value: _notifyGeofence,
                      onChanged: (val) {
                        setState(() => _notifyGeofence = val);
                        _updateSettings();
                      },
                    ),
                    _divider(),
                    _toggleItem(
                      icon: Icons.speed_rounded,
                      iconColor: Colors.amber,
                      label: "Overspeed Alerts",
                      value: _notifySpeed,
                      onChanged: (val) {
                        setState(() => _notifySpeed = val);
                        _updateSettings();
                      },
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // --- APP SECTION ---
                  _sectionLabel("App"),
                  const SizedBox(height: 10),
                  _settingsCard([
                    _menuItem(
                      context,
                      icon: Icons.gps_fixed_rounded,
                      label: "Tracking Mode",
                      trailing: _badge("Normal"),
                      onTap: () => _showTrackingModeSheet(context),
                    ),
                    _divider(),
                    _menuItem(
                      context,
                      icon: Icons.lock_outline_rounded,
                      label: "Change Password",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ForgotPasswordPage(),
                        ),
                      ),
                    ),
                    _divider(),
                    _menuItem(
                      context,
                      icon: Icons.info_outline_rounded,
                      label: "About Us",
                      onTap: () => _showAboutDialog(context),
                    ),
                  ]),

                  const SizedBox(height: 40),

                  // --- LOGOUT ---
                  SizedBox(
                    width: double.infinity,
                    height: 54,
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
                      onPressed: () => _handleLogout(context),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(
                        "LOGOUT",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: Colors.grey.shade600,
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.5,
    ),
  );

  Widget _settingsCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: Column(children: children),
  );

  Widget _menuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (iconColor ?? _orange).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor ?? _orange, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade600,
                  size: 20,
                ),
          ],
        ),
      ),
    );
  }

  Widget _toggleItem({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (iconColor ?? _orange).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor ?? _orange, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(value: value, activeColor: _orange, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
    color: Colors.white.withOpacity(0.06),
    height: 1,
    indent: 68,
    endIndent: 16,
  );

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _orange.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: _orange,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  void _showTrackingModeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1D21),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Tracking Mode",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...[
              {"label": "Normal", "desc": "Updates every 30 seconds"},
              {"label": "Power Saving", "desc": "Updates every 5 minutes"},
              {"label": "High Accuracy", "desc": "Updates every 5 seconds"},
            ].map(
              (m) => ListTile(
                title: Text(
                  m["label"]!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  m["desc"]!,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                trailing: m["label"] == "Normal"
                    ? Icon(Icons.check_circle_rounded, color: _orange)
                    : null,
                onTap: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    AppDialogs.showSuccess(
      context,
      title: "About ScanID",
      message:
          "GPS Tracking System\nVersion 1.0.0\n\nReal-time GPS tracking with geofence alerts and history playback.",
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await AppDialogs.showConfirm(
      context,
      title: "Logout?",
      message: "Are you sure you want to logout from your account?",
      confirmText: "Logout",
      cancelText: "Cancel",
      isDeleteAction: true,
    );
    if (confirm == true) {
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
