import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/notification_helper.dart';
import '../../widgets/app_loading_widget.dart';

class MapPage extends StatefulWidget {
  final int userId;

  const MapPage({super.key, required this.userId});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin {
  // --- Brand colors ---
  final Color brandOrange = const Color(0xFFFF6600);
  final Color deepDark = const Color(0xFF111111);
  final Color panelBg = const Color(0xF2FFFFFF);

  final String baseUrl =
      "https://galleries-symphony-euros-addressing.trycloudflare.com";

  // --- Map state ---
  GoogleMapController? mapController;
  BitmapDescriptor? trackerIcon;
  MapType _mapType = MapType.normal;
  bool _isProgrammaticMovement = false;

  // --- Data state ---
  Timer? timer;
  Map<String, dynamic> data = {};
  bool loading = true;
  bool hasError = false;

  // --- Tracking state ---
  Set<Marker> markers = {};
  List<LatLng> routePoints = [];
  List<double> speedHistory = [];
  bool followMode = true;
  bool panelExpanded = true;
  double totalDistanceMeters = 0;
  LatLng? _previousPosition;
  double _currentBearing = 0;
  bool loadingRoute = false;

  // ============================================================
  //  GEOFENCE STATE
  // ============================================================

  LatLng? _geofenceCenter;
  double _geofenceRadiusKm = 5.0; // default 5 km
  bool _geofenceActive = false;
  List<MapGeofence> _dbGeofences = [];
  Map<String, BitmapDescriptor> _geofenceMarkerIcons = {};
  bool? _wasInsideGeofence;
  bool _pickingGeofenceFromMap = false;

  // In-app notification overlay
  OverlayEntry? _notificationOverlay;
  AnimationController? _notifAnimController;

  // ============================================================
  //  LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    loadMarker();
    loadLocation();
    _loadTodayRoute();
    _loadDbGeofences();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      loadLocation();
      _loadDbGeofences();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    _notifAnimController?.dispose();
    _removeNotification();
    super.dispose();
  }

  // ============================================================
  //  DATA LOADING
  // ============================================================

  Future<void> loadLocation() async {
    try {
      final response = await ApiService.get(
        Uri.parse("$baseUrl/user_dashboard/${widget.userId}"),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json["status"] == true && json["data"] != null) {
          final latVal = double.tryParse(
            json["data"]["latitude"]?.toString() ?? "",
          );
          final lngVal = double.tryParse(
            json["data"]["longitude"]?.toString() ?? "",
          );

          if (latVal != null && lngVal != null) {
            final newPosition = LatLng(latVal, lngVal);
            if (!mounted) return;

            // Calculate bearing between previous and current position
            if (_previousPosition != null) {
              _currentBearing = _calculateBearing(
                _previousPosition!,
                newPosition,
              );
              final dist = _calculateDistance(_previousPosition!, newPosition);
              totalDistanceMeters += dist;
            }

            final currentSpeed =
                double.tryParse(json["data"]["speed"]?.toString() ?? "0") ?? 0;
            speedHistory.add(currentSpeed);

            // GPS Drift filter: Lock marker position when stationary to prevent building drift
            LatLng finalPosition = newPosition;
            if (_previousPosition != null && currentSpeed <= 1.0) {
              final driftDist = _calculateDistance(
                _previousPosition!,
                newPosition,
              );
              if (driftDist < 10.0) {
                finalPosition = _previousPosition!;
              }
            }

            setState(() {
              data = json["data"];
              loading = false;
              hasError = false;

              // Add to route if position actually changed
              if (routePoints.isEmpty ||
                  _positionChanged(routePoints.last, finalPosition)) {
                routePoints.add(finalPosition);
              }

              _previousPosition = finalPosition;

              markers = {
                Marker(
                  markerId: const MarkerId("tracker"),
                  position: finalPosition,
                  rotation: _currentBearing,
                  anchor: const Offset(0.5, 0.5),
                  icon:
                      trackerIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueOrange,
                      ),
                  infoWindow: InfoWindow(
                    title: data["name"] ?? "Tracker",
                    snippet: "Speed: ${currentSpeed.toStringAsFixed(1)} km/h",
                  ),
                ),
                // Geofence center marker
                if (_geofenceActive && _geofenceCenter != null)
                  Marker(
                    markerId: const MarkerId("geofence_center"),
                    position: _geofenceCenter!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure,
                    ),
                    infoWindow: InfoWindow(
                      title: "📍 Geofence Center",
                      snippet:
                          "Radius: ${_geofenceRadiusKm.toStringAsFixed(0)} km",
                    ),
                    anchor: const Offset(0.5, 1.0),
                  ),
              };
            });

            // ---- GEOFENCE CHECK ----
            if (_geofenceActive && _geofenceCenter != null) {
              _checkGeofence(newPosition);
            }

            // Smooth camera follow
            if (followMode && mapController != null) {
              _isProgrammaticMovement = true;
              mapController!.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: newPosition, zoom: 16),
                ),
              );
            }
            return;
          } else {
            // Lat/Lng is null but database data is present (could be offline tracker with last values null/old)
            if (data.isEmpty && json["data"] != null) {
              setState(() {
                data = json["data"];
                loading = false;
                hasError = false;
              });
            }
          }
        }
      }
      // If we reach here, something didn't parse right
      if (data.isEmpty) {
        setState(() {
          loading = false;
          hasError = true;
        });
      }
    } catch (e) {
      debugPrint("MapPage loadLocation error: $e");
      if (!mounted) return;
      if (data.isEmpty) {
        setState(() {
          loading = false;
          hasError = true;
        });
      }
    }
  }

  Future<void> loadMarker() async {
    try {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      const double size = 140.0;

      // 1. Draw outer neon orange pulse aura (glow)
      final Paint glowPaint = Paint()
        ..color = brandOrange.withOpacity(0.18)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, glowPaint);

      // 2. Draw outer orange background card ring
      final Paint outerRingPaint = Paint()
        ..color = brandOrange
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        const Offset(size / 2, size / 2),
        size / 2.8,
        outerRingPaint,
      );

      // 3. Draw inner white solid card circle
      final Paint innerCirclePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        const Offset(size / 2, size / 2),
        size / 3.4,
        innerCirclePaint,
      );

      // 4. Paint beautiful walking person vector icon in the center
      TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
      textPainter.text = TextSpan(
        text: String.fromCharCode(Icons.directions_walk_rounded.codePoint),
        style: TextStyle(
          fontSize: 46.0,
          fontFamily: Icons.directions_walk_rounded.fontFamily,
          package: Icons.directions_walk_rounded.fontPackage,
          color: brandOrange,
        ),
      );
      textPainter.layout();

      final double offsetLeft = (size - textPainter.width) / 2;
      final double offsetTop = (size - textPainter.height) / 2;
      textPainter.paint(canvas, Offset(offsetLeft, offsetTop));

      final ui.Picture picture = recorder.endRecording();
      final ui.Image img = await picture.toImage(size.toInt(), size.toInt());
      final ByteData? byteData = await img.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        trackerIcon = BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint("Could not build custom canvas marker: $e");
    }
  }

  // ============================================================
  //  GEOFENCE LOGIC
  // ============================================================

  void _checkGeofence(LatLng currentPosition) {
    if (_geofenceCenter == null) return;

    final distanceMeters = _calculateDistance(
      _geofenceCenter!,
      currentPosition,
    );
    final distanceKm = distanceMeters / 1000.0;
    final isInsideNow = distanceKm <= _geofenceRadiusKm;

    // First check — just record state without alerting
    if (_wasInsideGeofence == null) {
      _wasInsideGeofence = isInsideNow;
      return;
    }

    // Detect boundary crossing
    if (_wasInsideGeofence! && !isInsideNow) {
      // Was inside, now outside → EXITED
      _showGeofenceNotification(
        message: "⚠️  Tracker EXITED the zone!",
        subMessage: "Distance from center: ${distanceKm.toStringAsFixed(2)} km",
        isExit: true,
      );
    } else if (!_wasInsideGeofence! && isInsideNow) {
      // Was outside, now inside → ENTERED
      _showGeofenceNotification(
        message: "✅  Tracker ENTERED the zone!",
        subMessage: "Distance from center: ${distanceKm.toStringAsFixed(2)} km",
        isExit: false,
      );
    }

    _wasInsideGeofence = isInsideNow;
  }

  void _activateGeofence(LatLng center, double radiusKm) {
    setState(() {
      _geofenceCenter = center;
      _geofenceRadiusKm = radiusKm;
      _geofenceActive = true;
      _wasInsideGeofence = null; // reset state so first check doesn't alert
      _pickingGeofenceFromMap = false;

      // Immediately add geofence marker
      markers = {
        ...markers,
        Marker(
          markerId: const MarkerId("geofence_center"),
          position: center,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: "📍 Geofence Center",
            snippet: "Radius: ${radiusKm.toStringAsFixed(0)} km",
          ),
          anchor: const Offset(0.5, 1.0),
        ),
      };
    });

    // Zoom out to show the full geofence circle
    mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(center, _zoomForRadius(radiusKm)),
    );
  }

  void _clearGeofence() {
    setState(() {
      _geofenceActive = false;
      _geofenceCenter = null;
      _wasInsideGeofence = null;
      _pickingGeofenceFromMap = false;
      markers = markers
          .where((m) => m.markerId.value != "geofence_center")
          .toSet();
    });
    _removeNotification();
  }

  double _zoomForRadius(double radiusKm) {
    if (radiusKm <= 1) return 14.5;
    if (radiusKm <= 5) return 12.0;
    return 10.5;
  }

  Set<Circle> _buildGeofenceCircles() {
    final Set<Circle> result = {};

    if (_geofenceActive && _geofenceCenter != null) {
      result.add(
        Circle(
          circleId: const CircleId("geofence_glow"),
          center: _geofenceCenter!,
          radius: _geofenceRadiusKm * 1000 * 1.05,
          strokeColor: brandOrange.withOpacity(0.2),
          strokeWidth: 8,
          fillColor: Colors.transparent,
        ),
      );
      result.add(
        Circle(
          circleId: const CircleId("geofence_boundary"),
          center: _geofenceCenter!,
          radius: _geofenceRadiusKm * 1000,
          strokeColor: brandOrange.withOpacity(0.85),
          strokeWidth: 3,
          fillColor: brandOrange.withOpacity(0.08),
        ),
      );
    }

    for (int i = 0; i < _dbGeofences.length; i++) {
      final zone = _dbGeofences[i];
      if (!zone.enabled) continue;

      result.add(
        Circle(
          circleId: CircleId("db_geofence_glow_$i"),
          center: LatLng(zone.lat, zone.lng),
          radius: zone.radiusMeters * 1.05,
          strokeColor: zone.color.withOpacity(0.15),
          strokeWidth: 6,
          fillColor: Colors.transparent,
        ),
      );
      result.add(
        Circle(
          circleId: CircleId("db_geofence_boundary_$i"),
          center: LatLng(zone.lat, zone.lng),
          radius: zone.radiusMeters,
          strokeColor: zone.color.withOpacity(0.7),
          strokeWidth: 2,
          fillColor: zone.color.withOpacity(0.05),
        ),
      );
    }

    return result;
  }

  // ============================================================
  //  IN-APP NOTIFICATION BANNER
  // ============================================================

  void _showGeofenceNotification({
    required String message,
    required String subMessage,
    required bool isExit,
  }) {
    NotificationHelper.showNotification(message, subMessage);
    _removeNotification(); // remove any existing one first

    _notifAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    final slideAnim =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(parent: _notifAnimController!, curve: Curves.easeOut),
        );

    _notificationOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        child: SlideTransition(
          position: slideAnim,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isExit
                    ? const Color(0xFFB71C1C)
                    : const Color(0xFF1B5E20),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: (isExit ? Colors.red : Colors.green).withOpacity(
                      0.45,
                    ),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isExit
                          ? Icons.directions_run_rounded
                          : Icons.location_on_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subMessage,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _removeNotification,
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_notificationOverlay!);
    _notifAnimController!.forward();

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (_notifAnimController != null && _notifAnimController!.isCompleted) {
        _notifAnimController!.reverse().then((_) => _removeNotification());
      }
    });
  }

  void _removeNotification() {
    _notificationOverlay?.remove();
    _notificationOverlay = null;
  }

  // ============================================================
  //  GEOFENCE SETUP BOTTOM SHEET
  // ============================================================

  void _showGeofenceSheet() {
    double selectedRadius = _geofenceRadiusKm;
    LatLng? pickedCenter = _geofenceCenter;
    bool tappingMap = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            decoration: BoxDecoration(
              color: deepDark,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: brandOrange.withOpacity(0.15),
                  blurRadius: 30,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

                // Title row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: brandOrange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.fence_rounded,
                        color: brandOrange,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Geofence Zone",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Set a boundary & get alerts on crossing",
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // --- CENTER LOCATION SECTION ---
                _sheetLabel("📍  Center Location"),
                const SizedBox(height: 10),

                // Status indicator
                if (pickedCenter != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.green,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Lat: ${pickedCenter!.latitude.toStringAsFixed(5)},  Lng: ${pickedCenter!.longitude.toStringAsFixed(5)}",
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setSheet(() => pickedCenter = null),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.green,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (pickedCenter == null) ...[
                  // Use current tracker position
                  _sheetOptionButton(
                    icon: Icons.my_location_rounded,
                    label: "Use Tracker's Current Position",
                    onTap: () {
                      if (routePoints.isNotEmpty) {
                        setSheet(() => pickedCenter = routePoints.last);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  // Tap map
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _pickingGeofenceFromMap = true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            "Tap anywhere on the map to set center",
                          ),
                          backgroundColor: brandOrange,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: brandOrange.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            color: brandOrange,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Tap Map to Pick Location",
                            style: TextStyle(
                              color: brandOrange,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // --- RADIUS SECTION ---
                _sheetLabel("📏  Zone Radius"),
                const SizedBox(height: 12),

                Row(
                  children: [1.0, 5.0, 10.0].map((km) {
                    final bool selected = selectedRadius == km;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setSheet(() => selectedRadius = km),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: selected
                                ? brandOrange
                                : Colors.white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? brandOrange
                                  : Colors.white.withOpacity(0.15),
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: brandOrange.withOpacity(0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Column(
                            children: [
                              Text(
                                "${km.toStringAsFixed(0)}",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                "km",
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white70
                                      : Colors.grey.shade500,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 28),

                // --- ACTION BUTTONS ---
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pickedCenter != null
                          ? brandOrange
                          : Colors.grey.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: pickedCenter == null
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _activateGeofence(pickedCenter!, selectedRadius);
                          },
                    icon: const Icon(Icons.shield_rounded, color: Colors.white),
                    label: const Text(
                      "ACTIVATE ZONE",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),

                if (_geofenceActive) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        foregroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _clearGeofence();
                      },
                      icon: const Icon(Icons.cancel_rounded, size: 18),
                      label: const Text(
                        "CLEAR ZONE",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sheetLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _sheetOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: brandOrange, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  //  CALCULATIONS
  // ============================================================

  bool _positionChanged(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() > 0.000005 ||
        (a.longitude - b.longitude).abs() > 0.000005;
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final dLng = _toRadians(end.longitude - start.longitude);
    final sLat = _toRadians(start.latitude);
    final eLat = _toRadians(end.latitude);
    final x = cos(eLat) * sin(dLng);
    final y = cos(sLat) * sin(eLat) - sin(sLat) * cos(eLat) * cos(dLng);
    return (_toDegrees(atan2(x, y)) + 360) % 360;
  }

  double _calculateDistance(LatLng a, LatLng b) {
    const R = 6371000.0; // Earth radius meters
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final x =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(a.latitude)) *
            cos(_toRadians(b.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(x), sqrt(1 - x));
  }

  double _toRadians(double deg) => deg * pi / 180;
  double _toDegrees(double rad) => rad * 180 / pi;

  String _formatDistance(double meters) {
    if (meters < 1000) return "${meters.toStringAsFixed(0)} m";
    return "${(meters / 1000).toStringAsFixed(2)} km";
  }

  // ============================================================
  //  ACTIONS
  // ============================================================

  Future<void> openMap() async {
    final double? lat = double.tryParse(data["latitude"]?.toString() ?? "");
    final double? lng = double.tryParse(data["longitude"]?.toString() ?? "");
    if (lat == null || lng == null) return;
    final url = Uri.parse(
      "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  /// Reload today's complete route from the history API
  Future<void> _loadTodayRoute() async {
    setState(() => loadingRoute = true);
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final response = await ApiService.get(
        Uri.parse("$baseUrl/location_history/${widget.userId}?date=$today"),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List history = json["history"] ?? [];

        if (!mounted) return;

        setState(() {
          routePoints.clear();
          speedHistory.clear();
          totalDistanceMeters = 0;
          _previousPosition = null;

          for (int i = 0; i < history.length; i++) {
            final double? lat = double.tryParse(
              history[i]["latitude"]?.toString() ?? "",
            );
            final double? lng = double.tryParse(
              history[i]["longitude"]?.toString() ?? "",
            );
            final double spd =
                double.tryParse(history[i]["speed"]?.toString() ?? "0") ?? 0;

            if (lat != null && lng != null) {
              final point = LatLng(lat, lng);
              if (_previousPosition != null) {
                totalDistanceMeters += _calculateDistance(
                  _previousPosition!,
                  point,
                );
              }
              routePoints.add(point);
              speedHistory.add(spd);
              _previousPosition = point;
            }
          }
          loadingRoute = false;
        });

        // Fit camera to show entire route
        if (routePoints.length >= 2 && mapController != null) {
          final bounds = _boundsFromPoints(routePoints);
          mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 60),
          );
        }
      }
    } catch (e) {
      debugPrint("Error loading today route: $e");
      if (!mounted) return;
      setState(() => loadingRoute = false);
    }
  }

  LatLngBounds _boundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _cycleMapType() {
    setState(() {
      if (_mapType == MapType.normal) {
        _mapType = MapType.satellite;
      } else if (_mapType == MapType.satellite) {
        _mapType = MapType.terrain;
      } else {
        _mapType = MapType.normal;
      }
    });
  }

  // ============================================================
  //  POLYLINES — Speed-colored segments
  // ============================================================

  Set<Polyline> _buildPolylines() {
    return const {};
  }

  // ============================================================
  //  BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: AppLoadingWidget());
    }

    if (hasError || data.isEmpty) {
      return _buildErrorView();
    }

    return Scaffold(
      body: Stack(
        children: [
          // --- MAP ---
          _buildMap(),

          // --- TOP STATUS BAR ---
          _buildTopBar(),

          // --- MAP CONTROLS (right side) ---
          _buildMapControls(),

          // --- BOTTOM TELEMETRY PANEL ---
          _buildBottomPanel(),

          // --- GEOFENCE ACTIVE INDICATOR ---
          if (_geofenceActive) _buildGeofenceStatusBar(),

          // --- MAP TAP PICKING HINT ---
          if (_pickingGeofenceFromMap) _buildPickingHint(),
        ],
      ),
    );
  }

  // ============================================================
  //  GEOFENCE STATUS BAR (when zone is active)
  // ============================================================

  Widget _buildGeofenceStatusBar() {
    final bool? inside = _wasInsideGeofence;
    final Color statusColor = inside == null
        ? Colors.blue
        : inside
        ? Colors.green
        : Colors.red;
    final String statusText = inside == null
        ? "Checking…"
        : inside
        ? "Inside Zone"
        : "Outside Zone";
    final IconData statusIcon = inside == null
        ? Icons.radar_rounded
        : inside
        ? Icons.check_circle_rounded
        : Icons.warning_rounded;

    return Positioned(
      bottom: panelExpanded ? 260 : 130,
      left: 12,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.92),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              "Zone: $statusText  •  ${_geofenceRadiusKm.toStringAsFixed(0)} km",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- MAP PICKING HINT ---
  Widget _buildPickingHint() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 80,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: brandOrange,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: brandOrange.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.touch_app_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                "Tap anywhere on the map to set the geofence center",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _pickingGeofenceFromMap = false),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white70,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  //  ERROR VIEW
  // ============================================================

  Widget _buildErrorView() {
    return Scaffold(
      backgroundColor: deepDark,
      appBar: AppBar(
        backgroundColor: deepDark,
        elevation: 0,
        title: const Text(
          "Live Tracking",
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.gps_off_rounded,
                size: 80,
                color: brandOrange.withOpacity(0.6),
              ),
              const SizedBox(height: 20),
              const Text(
                "No GPS Signal",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Waiting for location data from the device.\nThe tracker may be offline or initializing.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade400,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandOrange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    setState(() => loading = true);
                    loadLocation();
                  },
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  label: const Text(
                    "Retry Connection",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  //  MAP WIDGET
  // ============================================================

  Widget _buildMap() {
    final double lat =
        double.tryParse(data["latitude"]?.toString() ?? "") ?? 0.0;
    final double lng =
        double.tryParse(data["longitude"]?.toString() ?? "") ?? 0.0;

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: LatLng(lat, lng), zoom: 16),
      mapType: _mapType,
      markers: _buildMarkers(),
      polylines: _buildPolylines(),
      circles: _buildGeofenceCircles(),
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: (controller) {
        mapController = controller;
      },
      onTap: (LatLng tappedPoint) {
        if (_pickingGeofenceFromMap) {
          setState(() {
            _pickingGeofenceFromMap = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showGeofenceSheetWithCenter(tappedPoint);
          });
          return;
        }
        if (followMode) {
          setState(() => followMode = false);
        }
      },
      onCameraMove: (_) {
        if (!_isProgrammaticMovement && followMode) {
          setState(() => followMode = false);
        }
      },
      onCameraIdle: () {
        _isProgrammaticMovement = false;
      },
    );
  }

  /// Opens the geofence sheet with a pre-selected center (from map tap)
  void _showGeofenceSheetWithCenter(LatLng preselectedCenter) {
    double selectedRadius = _geofenceRadiusKm;
    LatLng? pickedCenter = preselectedCenter;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            decoration: BoxDecoration(
              color: deepDark,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: brandOrange.withOpacity(0.15),
                  blurRadius: 30,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: brandOrange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.fence_rounded,
                        color: brandOrange,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Geofence Zone",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Location picked from map",
                          style: TextStyle(
                            color: Colors.green.shade400,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Lat: ${pickedCenter!.latitude.toStringAsFixed(5)},  Lng: ${pickedCenter!.longitude.toStringAsFixed(5)}",
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sheetLabel("📏  Zone Radius"),
                const SizedBox(height: 12),
                Row(
                  children: [1.0, 5.0, 10.0].map((km) {
                    final bool selected = selectedRadius == km;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setSheet(() => selectedRadius = km),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: selected
                                ? brandOrange
                                : Colors.white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? brandOrange
                                  : Colors.white.withOpacity(0.15),
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: brandOrange.withOpacity(0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Column(
                            children: [
                              Text(
                                "${km.toStringAsFixed(0)}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                "km",
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white70
                                      : Colors.grey.shade500,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandOrange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _activateGeofence(pickedCenter!, selectedRadius);
                    },
                    icon: const Icon(Icons.shield_rounded, color: Colors.white),
                    label: const Text(
                      "ACTIVATE ZONE",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                if (_geofenceActive) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        foregroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _clearGeofence();
                      },
                      icon: const Icon(Icons.cancel_rounded, size: 18),
                      label: const Text(
                        "CLEAR ZONE",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  //  TOP STATUS BAR
  // ============================================================

  Widget _buildTopBar() {
    final String name = data["name"] ?? "Tracker";
    final String status = (data["status"] ?? "OFFLINE")
        .toString()
        .toUpperCase();
    final bool isOnline = status == "ONLINE";

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: deepDark.withOpacity(0.92),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Status dot + name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: isOnline
                                  ? Colors.greenAccent.withOpacity(0.5)
                                  : Colors.redAccent.withOpacity(0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "$status • ${routePoints.length} points",
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                  ),
                ],
              ),
            ),
            // Last update time
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: brandOrange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: brandOrange.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time_rounded, color: brandOrange, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    data["last_update"] ?? "-",
                    style: TextStyle(
                      color: brandOrange,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  //  MAP CONTROLS (right side floating buttons)
  // ============================================================

  Widget _buildMapControls() {
    String mapLabel;
    IconData mapIcon;
    switch (_mapType) {
      case MapType.satellite:
        mapLabel = "SAT";
        mapIcon = Icons.satellite_alt_rounded;
        break;
      case MapType.terrain:
        mapLabel = "TER";
        mapIcon = Icons.terrain_rounded;
        break;
      default:
        mapLabel = "MAP";
        mapIcon = Icons.map_rounded;
    }

    return Positioned(
      right: 12,
      top: MediaQuery.of(context).padding.top + 90,
      child: Column(
        children: [
          // Map type toggle
          _controlButton(icon: mapIcon, label: mapLabel, onTap: _cycleMapType),
          const SizedBox(height: 10),
          // Open in Google Maps
          _controlButton(
            icon: Icons.open_in_new_rounded,
            label: "OPEN",
            onTap: openMap,
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    Color? activeColor,
  }) {
    final Color btnColor = active
        ? (activeColor ?? brandOrange)
        : deepDark.withOpacity(0.88);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: btnColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: active
                  ? (activeColor ?? brandOrange).withOpacity(0.4)
                  : Colors.black.withOpacity(0.25),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  //  BOTTOM TELEMETRY PANEL
  // ============================================================

  Widget _buildBottomPanel() {
    final String battery = data["battery"] != null
        ? "${data["battery"]}%"
        : "-";
    final String signal = data["signal_strength"]?.toString() ?? "-";
    final String currentSpeed = data["speed"] != null
        ? "${data["speed"]} km/h"
        : "0 km/h";

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: deepDark.withOpacity(0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 30,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            // Location Address Row
            if (data["address"] != null &&
                data["address"].toString().isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: brandOrange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data["address"],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                color: Colors.white10,
                height: 20,
                indent: 20,
                endIndent: 20,
              ),
            ],
            // Stats row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sessionStat(Icons.speed_rounded, "Speed", currentSpeed),
                  _sessionStat(
                    Icons.straighten_rounded,
                    "Distance",
                    _formatDistance(totalDistanceMeters),
                  ),
                  _sessionStat(
                    Icons.battery_charging_full_rounded,
                    "Battery",
                    battery,
                  ),
                  _sessionStat(
                    Icons.signal_cellular_alt_rounded,
                    "Signal",
                    signal,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sessionStat(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: brandOrange, size: 16),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 9)),
      ],
    );
  }

  Future<void> _loadDbGeofences() async {
    try {
      final res = await ApiService.get(
        Uri.parse("$baseUrl/geofences/${widget.userId}"),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json["status"] == true) {
          final List list = json["geofences"] ?? [];
          final parsed = list.map((item) {
            final colorHex = item["color"]?.toString() ?? "#FF6600";
            Color parsedColor;
            try {
              final hex = colorHex.replaceAll("#", "");
              parsedColor = Color(int.parse("FF$hex", radix: 16));
            } catch (_) {
              parsedColor = const Color(0xFFFF6600);
            }
            return MapGeofence(
              name: item["name"] ?? "Zone",
              lat: double.tryParse(item["latitude"].toString()) ?? 0.0,
              lng: double.tryParse(item["longitude"].toString()) ?? 0.0,
              radiusMeters:
                  double.tryParse(item["radius_meters"].toString()) ?? 200.0,
              color: parsedColor,
              colorHex: colorHex,
              icon: item["icon"]?.toString() ?? "location",
              enabled: (item["enabled"] == 1 || item["enabled"] == true),
            );
          }).toList();

          if (mounted) {
            setState(() {
              _dbGeofences = parsed;
            });
            _generateGeofenceMarkerIcons();
          }
        }
      }
    } catch (_) {}
  }

  Set<Marker> _buildMarkers() {
    final Set<Marker> result = {};

    final tracker = markers.firstWhere(
      (m) => m.markerId.value == "tracker",
      orElse: () => const Marker(markerId: MarkerId("none")),
    );
    if (tracker.markerId.value != "none") {
      result.add(tracker);
    }

    final tempGeofence = markers.firstWhere(
      (m) => m.markerId.value == "geofence_center",
      orElse: () => const Marker(markerId: MarkerId("none")),
    );
    if (tempGeofence.markerId.value != "none") {
      result.add(tempGeofence);
    }

    for (int i = 0; i < _dbGeofences.length; i++) {
      final zone = _dbGeofences[i];
      if (!zone.enabled) continue;

      final String key = "${zone.name}_${zone.colorHex}_${zone.icon}";
      final customIcon = _geofenceMarkerIcons[key];

      result.add(
        Marker(
          markerId: MarkerId("db_geofence_$i"),
          position: LatLng(zone.lat, zone.lng),
          icon:
              customIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                _getMarkerHue(zone.colorHex),
              ),
          infoWindow: InfoWindow(
            title: zone.name,
            snippet: "Radius: ${zone.radiusMeters.toStringAsFixed(0)} m",
          ),
          anchor: const Offset(0.5, 1.0),
        ),
      );
    }

    return result;
  }

  Future<void> _generateGeofenceMarkerIcons() async {
    bool updated = false;
    for (var gf in _dbGeofences) {
      final String key = "${gf.name}_${gf.colorHex}_${gf.icon}";
      if (!_geofenceMarkerIcons.containsKey(key)) {
        final icon = await _getGeofenceMarkerBitmap(gf.name, gf.icon, gf.color);
        _geofenceMarkerIcons[key] = icon;
        updated = true;
      }
    }
    if (updated && mounted) {
      setState(() {});
    }
  }

  Future<BitmapDescriptor> _getGeofenceMarkerBitmap(
    String name,
    String iconName,
    Color color,
  ) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    const double width = 150.0;
    const double height = 150.0;

    final Paint paint = Paint()..color = color;
    final Paint shadowPaint = Paint()..color = Colors.black26;

    canvas.drawCircle(
      const Offset(width / 2, height / 2 - 15),
      32,
      shadowPaint,
    );
    canvas.drawCircle(const Offset(width / 2, height / 2 - 15), 30, paint);

    final Paint whitePaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(width / 2, height / 2 - 15), 24, whitePaint);

    final Path path = Path();
    path.moveTo(width / 2 - 12, height / 2 + 5);
    path.lineTo(width / 2 + 12, height / 2 + 5);
    path.lineTo(width / 2, height / 2 + 25);
    path.close();
    canvas.drawPath(path, paint);

    IconData iconData = Icons.location_on;
    switch (iconName.toLowerCase()) {
      case 'school':
        iconData = Icons.school;
        break;
      case 'hospital':
        iconData = Icons.local_hospital;
        break;
      case 'park':
        iconData = Icons.park;
        break;
      case 'office':
        iconData = Icons.business;
        break;
      case 'home':
        iconData = Icons.home;
        break;
      case 'gym':
        iconData = Icons.fitness_center;
        break;
      case 'shop':
        iconData = Icons.shopping_bag;
        break;
      case 'restaurant':
        iconData = Icons.restaurant;
        break;
      case 'airport':
        iconData = Icons.local_airport;
        break;
      case 'hotel':
        iconData = Icons.hotel;
        break;
    }

    final TextPainter iconPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );
    iconPainter.text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontSize: 28.0,
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        color: color,
      ),
    );
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      Offset(
        (width - iconPainter.width) / 2,
        (height - iconPainter.height) / 2 - 17,
      ),
    );

    final TextPainter textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    textPainter.text = TextSpan(
      text: name,
      style: const TextStyle(
        fontSize: 14.0,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
    textPainter.layout(maxWidth: width - 10);

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        (width - textPainter.width) / 2 - 6,
        height / 2 + 30,
        textPainter.width + 12,
        textPainter.height + 6,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF1E2125));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    textPainter.paint(
      canvas,
      Offset((width - textPainter.width) / 2, height / 2 + 33),
    );

    final img = await pictureRecorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  double _getMarkerHue(String colorHex) {
    final hex = colorHex.toUpperCase().replaceAll("#", "");
    switch (hex) {
      case '4CAF50': // Green
      case '009688': // Teal
        return BitmapDescriptor.hueGreen;
      case '2196F3': // Blue
        return BitmapDescriptor.hueBlue;
      case '9C27B0': // Purple
        return BitmapDescriptor.hueViolet;
      case '00BCD4': // Cyan
        return BitmapDescriptor.hueCyan;
      case 'FFB300': // Amber
        return BitmapDescriptor.hueYellow;
      case 'E91E63': // Pink
        return BitmapDescriptor.hueRose;
      case 'EF5350': // Red
        return BitmapDescriptor.hueRed;
      case 'FF6600': // Orange
      default:
        return BitmapDescriptor.hueOrange;
    }
  }
}

class MapGeofence {
  final String name;
  final double lat;
  final double lng;
  final double radiusMeters;
  final Color color;
  final String colorHex;
  final String icon;
  final bool enabled;

  MapGeofence({
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.color,
    required this.colorHex,
    required this.icon,
    required this.enabled,
  });
}
