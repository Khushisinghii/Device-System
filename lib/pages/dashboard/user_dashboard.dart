import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/services/api_service.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/app_loading_widget.dart';
import '../../pages/live_tracking/map_page.dart';
import '../../pages/dashboard/alerts_page.dart';

class UserDashboard extends StatefulWidget {
  final int userId;
  final Map<String, dynamic>? initialData;
  const UserDashboard({super.key, required this.userId, this.initialData});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  static const Color _bg = Color(0xFF0D0F11);
  static const Color _card = Color(0xFF1A1D21);
  static const Color _orange = Color(0xFFFF6600);

  final String baseUrl =
      "https://b58k998z-5000.inc1.devtunnels.ms";
  Map<String, dynamic> data = {};
  bool loading = true;
  bool hasError = false;
  Timer? _refreshTimer;
  bool _hasNewNotifications = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      data = widget.initialData!;
      loading = false;
    } else {
      _loadData(isFirst: true);
    }
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
        hasError = false;
      });
    }
    try {
      final res = await ApiService.get(
        Uri.parse("$baseUrl/user_dashboard/${widget.userId}"),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json["status"] == true && json["data"] != null) {
          if (!mounted) return;
          setState(() {
            data = json["data"];
            loading = false;
          });

          // Also fetch notifications silently in the background to check for new ones
          _checkNewNotifications();
          return;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    if (isFirst) {
      setState(() {
        loading = false;
        hasError = true;
      });
    }
  }

  Future<void> _checkNewNotifications() async {
    try {
      final res = await ApiService.get(
        Uri.parse("$baseUrl/notifications/${widget.userId}"),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List<dynamic> fetchedNotifications = jsonDecode(res.body)["data"];
        final prefs = await SharedPreferences.getInstance();
        int savedCount =
            prefs.getInt('notification_count_${widget.userId}') ?? 0;

        if (fetchedNotifications.length > savedCount) {
          if (mounted) setState(() => _hasNewNotifications = true);
        } else {
          if (mounted) setState(() => _hasNewNotifications = false);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: loading
          ? const AppLoadingWidget()
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _orange,
              backgroundColor: _card,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    _buildAppBar(context),
                    _buildProfileCard(),
                    _buildTelemetrySection(context),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    await FlutterPhoneDirectCaller.callNumber(phoneNumber);
  }

  Future<void> _onBellTapped() async {
    // 1. Mark as read immediately
    setState(() => _hasNewNotifications = false);

    // 2. Fetch the current count and save it to preferences
    try {
      final res = await ApiService.get(
        Uri.parse("$baseUrl/notifications/${widget.userId}"),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final count = (jsonDecode(res.body)["data"] as List).length;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('notification_count_${widget.userId}', count);
      }
    } catch (_) {}

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AlertsPage()),
      );
    }
  }

  // ── APP BAR ────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 20,
        right: 16,
        bottom: 14,
      ),
      color: _bg,
      child: Row(
        children: [
          // ScanID logo
          const Icon(Icons.location_on, color: _orange, size: 24),
          const SizedBox(width: 6),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: "Scan",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                TextSpan(
                  text: "ID",
                  style: TextStyle(
                    color: _orange,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Notification bell
          GestureDetector(
            onTap: _onBellTapped,
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                if (_hasNewNotifications)
                  Positioned(
                    right: 7,
                    top: 7,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: _bg, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _parseLastUpdate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final clean = raw.trim();
      final parts = clean.split(" ");
      if (parts.length >= 2) {
        final dateParts = parts[0].split("-");
        final timeParts = parts[1].split(":");
        int day = int.parse(dateParts[0]);
        int month = int.parse(dateParts[1]);
        int year = int.parse(dateParts[2]);

        int hour = int.parse(timeParts[0]);
        int minute = int.parse(timeParts[1]);
        int second = int.parse(timeParts[2]);

        if (parts.length > 2) {
          final amPm = parts[2].toUpperCase();
          if (amPm == "PM" && hour < 12) hour += 12;
          if (amPm == "AM" && hour == 12) hour = 0;
        }
        return DateTime(year, month, day, hour, minute, second);
      }
      return DateTime.tryParse(clean);
    } catch (_) {
      return null;
    }
  }

  // ── PROFILE CARD ────────────────────────────────────────────
  Widget _buildProfileCard() {
    final String name = data["name"] ?? "User";
    final String username = data["username"] ?? "username";
    final String statusStr =
        (data["status"]?.toString().toUpperCase() ?? "");

    // Must have valid lat/long coordinates coming in
    final lat = double.tryParse(data["latitude"]?.toString() ?? "") ?? 0.0;
    final lng = double.tryParse(data["longitude"]?.toString() ?? "") ?? 0.0;
    final bool hasCoordinates = (lat != 0.0 && lng != 0.0);

    // Online only if coordinates exist and received within 1 minute (60 seconds)
    bool isOnline = false;
    if (hasCoordinates) {
      final lastUp = _parseLastUpdate(data["last_update"]?.toString());
      if (lastUp != null) {
        final ageSec = DateTime.now().difference(lastUp).inSeconds.abs();
        if (ageSec <= 60 && statusStr != "OFFLINE") {
          isOnline = true;
        }
      } else if (data["is_online"] == true || statusStr == "ONLINE" || statusStr == "VALID") {
        isOnline = true;
      }
    }
    final String battery = data["battery"] != null
        ? "${data["battery"]}%"
        : "--";
    String dateStr = "--";
    String timeStr = "--";
    if (data["last_update"] != null) {
      final String raw = data["last_update"].toString().trim();
      final List<String> parts = raw.split(" ");
      if (parts.isNotEmpty) {
        dateStr = parts[0];
      }
      if (parts.length > 1) {
        timeStr = parts.sublist(1).join(" ");
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _orange, width: 2),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: _bg,
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "@$username",
                      style: const TextStyle(
                        color: _orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isOnline
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOnline
                        ? Colors.green.withOpacity(0.4)
                        : Colors.red.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline ? Colors.green : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isOnline ? "ONLINE" : "OFFLINE",
                      style: TextStyle(
                        color: isOnline ? Colors.green : Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 24, color: Colors.white10),
          // Battery Row
          Row(
            children: [
              const SizedBox(width: 6),
              Icon(
                Icons.battery_charging_full_rounded,
                color: (int.tryParse(data["battery"]?.toString() ?? "0") ?? 0) > 20
                    ? Colors.green
                    : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                "Battery Status: $battery",
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Last Update blocks side-by-side
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        color: _orange,
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Update Date",
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        color: _orange,
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Update Time",
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── LIVE TELEMETRY SECTION ──────────────────────────────────
  Widget _buildTelemetrySection(BuildContext context) {
    final double lat =
        double.tryParse(data["latitude"]?.toString() ?? "") ?? 0.0;
    final double lng =
        double.tryParse(data["longitude"]?.toString() ?? "") ?? 0.0;
    final String battery = data["battery"] != null
        ? "${data["battery"]}%"
        : "--";
    final String speed = data["speed"] != null
        ? "${data["speed"]} km/h"
        : "0 km/h";
    final String signal = data["signal_strength"]?.toString() ?? "--";
    final String mcc = data["mcc"]?.toString() ?? "--";
    final String mnc = data["mnc"]?.toString() ?? "--";
    final String lac = data["lac"]?.toString() ?? "--";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.explore_rounded, color: _orange, size: 20),
              const SizedBox(width: 8),
              const Text(
                "LIVE TELEMETRY",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MapPage(userId: widget.userId),
                  ),
                ),
                child: const Row(
                  children: [
                    Text(
                      "View Map",
                      style: TextStyle(
                        color: _orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: _orange, size: 16),
                  ],
                ),
              ),
              if (data["sim_number"] != null &&
                  data["sim_number"].toString().isNotEmpty &&
                  data["sim_number"] != "-") ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _makePhoneCall(data["sim_number"].toString()),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green.withOpacity(0.4)),
                    ),
                    child: const Icon(
                      Icons.call,
                      color: Colors.green,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Layout containing Map on left, Grid on right
          // Layout containing Location on top, Map in middle, Grid on bottom
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── LOCATION ROW (ABOVE THE MAP) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: _orange,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Current Location",
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          data["address"] ?? "Not provided",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Map preview (Taller, Full Width)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 220,
                  child: lat != 0.0 && lng != 0.0
                      ? GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(lat, lng),
                            zoom: 15,
                          ),
                          markers: {
                            Marker(
                              markerId: const MarkerId("pos"),
                              position: LatLng(lat, lng),
                              icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueOrange,
                              ),
                            ),
                          },
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: false,
                          mapToolbarEnabled: false,
                          compassEnabled: false,
                          scrollGesturesEnabled: false,
                          zoomGesturesEnabled: false,
                          onMapCreated: (_) {},
                        )
                      : Container(
                          color: Colors.black26,
                          child: Center(
                            child: Icon(
                              Icons.map_outlined,
                              color: Colors.grey.shade700,
                              size: 48,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),

              // Telemetry Grid Details (Below)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _telemetryItem(
                          "MCC",
                          mcc,
                          Icons.cell_tower_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _telemetryItem("MNC", mnc, Icons.dns_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _telemetryItem(
                          "Speed",
                          speed,
                          Icons.speed_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _telemetryItem(
                          "LAC",
                          lac,
                          Icons.pin_drop_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _telemetryItem(
                          "Signal",
                          signal,
                          Icons.signal_cellular_alt_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _telemetryItem(
                          "Battery",
                          battery,
                          Icons.battery_charging_full_rounded,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _telemetryItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _orange.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _orange, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
