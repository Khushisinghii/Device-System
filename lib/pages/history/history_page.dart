import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/services/api_service.dart';
import 'package:intl/intl.dart';
import '../../widgets/app_loading_widget.dart';

class HistoryPage extends StatefulWidget {
  final int userId;
  const HistoryPage({super.key, required this.userId});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const Color _bg = Color(0xFF0D0F11);
  static const Color _card = Color(0xFF1A1D21);
  static const Color _orange = Color(0xFFFF6600);

  final String baseUrl =
      "https://galleries-symphony-euros-addressing.trycloudflare.com";

  DateTime selectedDate = DateTime.now();
  bool loading = true;
  bool hasError = false;

  List<dynamic> history = [];
  List<Map<String, dynamic>> detectedStops = [];
  List<dynamic> userGeofences = [];
  Map<String, dynamic>? startData;
  Map<String, dynamic>? endData;

  List<dynamic> _fullHistory = [];
  List<Map<String, dynamic>> _fullDetectedStops = [];
  List<LatLng> _fullSnappedRoute = [];
  RangeValues _timeRange = const RangeValues(0, 24);
  bool _showFilters = true;
  bool _isMapView = true; // Added state for view toggle

  double totalDistanceMeters = 0;

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  List<List<LatLng>> _snappedSegments = [];
  Map<String, BitmapDescriptor> _geofenceMarkerIcons = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String get _formattedDate => DateFormat("d MMM yyyy").format(selectedDate);

  DateTime? _parseGpsDateTime(String? raw) {
    if (raw == null) return null;
    try {
      if (raw.contains("-")) {
        final cleanRaw = raw.replaceAll(RegExp(r'[a-zA-Z]'), '').trim();
        final parts = cleanRaw.split(" ");
        final dateParts = parts[0].split("-");
        final timeParts = parts[1].split(":");

        int day, month, year;
        if (dateParts[0].length == 4) {
          year = int.parse(dateParts[0]);
          month = int.parse(dateParts[1]);
          day = int.parse(dateParts[2]);
        } else {
          day = int.parse(dateParts[0]);
          month = int.parse(dateParts[1]);
          year = int.parse(dateParts[2]);
        }

        int hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final second = int.parse(timeParts[2]);

        final isPm = raw.toLowerCase().contains("pm");
        final isAm = raw.toLowerCase().contains("am");
        if (isPm && hour < 12) hour += 12;
        if (isAm && hour == 12) hour = 0;

        return DateTime(year, month, day, hour, minute, second);
      }
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  List<Map<String, dynamic>> _detectStops(List<dynamic> pts) {
    final List<Map<String, dynamic>> list = [];
    if (pts.isEmpty) return list;

    int i = 0;
    while (i < pts.length) {
      final startPt = pts[i];
      final startLat =
          double.tryParse(startPt["latitude"]?.toString() ?? "") ?? 0.0;
      final startLng =
          double.tryParse(startPt["longitude"]?.toString() ?? "") ?? 0.0;
      final startTime = _parseGpsDateTime(startPt["gps_time"]);

      if (startLat == 0.0 || startTime == null) {
        i++;
        continue;
      }

      int j = i + 1;
      DateTime lastTime = startTime;
      String stopAddress = startPt["address"] ?? "";

      while (j < pts.length) {
        final nextPt = pts[j];
        final nextLat =
            double.tryParse(nextPt["latitude"]?.toString() ?? "") ?? 0.0;
        final nextLng =
            double.tryParse(nextPt["longitude"]?.toString() ?? "") ?? 0.0;
        final nextTime = _parseGpsDateTime(nextPt["gps_time"]);

        if (nextLat == 0.0 || nextTime == null) {
          j++;
          continue;
        }

        final dist = _haversine(startLat, startLng, nextLat, nextLng);
        final speed =
            double.tryParse(nextPt["speed"]?.toString() ?? "0") ?? 0.0;

        if (dist < 50.0 && speed <= 5.0) {
          lastTime = nextTime;
          if (nextPt["address"] != null &&
              nextPt["address"].toString().isNotEmpty) {
            stopAddress = nextPt["address"];
          }
          j++;
        } else {
          break;
        }
      }

      final durationMin = lastTime.difference(startTime).inMinutes;
      if (durationMin >= 5) {
        String placeName = "Visited Location";
        for (var gf in userGeofences) {
          final gfLat =
              double.tryParse(gf["latitude"]?.toString() ?? "") ?? 0.0;
          final gfLng =
              double.tryParse(gf["longitude"]?.toString() ?? "") ?? 0.0;
          final gfRad =
              double.tryParse(gf["radius_meters"]?.toString() ?? "100") ??
              100.0;

          if (_haversine(startLat, startLng, gfLat, gfLng) <= gfRad) {
            placeName = gf["name"];
            break;
          }
        }

        if (placeName == "Visited Location" && stopAddress.isNotEmpty) {
          final addrParts = stopAddress.split(",");
          if (addrParts.isNotEmpty && addrParts[0].trim().isNotEmpty) {
            placeName = addrParts[0].trim();
          }
        }

        list.add({
          "latitude": startLat,
          "longitude": startLng,
          "place_name": placeName,
          "address": stopAddress.isNotEmpty
              ? stopAddress
              : "${startLat.toStringAsFixed(6)}, ${startLng.toStringAsFixed(6)}",
          "start_time": startPt["gps_time"],
          "end_time": pts[j - 1]["gps_time"],
          "duration": durationMin,
        });
        i = j;
      } else {
        i++;
      }
    }
    return list;
  }

  List<dynamic> _cleanGpsData(List<dynamic> rawList) {
    if (rawList.isEmpty) return [];

    final List<dynamic> clean = [];

    // Add first point if valid
    var first = rawList.first;
    var firstLat = double.tryParse(first["latitude"]?.toString() ?? "") ?? 0.0;
    var firstLng = double.tryParse(first["longitude"]?.toString() ?? "") ?? 0.0;
    if (firstLat != 0.0 && firstLng != 0.0) {
      clean.add(first);
    }

    for (int idx = 1; idx < rawList.length; idx++) {
      final pt = rawList[idx];
      final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
      final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
      final speed = double.tryParse(pt["speed"]?.toString() ?? "0") ?? 0.0;

      if (lat == 0.0 || lng == 0.0) continue;

      // Get previous clean point
      final prev = clean.last;
      final prevLat =
          double.tryParse(prev["latitude"]?.toString() ?? "") ?? 0.0;
      final prevLng =
          double.tryParse(prev["longitude"]?.toString() ?? "") ?? 0.0;

      final dist = _haversine(prevLat, prevLng, lat, lng);

      // 1. Remove duplicate coordinates (nearly identical)
      if (dist < 1.0) {
        continue;
      }

      // 2. Distance filter: if distance < 10m and speed < 2 km/h, ignore (removes drift stops)
      if (dist < 10.0 && speed < 2.0) {
        continue;
      }

      clean.add(pt);
    }
    return clean;
  }

  Future<void> _loadData() async {
    setState(() {
      loading = true;
      hasError = false;
      _markers.clear();
      _polylines.clear();
    });
    try {
      final dateStr = selectedDate.toIso8601String().split('T')[0];

      final responses = await Future.wait([
        ApiService.get(
          Uri.parse("$baseUrl/location_history/${widget.userId}?date=$dateStr"),
        ).timeout(const Duration(seconds: 15)),
        ApiService.get(
          Uri.parse("$baseUrl/geofences/${widget.userId}"),
        ).timeout(const Duration(seconds: 15)),
      ]);

      final res = responses[0];
      final geofenceRes = responses[1];

      if (res.statusCode == 200 && geofenceRes.statusCode == 200) {
        final json = jsonDecode(res.body);
        userGeofences = jsonDecode(geofenceRes.body)["geofences"] ?? [];
        _generateGeofenceMarkerIcons();
        if (!mounted) return;

        final rawHist = json["history"] ?? [];
        final rawMatchedRoute = json["matched_route"] ?? [];

        List<LatLng> backendSnappedRoute = [];
        for (var pt in rawMatchedRoute) {
          final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
          final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
          if (lat != 0.0 && lng != 0.0) {
            backendSnappedRoute.add(LatLng(lat, lng));
          }
        }

        // Detect stops on raw GPS data so duration information is preserved
        final detected = _detectStops(rawHist);

        // Clean GPS data for map route plotting
        final cleanHist = _cleanGpsData(rawHist);

        setState(() {
          _fullHistory = cleanHist;
          _fullDetectedStops = detected;
          _fullSnappedRoute = backendSnappedRoute;
          _timeRange = const RangeValues(0, 24);
          loading = false;
        });

        _filterHistory();
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      loading = false;
      hasError = true;
    });
  }

  void _filterHistory() {
    if (_fullHistory.isEmpty) return;

    final double startHour = _timeRange.start;
    final double endHour = _timeRange.end;

    final baseDate = selectedDate;
    final startMinTotal = (startHour * 60).round();
    final endMinTotal = (endHour * 60).round();

    final DateTime startLimit = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      startMinTotal ~/ 60,
      startMinTotal % 60,
    );
    final DateTime endLimit = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      endMinTotal ~/ 60,
      endMinTotal % 60,
    );

    final List<dynamic> filteredHist = [];
    for (var pt in _fullHistory) {
      final time = _parseGpsDateTime(pt["gps_time"]);
      if (time != null &&
          time.isAfter(startLimit.subtract(const Duration(seconds: 1))) &&
          time.isBefore(endLimit.add(const Duration(seconds: 1)))) {
        filteredHist.add(pt);
      }
    }

    final List<Map<String, dynamic>> filteredStops = [];
    for (var stop in _fullDetectedStops) {
      final stopStart = _parseGpsDateTime(stop["start_time"]);
      final stopEnd = _parseGpsDateTime(stop["end_time"]);
      if (stopStart != null && stopEnd != null) {
        if (stopStart.isBefore(endLimit) && stopEnd.isAfter(startLimit)) {
          filteredStops.add(stop);
        }
      }
    }

    setState(() {
      history = filteredHist;
      detectedStops = filteredStops;

      if (filteredHist.isNotEmpty) {
        startData = filteredHist.first;
        endData = filteredHist.last;
      } else {
        startData = null;
        endData = null;
      }

      if (startHour == 0.0 && endHour == 24.0 && _fullSnappedRoute.isNotEmpty) {
        _snappedSegments = [_fullSnappedRoute];
      } else {
        _snappedSegments = [];
      }
    });

    final rawSegments = _getCleanRouteSegments();
    final List<LatLng> cleanRoute = [];
    for (final seg in rawSegments) {
      cleanRoute.addAll(seg);
    }

    setState(() {
      totalDistanceMeters = _calcTotalDistance(cleanRoute);
    });

    _buildMapElements();
  }

  Color _parseColorHex(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFFFF6600);
    try {
      final clean = hex.toUpperCase().replaceAll("#", "");
      if (clean.length == 6) {
        return Color(int.parse("FF$clean", radix: 16));
      } else if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}
    return const Color(0xFFFF6600);
  }

  double _getMarkerHue(String? colorHex) {
    if (colorHex == null) return BitmapDescriptor.hueOrange;
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
      case 'FF6600':
      default:
        return BitmapDescriptor.hueOrange;
    }
  }

  Set<Circle> _buildCircles() {
    final Set<Circle> result = {};
    for (int i = 0; i < userGeofences.length; i++) {
      final gf = userGeofences[i];
      final lat = double.tryParse(gf["latitude"]?.toString() ?? "") ?? 0.0;
      final lng = double.tryParse(gf["longitude"]?.toString() ?? "") ?? 0.0;
      final colorHex = gf["color"]?.toString() ?? "#FF6600";
      final radius =
          double.tryParse(gf["radius_meters"]?.toString() ?? "100") ?? 100.0;
      final color = _parseColorHex(colorHex);

      if (lat != 0.0 && lng != 0.0) {
        result.add(
          Circle(
            circleId: CircleId("geofence_glow_$i"),
            center: LatLng(lat, lng),
            radius: radius * 1.05,
            strokeColor: color.withOpacity(0.15),
            strokeWidth: 6,
            fillColor: Colors.transparent,
          ),
        );
        result.add(
          Circle(
            circleId: CircleId("geofence_boundary_$i"),
            center: LatLng(lat, lng),
            radius: radius,
            strokeColor: color.withOpacity(0.7),
            strokeWidth: 2,
            fillColor: color.withOpacity(0.05),
          ),
        );
      }
    }
    return result;
  }

  Future<void> _generateGeofenceMarkerIcons() async {
    final Map<String, BitmapDescriptor> icons = {};
    for (var gf in userGeofences) {
      final String id = gf["id"]?.toString() ?? "";
      final String name = gf["name"]?.toString() ?? "Safe Zone";
      final String iconName = gf["icon"]?.toString() ?? "location";
      final String colorHex = gf["color"]?.toString() ?? "#FF6600";
      final Color color = _parseColorHex(colorHex);

      final icon = await _getGeofenceMarkerBitmap(name, iconName, color);
      icons[id] = icon;
    }
    if (!mounted) return;
    setState(() {
      _geofenceMarkerIcons = icons;
    });
    _buildMapElements();
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

  String _formatTimeValue(double hourVal) {
    final int totalMinutes = (hourVal * 60).round();
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;

    final int displayHours = hours % 12 == 0 ? 12 : hours % 12;
    final String amPm = hours >= 12 ? "PM" : "AM";
    final String minStr = minutes.toString().padLeft(2, '0');

    return "${displayHours.toString().padLeft(2, '0')}:$minStr $amPm";
  }

  List<List<LatLng>> _getCleanRouteSegments() {
    final List<List<LatLng>> segments = [];
    List<LatLng> currentSegment = [];
    LatLng? lastValid;
    DateTime? lastTime;

    for (final pt in history) {
      final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
      final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
      final time = _parseGpsDateTime(pt["gps_time"]);

      if (lat == 0.0 || lng == 0.0 || lat == 11.017565 || lng == 76.955836) {
        continue;
      }

      if (lastValid != null && lastTime != null && time != null) {
        final dist = _haversine(
          lastValid.latitude,
          lastValid.longitude,
          lat,
          lng,
        );
        final seconds = time.difference(lastTime).inSeconds;
        if (seconds > 0) {
          final speedKmH = (dist / seconds) * 3.6;
          if (speedKmH > 150.0 && dist > 500.0) {
            continue;
          }
        }

        if (seconds > 600 || dist > 500.0) {
          if (currentSegment.isNotEmpty) {
            segments.add(currentSegment);
            currentSegment = [];
          }
        }
      }

      final pos = LatLng(lat, lng);
      currentSegment.add(pos);
      lastValid = pos;
      lastTime = time;
    }

    if (currentSegment.isNotEmpty) {
      segments.add(currentSegment);
    }
    return segments;
  }

  void _buildMapElements() {
    if (history.isEmpty) return;

    final segments = _snappedSegments.isNotEmpty
        ? _snappedSegments
        : _getCleanRouteSegments();

    if (segments.isNotEmpty) {
      setState(() {
        _polylines.clear();
        _markers.clear();

        for (int i = 0; i < segments.length; i++) {
          _polylines.add(
            Polyline(
              polylineId: PolylineId("route_$i"),
              points: segments[i],
              color: _orange,
              width: 5,
            ),
          );
        }

        final startLat =
            double.tryParse(startData?["latitude"]?.toString() ?? "") ?? 0.0;
        final startLng =
            double.tryParse(startData?["longitude"]?.toString() ?? "") ?? 0.0;
        if (startLat != 0.0) {
          _markers.add(
            Marker(
              markerId: const MarkerId("start"),
              position: LatLng(startLat, startLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
              infoWindow: InfoWindow(
                title: "Start Point",
                snippet: startData?["address"] ?? "",
              ),
            ),
          );
        }

        final endLat =
            double.tryParse(endData?["latitude"]?.toString() ?? "") ?? 0.0;
        final endLng =
            double.tryParse(endData?["longitude"]?.toString() ?? "") ?? 0.0;
        if (endLat != 0.0) {
          _markers.add(
            Marker(
              markerId: const MarkerId("end"),
              position: LatLng(endLat, endLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
              infoWindow: InfoWindow(
                title: "End Point",
                snippet: endData?["address"] ?? "",
              ),
            ),
          );
        }

        for (int i = 0; i < detectedStops.length; i++) {
          final stop = detectedStops[i];
          final stopLat = stop["latitude"] as double;
          final stopLng = stop["longitude"] as double;
          _markers.add(
            Marker(
              markerId: MarkerId("stop_$i"),
              position: LatLng(stopLat, stopLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueBlue,
              ),
              infoWindow: InfoWindow(
                title: "${stop["place_name"]} (${stop["duration"]} mins)",
                snippet: stop["address"],
              ),
            ),
          );
        }

        // Add geofences as markers
        for (int i = 0; i < userGeofences.length; i++) {
          final gf = userGeofences[i];
          final lat = double.tryParse(gf["latitude"]?.toString() ?? "") ?? 0.0;
          final lng = double.tryParse(gf["longitude"]?.toString() ?? "") ?? 0.0;
          final name = gf["name"]?.toString() ?? "Safe Zone";
          final colorHex = gf["color"]?.toString() ?? "#FF6600";
          final radius =
              double.tryParse(gf["radius_meters"]?.toString() ?? "100") ??
              100.0;
          final String gfId = gf["id"]?.toString() ?? "";
          final customIcon = _geofenceMarkerIcons[gfId];

          if (lat != 0.0 && lng != 0.0) {
            _markers.add(
              Marker(
                markerId: MarkerId("geofence_$i"),
                position: LatLng(lat, lng),
                icon:
                    customIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(
                      _getMarkerHue(colorHex),
                    ),
                infoWindow: InfoWindow(
                  title: name,
                  snippet: "Radius: ${radius.toStringAsFixed(0)} m",
                ),
              ),
            );
          }
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: segments.first.first, zoom: 14),
          ),
        );
      });
    }
  }

  double _calcTotalDistance(List<LatLng> coords) {
    double total = 0;
    for (int i = 1; i < coords.length; i++) {
      total += _haversine(
        coords[i - 1].latitude,
        coords[i - 1].longitude,
        coords[i].latitude,
        coords[i].longitude,
      );
    }
    return total;
  }

  String _formatDist(double m) {
    if (m < 1000) return "${m.toStringAsFixed(0)} m";
    return "${(m / 1000).toStringAsFixed(2)} km";
  }

  void _prevDay() {
    setState(
      () => selectedDate = selectedDate.subtract(const Duration(days: 1)),
    );
    _loadData();
  }

  void _nextDay() {
    if (selectedDate.isBefore(
      DateTime.now().subtract(const Duration(days: 1)),
    )) {
      setState(() => selectedDate = selectedDate.add(const Duration(days: 1)));
      _loadData();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _orange, surface: _card),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != selectedDate) {
      setState(() => selectedDate = picked);
      _loadData();
    }
  }

  String _getEmojiForPlace(String name) {
    final lower = name.toLowerCase();
    if (lower.contains("home")) return "🏠";
    if (lower.contains("school")) return "🏫";
    if (lower.contains("tuition") || lower.contains("class")) return "🎓";
    if (lower.contains("office") || lower.contains("work")) return "💼";
    if (lower.contains("park") || lower.contains("garden")) return "🌳";
    if (lower.contains("shop") ||
        lower.contains("mart") ||
        lower.contains("smart") ||
        lower.contains("store") ||
        lower.contains("mall"))
      return "🛒";
    if (lower.contains("hotel") ||
        lower.contains("restaurant") ||
        lower.contains("cafe") ||
        lower.contains("tea"))
      return "☕";
    return "📍";
  }

  String _formatStayed(int mins) {
    if (mins < 60) return "$mins min";
    final hrs = mins ~/ 60;
    final remainingMins = mins % 60;
    if (remainingMins == 0) return "${hrs}h";
    return "${hrs}h ${remainingMins}m";
  }

  List<_TimelineEvent> _buildTimeline() {
    final List<_TimelineEvent> events = [];

    // 1. Day Started At (First GPS location)
    if (startData != null) {
      final startLat =
          double.tryParse(startData!["latitude"]?.toString() ?? "") ?? 0.0;
      final startLng =
          double.tryParse(startData!["longitude"]?.toString() ?? "") ?? 0.0;

      String startPlaceName = "";
      String emoji = "📍";

      for (var gf in userGeofences) {
        final gfLat = double.tryParse(gf["latitude"]?.toString() ?? "") ?? 0.0;
        final gfLng = double.tryParse(gf["longitude"]?.toString() ?? "") ?? 0.0;
        final gfRad =
            double.tryParse(gf["radius_meters"]?.toString() ?? "100") ?? 100.0;
        if (_haversine(startLat, startLng, gfLat, gfLng) <= gfRad) {
          startPlaceName = gf["name"];
          emoji = _getEmojiForPlace(gf["name"]);
          break;
        }
      }

      if (startPlaceName.isEmpty && startData!["address"] != null) {
        final addrParts = startData!["address"].toString().split(",");
        if (addrParts.isNotEmpty && addrParts[0].trim().isNotEmpty) {
          startPlaceName = addrParts[0].trim();
        }
      }
      if (startPlaceName.isEmpty) {
        startPlaceName = "Unknown Location";
      }

      events.add(
        _TimelineEvent(
          time: _parseTime(startData!["gps_time"]),
          parsedTime:
              _parseGpsDateTime(startData!["gps_time"]) ?? DateTime(1970),
          label: "🌍 Day Started At",
          sublabel: "$emoji $startPlaceName",
          color: Colors.green,
          icon: Icons.play_circle_rounded,
        ),
      );
    }

    // 2. Geofence Entries & Exits Transitions
    List<Map<String, dynamic>> geofenceCrossings = [];
    String? currentGeofenceName;
    DateTime? entryTime;
    String? geofenceAddress;

    for (var pt in history) {
      final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
      final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
      final time = _parseGpsDateTime(pt["gps_time"]);
      if (lat == 0.0 || time == null) continue;

      String? matchedGeofence;
      for (var gf in userGeofences) {
        final gfLat = double.tryParse(gf["latitude"]?.toString() ?? "") ?? 0.0;
        final gfLng = double.tryParse(gf["longitude"]?.toString() ?? "") ?? 0.0;
        final gfRad =
            double.tryParse(gf["radius_meters"]?.toString() ?? "100") ?? 100.0;

        if (_haversine(lat, lng, gfLat, gfLng) <= gfRad) {
          matchedGeofence = gf["name"];
          break;
        }
      }

      if (matchedGeofence != currentGeofenceName) {
        if (currentGeofenceName != null && entryTime != null) {
          final exitTime = time;
          final durationMin = exitTime.difference(entryTime).inMinutes;
          geofenceCrossings.add({
            "type": "Exit",
            "name": currentGeofenceName,
            "gps_time": pt["gps_time"],
            "duration": durationMin,
            "address": geofenceAddress ?? pt["address"] ?? "Safe Zone Boundary",
            "parsedTime": time,
          });
        }
        if (matchedGeofence != null) {
          currentGeofenceName = matchedGeofence;
          entryTime = time;
          geofenceAddress = pt["address"];
          geofenceCrossings.add({
            "type": "Entry",
            "name": matchedGeofence,
            "gps_time": pt["gps_time"],
            "address": pt["address"] ?? "Safe Zone Boundary",
            "parsedTime": time,
          });
        } else {
          currentGeofenceName = null;
          entryTime = null;
          geofenceAddress = null;
        }
      }
    }

    // Flush final geofence exit if day ended inside it
    if (currentGeofenceName != null &&
        entryTime != null &&
        history.isNotEmpty) {
      final lastPt = history.last;
      final exitTime = _parseGpsDateTime(lastPt["gps_time"]) ?? entryTime;
      final durationMin = exitTime.difference(entryTime).inMinutes;
      geofenceCrossings.add({
        "type": "Exit",
        "name": currentGeofenceName,
        "gps_time": lastPt["gps_time"],
        "duration": durationMin,
        "address": geofenceAddress ?? lastPt["address"] ?? "Safe Zone Boundary",
        "parsedTime": exitTime.add(const Duration(seconds: 1)),
      });
    }

    // Add geofence entry/exit events
    for (var cross in geofenceCrossings) {
      final isEntry = cross["type"] == "Entry";
      final timeStr = _parseTime(cross["gps_time"]);
      final emoji = _getEmojiForPlace(cross["name"]);

      if (isEntry) {
        events.add(
          _TimelineEvent(
            time: timeStr,
            parsedTime: cross["parsedTime"],
            label: "$emoji Enter ${cross["name"]}",
            sublabel: cross["address"] ?? "Safe Zone",
            color: Colors.green,
            icon: Icons.login_rounded,
          ),
        );
      } else {
        final duration = cross["duration"] as int;
        events.add(
          _TimelineEvent(
            time: timeStr,
            parsedTime: cross["parsedTime"],
            label: "$emoji Exit ${cross["name"]}",
            sublabel: "Stayed : ${_formatStayed(duration)}",
            color: _orange,
            icon: Icons.logout_rounded,
          ),
        );
      }
    }

    // 3. Stops > 5 min outside marked locations (e.g. Reliance Smart, VOC Park)
    for (int i = 0; i < detectedStops.length; i++) {
      final stop = detectedStops[i];
      final duration = stop["duration"] as int;
      final place = stop["place_name"] as String;
      final arrivalTime = _parseTime(stop["start_time"]);
      final departureTime = _parseTime(stop["end_time"]);

      bool isInsideGeofence = false;
      final stopLat = stop["latitude"] as double;
      final stopLng = stop["longitude"] as double;
      for (var gf in userGeofences) {
        final gfLat = double.tryParse(gf["latitude"]?.toString() ?? "") ?? 0.0;
        final gfLng = double.tryParse(gf["longitude"]?.toString() ?? "") ?? 0.0;
        final gfRad =
            double.tryParse(gf["radius_meters"]?.toString() ?? "100") ?? 100.0;
        if (_haversine(stopLat, stopLng, gfLat, gfLng) <= gfRad) {
          isInsideGeofence = true;
          break;
        }
      }

      if (!isInsideGeofence) {
        final emoji = _getEmojiForPlace(place);
        events.add(
          _TimelineEvent(
            time: "$arrivalTime - $departureTime",
            parsedTime: _parseGpsDateTime(stop["start_time"]) ?? DateTime(1970),
            label: "$emoji $place",
            sublabel:
                "Arrival : $arrivalTime\nDeparture : $departureTime\nStayed : ${_formatStayed(duration)}",
            color: Colors.blueAccent,
            icon: Icons.pause_circle_rounded,
          ),
        );
      }
    }

    // 4. Day Ended At (Last GPS location)
    if (endData != null &&
        startData != null &&
        endData!["gps_time"] != startData!["gps_time"]) {
      final endLat =
          double.tryParse(endData!["latitude"]?.toString() ?? "") ?? 0.0;
      final endLng =
          double.tryParse(endData!["longitude"]?.toString() ?? "") ?? 0.0;

      String endPlaceName = "";
      String emoji = "📍";
      bool isInside = false;

      for (var gf in userGeofences) {
        final gfLat = double.tryParse(gf["latitude"]?.toString() ?? "") ?? 0.0;
        final gfLng = double.tryParse(gf["longitude"]?.toString() ?? "") ?? 0.0;
        final gfRad =
            double.tryParse(gf["radius_meters"]?.toString() ?? "100") ?? 100.0;
        if (_haversine(endLat, endLng, gfLat, gfLng) <= gfRad) {
          endPlaceName = "At " + gf["name"];
          emoji = _getEmojiForPlace(gf["name"]);
          isInside = true;
          break;
        }
      }

      if (!isInside && endData!["address"] != null) {
        final addrParts = endData!["address"].toString().split(",");
        if (addrParts.isNotEmpty && addrParts[0].trim().isNotEmpty) {
          endPlaceName = "At " + addrParts[0].trim();
        }
      }

      events.add(
        _TimelineEvent(
          time: _parseTime(endData!["gps_time"]),
          parsedTime: _parseGpsDateTime(endData!["gps_time"]) ?? DateTime(2099),
          label: "$emoji Day Ended $endPlaceName",
          sublabel: endData!["address"] ?? "Final Location",
          color: _orange,
          icon: Icons.location_on_rounded,
        ),
      );
    }

    events.sort((a, b) => a.parsedTime.compareTo(b.parsedTime));
    return events;
  }

  String _parseTime(String? raw) {
    if (raw == null) return "-";
    try {
      if (raw.contains(" ")) {
        final parts = raw.split(" ");
        if (parts.length >= 2) {
          return "${parts[1]} ${parts.length > 2 ? parts[2] : ''}".trim();
        }
      }
      return raw;
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "History",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    if (!_showFilters)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          "$_formattedDate • ${_formatTimeValue(_timeRange.start)} - ${_formatTimeValue(_timeRange.end)}",
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showFilters = !_showFilters;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _showFilters ? _orange.withOpacity(0.15) : _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _showFilters ? _orange : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      _showFilters
                          ? Icons.expand_less_rounded
                          : Icons.filter_alt_rounded,
                      color: _showFilters ? _orange : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── VIEW TOGGLE ──
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isMapView = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isMapView ? _orange : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.map_rounded,
                            size: 18,
                            color: _isMapView ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Map View",
                            style: TextStyle(
                              color: _isMapView ? Colors.white : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isMapView = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isMapView ? _orange : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.list_alt_rounded,
                            size: 18,
                            color: !_isMapView ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Details View",
                            style: TextStyle(
                              color: !_isMapView ? Colors.white : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── DATE NAVIGATOR ──
          if (_showFilters)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.grey.shade400,
                    ),
                    onPressed: _prevDay,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickDate,
                      child: Text(
                        _formattedDate,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.chevron_right_rounded,
                      color:
                          selectedDate.isBefore(
                            DateTime.now().subtract(const Duration(days: 1)),
                          )
                          ? Colors.grey.shade400
                          : Colors.grey.shade700,
                    ),
                    onPressed: _nextDay,
                  ),
                ],
              ),
            ),

          // ── TIME RANGE SLIDER ──
          if (_showFilters && !loading && !hasError && _fullHistory.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_filled_rounded,
                            color: _orange,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Filter Time Range",
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "${_formatTimeValue(_timeRange.start)} - ${_formatTimeValue(_timeRange.end)}",
                        style: const TextStyle(
                          color: _orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _orange,
                      inactiveTrackColor: Colors.white.withOpacity(0.1),
                      thumbColor: _orange,
                      overlayColor: _orange.withOpacity(0.2),
                      valueIndicatorColor: _card,
                      valueIndicatorTextStyle: const TextStyle(
                        color: Colors.white,
                      ),
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                    ),
                    child: RangeSlider(
                      values: _timeRange,
                      min: 0,
                      max: 24,
                      divisions: 96,
                      labels: RangeLabels(
                        _formatTimeValue(_timeRange.start),
                        _formatTimeValue(_timeRange.end),
                      ),
                      onChanged: (RangeValues values) {
                        setState(() {
                          _timeRange = values;
                        });
                        _filterHistory();
                      },
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: loading
                ? const AppLoadingWidget()
                : hasError
                ? _buildError()
                : history.isEmpty
                ? _buildEmpty()
                : _isMapView
                ? _buildMapView()
                : _buildDetailsView(),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(
                  double.tryParse(
                        history.first["latitude"]?.toString() ?? "11.0252",
                      ) ??
                      11.0252,
                  double.tryParse(
                        history.first["longitude"]?.toString() ?? "76.9682",
                      ) ??
                      76.9682,
                ),
                zoom: 14,
              ),
              mapType: MapType.normal,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              markers: _markers,
              polylines: _polylines,
              circles: _buildCircles(),
              onMapCreated: (controller) {
                _mapController = controller;
                if (history.isNotEmpty) {
                  final lat =
                      double.tryParse(
                        history.first["latitude"]?.toString() ?? "",
                      ) ??
                      0.0;
                  final lng =
                      double.tryParse(
                        history.first["longitude"]?.toString() ?? "",
                      ) ??
                      0.0;
                  if (lat != 0.0) {
                    _mapController?.animateCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(target: LatLng(lat, lng), zoom: 14),
                      ),
                    );
                  }
                }
              },
            ),
          ),
        ),
        Positioned(bottom: 12, left: 16, right: 16, child: _buildStatsCard()),
      ],
    );
  }

  Widget _buildDetailsView() {
    final events = _buildTimeline();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _buildStatsCard(),
        ),
        if (events.isEmpty)
          Expanded(child: _buildEmpty())
        else
          Expanded(child: _buildTimelineList(events)),
      ],
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statChip(
            Icons.straighten_rounded,
            "Distance",
            _formatDist(totalDistanceMeters),
          ),
          _statDivider(),
          _statChip(Icons.pin_drop_rounded, "Points", "${history.length}"),
          _statDivider(),
          _statChip(
            Icons.pause_circle_outline_rounded,
            "Stops",
            "${detectedStops.length}",
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineList(List<_TimelineEvent> events) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: events.length,
      itemBuilder: (_, i) {
        final e = events[i];
        final isLast = i == events.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: e.color.withOpacity(0.15),
                        border: Border.all(
                          color: e.color.withOpacity(0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(e.icon, color: e.color, size: 18),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          color: Colors.grey.shade800,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            e.time,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        e.sublabel,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statChip(IconData icon, String label, String val) {
    return Column(
      children: [
        Icon(icon, color: _orange, size: 20),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          val,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _statDivider() {
    return Container(
      height: 24,
      width: 1,
      color: Colors.white.withOpacity(0.1),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route_rounded, size: 64, color: Colors.grey.shade700),
          const SizedBox(height: 16),
          Text(
            "No Journey Data",
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "No historical track found for this date",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 64,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 16),
          const Text(
            "Network Error",
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _loadData,
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }
}

class _TimelineEvent {
  final String time;
  final DateTime parsedTime;
  final String label;
  final String sublabel;
  final Color color;
  final IconData icon;

  _TimelineEvent({
    required this.time,
    required this.parsedTime,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.icon,
  });
}
