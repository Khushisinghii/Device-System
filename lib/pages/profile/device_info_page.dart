import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import '../../routes/app_router.dart';
import '../../widgets/app_loading_widget.dart';

class DeviceInfoPage extends StatefulWidget {
  final int userId;
  const DeviceInfoPage({super.key, required this.userId});

  @override
  State<DeviceInfoPage> createState() => _DeviceInfoPageState();
}

class _DeviceInfoPageState extends State<DeviceInfoPage> {
  static const Color _bg = Color(0xFF0D0F11);
  static const Color _card = Color(0xFF1A1D21);
  static const Color _orange = Color(0xFFFF6600);

  final String baseUrl =
      "https://ireland-calculations-chair-unfortunately.trycloudflare.com";
  Map<String, dynamic> data = {};
  bool loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData(isFirst: true);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadData(isFirst: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool isFirst = false}) async {
    if (isFirst) {
      setState(() {
        loading = true;
      });
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
          "Device Information",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: loading
          ? const AppLoadingWidget()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Device icon header
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _orange.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.gps_fixed_rounded,
                            color: _orange,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          data["name"] ?? "GPS Tracker",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "GPS Tracking Device",
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Info table
                  Container(
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Column(
                      children: [
                        _infoRow(
                          "Device Name",
                          data["name"] ?? "-",
                          Icons.badge_outlined,
                          isFirst: true,
                        ),
                        _divider(),
                        _infoRow(
                          "IMEI",
                          data["imei"] ?? "-",
                          Icons.fingerprint_rounded,
                        ),
                        _divider(),
                        _infoRow(
                          "SIM Number",
                          data["sim_number"] ?? "-",
                          Icons.sim_card_outlined,
                        ),
                        _divider(),
                        _infoRow(
                          "Firmware Version",
                          "GT06N-1.0.16",
                          Icons.system_update_alt_rounded,
                        ),
                        _divider(),
                        _infoRow(
                          "Hardware Version",
                          "V1.0",
                          Icons.memory_rounded,
                        ),
                        _divider(),
                        _infoRow(
                          "Battery Level",
                          data["battery"] != null ? "${data["battery"]}%" : "-",
                          Icons.battery_charging_full_rounded,
                          valueColor: _batteryColor(data["battery"]),
                        ),
                        _divider(),
                        _infoRow(
                          "Signal Strength",
                          data["signal_strength"]?.toString() ?? "-",
                          Icons.signal_cellular_alt_rounded,
                        ),
                        _divider(),
                        _infoRow(
                          "Last Update",
                          data["gps_time"] ?? "-",
                          Icons.access_time_rounded,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Status card
                  Builder(
                    builder: (context) {
                      final String statusStr =
                          (data["status"] ?? "").toString().toUpperCase();
                      final lat = double.tryParse(data["latitude"]?.toString() ?? "") ?? 0.0;
                      final lng = double.tryParse(data["longitude"]?.toString() ?? "") ?? 0.0;
                      final bool hasCoordinates = (lat != 0.0 && lng != 0.0);

                      bool isOnline = false;
                      if (hasCoordinates) {
                        DateTime? lastUp;
                        if (data["last_update"] != null) {
                          try {
                            final parts = data["last_update"].toString().trim().split(" ");
                            if (parts.length >= 2) {
                              final dp = parts[0].split("-");
                              final tp = parts[1].split(":");
                              int hour = int.parse(tp[0]);
                              if (parts.length > 2 && parts[2].toUpperCase() == "PM" && hour < 12) hour += 12;
                              if (parts.length > 2 && parts[2].toUpperCase() == "AM" && hour == 12) hour = 0;
                              lastUp = DateTime(int.parse(dp[2]), int.parse(dp[1]), int.parse(dp[0]), hour, int.parse(tp[1]), int.parse(tp[2]));
                            }
                          } catch (_) {}
                        }
                        if (lastUp != null) {
                          final ageSec = DateTime.now().difference(lastUp).inSeconds.abs();
                          if (ageSec <= 60 && statusStr != "OFFLINE") {
                            isOnline = true;
                          }
                        } else if (data["is_online"] == true || statusStr == "ONLINE" || statusStr == "VALID") {
                          isOnline = true;
                        }
                      }
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.07)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline ? Colors.green : Colors.redAccent,
                                boxShadow: [
                                  BoxShadow(
                                    color: isOnline
                                        ? Colors.green.withOpacity(0.5)
                                        : Colors.red.withOpacity(0.5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Tracker Status",
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  isOnline ? "ONLINE" : "OFFLINE",
                                  style: TextStyle(
                                    color: isOnline ? Colors.green : Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Color _batteryColor(dynamic battery) {
    if (battery == null) return Colors.white;
    final v = int.tryParse(battery.toString()) ?? 0;
    if (v > 50) return Colors.green;
    if (v > 20) return _orange;
    return Colors.redAccent;
  }

  Widget _divider() => Divider(
    color: Colors.white.withOpacity(0.06),
    height: 1,
    indent: 20,
    endIndent: 20,
  );

  Widget _infoRow(
    String label,
    String value,
    IconData icon, {
    bool isFirst = false,
    bool isLast = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 6 : 0, bottom: isLast ? 6 : 0),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: _orange, size: 18),
        title: Text(
          label,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
