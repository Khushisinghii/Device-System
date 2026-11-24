import 'package:flutter/material.dart';
import 'dart:convert';
import '../../core/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../pages/geofence/add_zone_page.dart';
import '../../widgets/app_loading_widget.dart';
import '../../widgets/app_dialogs.dart';

class GeofenceZone {
  final String id;
  String name;
  double radiusMeters;
  double lat;
  double lng;
  bool enabled;
  String iconName;
  String colorHex;

  GeofenceZone({
    required this.id,
    required this.name,
    required this.radiusMeters,
    required this.lat,
    required this.lng,
    required this.enabled,
    required this.iconName,
    required this.colorHex,
  });

  IconData get iconData {
    switch (iconName.toLowerCase()) {
      case 'home':
        return Icons.home_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'hospital':
        return Icons.local_hospital_rounded;
      case 'park':
        return Icons.park_rounded;
      case 'office':
        return Icons.work_rounded;
      case 'gym':
        return Icons.fitness_center_rounded;
      case 'shop':
        return Icons.shopping_bag_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'airport':
        return Icons.flight_takeoff_rounded;
      case 'default':
      default:
        return Icons.location_on_rounded;
    }
  }

  Color get color {
    try {
      final hex = colorHex.replaceAll("#", "");
      return Color(int.parse("FF$hex", radix: 16));
    } catch (_) {
      return const Color(0xFFFF6600); // brandOrange default
    }
  }

  String get radiusLabel {
    if (radiusMeters >= 1000) {
      return "${(radiusMeters / 1000).toStringAsFixed(0)} km";
    }
    return "${radiusMeters.toStringAsFixed(0)} m";
  }
}

class GeofencePage extends StatefulWidget {
  const GeofencePage({super.key});

  @override
  State<GeofencePage> createState() => _GeofencePageState();
}

class _GeofencePageState extends State<GeofencePage> {
  static const Color _bg = Color(0xFF0D0F11);
  static const Color _card = Color(0xFF1A1D21);
  static const Color _orange = Color(0xFFFF6600);

  final String _baseUrl =
      "https://ireland-calculations-chair-unfortunately.trycloudflare.com";
  List<GeofenceZone> _zones = [];
  bool _loading = true;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserAndData();
  }

  Future<void> _loadUserAndData() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt("userId") ?? 0;
    await _loadGeofences();
  }

  Future<void> _loadGeofences() async {
    if (_userId == null) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService.get(
        Uri.parse("$_baseUrl/geofences/$_userId"),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json["status"] == true) {
          final List list = json["geofences"] ?? [];
          setState(() {
            _zones = list.map((item) {
              return GeofenceZone(
                id: item["id"].toString(),
                name: item["name"] ?? "Zone",
                radiusMeters:
                    double.tryParse(item["radius_meters"].toString()) ?? 200.0,
                lat: double.tryParse(item["latitude"].toString()) ?? 0.0,
                lng: double.tryParse(item["longitude"].toString()) ?? 0.0,
                enabled: (item["enabled"] == 1 || item["enabled"] == true),
                iconName: item["icon"]?.toString() ?? "home",
                colorHex: item["color"]?.toString() ?? "#FF6600",
              );
            }).toList();
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _toggleGeofence(GeofenceZone zone, bool val) async {
    setState(() {
      zone.enabled = val;
    });
    try {
      await ApiService.put(
        Uri.parse("$_baseUrl/geofences/${zone.id}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"enabled": val ? 1 : 0}),
      );
    } catch (_) {}
  }

  Future<void> _deleteGeofence(String id) async {
    try {
      final res = await ApiService.delete(Uri.parse("$_baseUrl/geofences/$id"));
      if (res.statusCode == 200) {
        _loadGeofences();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          "Geofence",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_rounded, color: _orange, size: 20),
            ),
            onPressed: _openAddZone,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const AppLoadingWidget()
          : Column(
              children: [
                Expanded(
                  child: _zones.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: _zones.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _zoneTile(_zones[i]),
                        ),
                ),
                // Bottom info banner
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: _orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _orange.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: _orange,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "You will be notified when your device enters or leaves these zones.",
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                            height: 1.5,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fence_rounded, size: 64, color: Colors.grey.shade700),
          const SizedBox(height: 16),
          Text(
            "No Geofence Zones",
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Tap + to add a zone",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _zoneTile(GeofenceZone zone) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: zone.enabled
              ? zone.color.withOpacity(0.25)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: zone.enabled
                ? zone.color.withOpacity(0.15)
                : Colors.white.withOpacity(0.06),
          ),
          child: Icon(
            zone.iconData,
            color: zone.enabled ? zone.color : Colors.grey.shade600,
            size: 22,
          ),
        ),
        title: Text(
          zone.name,
          style: TextStyle(
            color: zone.enabled ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "Radius ${zone.radiusLabel}",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Edit button
            GestureDetector(
              onTap: () => _openEditZone(zone),
              child: Container(
                padding: const EdgeInsets.all(6),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.edit_rounded,
                  color: Colors.grey.shade500,
                  size: 16,
                ),
              ),
            ),
            // Toggle
            Switch(
              value: zone.enabled,
              onChanged: (v) => _toggleGeofence(zone, v),
              activeColor: zone.color,
              inactiveThumbColor: Colors.grey.shade700,
              inactiveTrackColor: Colors.white12,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        onLongPress: () => _confirmDelete(zone),
      ),
    );
  }

  Future<void> _openAddZone() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddZonePage()),
    );
    if (result == true) {
      _loadGeofences();
    }
  }

  Future<void> _openEditZone(GeofenceZone zone) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddZonePage(editZone: zone)),
    );
    if (result == true) {
      _loadGeofences();
    }
  }

  void _confirmDelete(GeofenceZone zone) async {
    final confirm = await AppDialogs.showConfirm(
      context,
      title: "Delete Zone",
      message:
          "Are you sure you want to permanently delete \"${zone.name}\"? This action cannot be undone.",
      confirmText: "Delete",
      cancelText: "Cancel",
      isDeleteAction: true,
    );
    if (confirm == true) {
      _deleteGeofence(zone.id);
    }
  }
}
