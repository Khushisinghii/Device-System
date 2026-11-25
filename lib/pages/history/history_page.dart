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
      "https://b58k998z-5000.inc1.devtunnels.ms";

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
  List<Map<String, dynamic>> _backendRouteSegments =
      []; // [{points: List<LatLng>, travel_count: int, ...}]
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

  bool _isStationaryDay(List<dynamic> pts) {
    if (pts.isEmpty) return false;
    double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    int validCount = 0;
    for (final pt in pts) {
      final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
      final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
      if (lat == 0.0 || lng == 0.0) continue;
      validCount++;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    if (validCount < 2) return true;
    final maxSpanMeters = _haversine(minLat, minLng, maxLat, maxLng);
    // If all points across the entire day/filter are within 350 meters, the tracker stayed in one location
    return maxSpanMeters < 350.0;
  }

  List<Map<String, dynamic>> _detectStops(List<dynamic> pts) {
    final List<Map<String, dynamic>> rawList = [];
    if (pts.isEmpty) return rawList;

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

        // Allow up to 100m drift while speed <= 5 km/h for stationary stay detection
        if (dist < 100.0 && speed <= 5.0) {
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

        rawList.add({
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

    if (rawList.isEmpty) return [];

    // Stop Deduplication & Merging:
    // If consecutive or nearby stops are within 150m of each other,
    // merge them into a single stop so pins do not stack on top of each other.
    final List<Map<String, dynamic>> mergedStops = [];
    for (var stop in rawList) {
      if (mergedStops.isEmpty) {
        mergedStops.add(Map<String, dynamic>.from(stop));
        continue;
      }

      final prev = mergedStops.last;
      final dist = _haversine(
        prev["latitude"] as double,
        prev["longitude"] as double,
        stop["latitude"] as double,
        stop["longitude"] as double,
      );

      if (dist < 150.0) {
        final prevDur = (prev["duration"] as int?) ?? 0;
        final currDur = (stop["duration"] as int?) ?? 0;
        prev["duration"] = prevDur + currDur;
        prev["end_time"] = stop["end_time"];
        if ((prev["address"] == null || prev["address"].toString().isEmpty) &&
            stop["address"] != null) {
          prev["address"] = stop["address"];
        }
      } else {
        mergedStops.add(Map<String, dynamic>.from(stop));
      }
    }

    return mergedStops;
  }

  List<dynamic> _cleanGpsData(List<dynamic> rawList) {
    if (rawList.isEmpty) return [];

    // Tier 1: Reject zero, out-of-bound coordinates and invalid GPS fixes
    final List<dynamic> validList = [];
    for (var pt in rawList) {
      final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
      final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
      final status = (pt["status"] ?? "").toString().toUpperCase();
      if (lat == 0.0 || lng == 0.0 || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        continue;
      }
      if (status == "INVALID") {
        continue;
      }
      validList.add(pt);
    }

    if (validList.isEmpty) return [];

    // Tier 2: Single-Point Outlier Spike Filter (Teleportation rejection)
    // If a point suddenly jumps > 300m away, but the next point returns close to previous,
    // it is a transient GPS coordinate glitch and should be discarded.
    final List<dynamic> noSpikes = [];
    noSpikes.add(validList.first);

    for (int i = 1; i < validList.length; i++) {
      final prev = noSpikes.last;
      final curr = validList[i];

      final prevLat = double.tryParse(prev["latitude"]?.toString() ?? "") ?? 0.0;
      final prevLng = double.tryParse(prev["longitude"]?.toString() ?? "") ?? 0.0;
      final currLat = double.tryParse(curr["latitude"]?.toString() ?? "") ?? 0.0;
      final currLng = double.tryParse(curr["longitude"]?.toString() ?? "") ?? 0.0;

      final distFromPrev = _haversine(prevLat, prevLng, currLat, currLng);

      if (i + 1 < validList.length && distFromPrev > 300.0) {
        final next = validList[i + 1];
        final nextLat = double.tryParse(next["latitude"]?.toString() ?? "") ?? 0.0;
        final nextLng = double.tryParse(next["longitude"]?.toString() ?? "") ?? 0.0;
        final distNextFromPrev = _haversine(prevLat, prevLng, nextLat, nextLng);

        // Next point is back near previous location (< 200m) -> curr is a jump spike
        if (distNextFromPrev < 200.0) {
          continue;
        }
      }

      noSpikes.add(curr);
    }

    // Tier 3: Stationary Drift Suppression (No spiderweb lines when parked)
    final List<dynamic> clean = [];
    clean.add(noSpikes.first);

    dynamic anchorPt = noSpikes.first;
    double anchorLat = double.tryParse(anchorPt["latitude"]?.toString() ?? "") ?? 0.0;
    double anchorLng = double.tryParse(anchorPt["longitude"]?.toString() ?? "") ?? 0.0;

    for (int idx = 1; idx < noSpikes.length; idx++) {
      final pt = noSpikes[idx];
      final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
      final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
      final speed = double.tryParse(pt["speed"]?.toString() ?? "0") ?? 0.0;

      final distFromLast = _haversine(
        double.tryParse(clean.last["latitude"]?.toString() ?? "") ?? 0.0,
        double.tryParse(clean.last["longitude"]?.toString() ?? "") ?? 0.0,
        lat,
        lng,
      );

      // Skip exact duplicate readings
      if (distFromLast < 2.0) {
        continue;
      }

      // If vehicle/tracker is stationary (speed <= 2.5 km/h) and within 30m of anchor,
      // it is indoor/parking GPS drift. Suppress it to keep map clean!
      final distFromAnchor = _haversine(anchorLat, anchorLng, lat, lng);
      if (speed <= 2.5 && distFromAnchor < 30.0) {
        continue;
      }

      // Movement detected: advance anchor and add to clean route
      anchorPt = pt;
      anchorLat = lat;
      anchorLng = lng;
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
        ).timeout(const Duration(seconds: 60)),
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
        final rawRouteSegments = json["route_segments"] ?? [];

        // Parse route_segments from backend (with travel_count metadata)
        List<Map<String, dynamic>> parsedSegments = [];
        for (var seg in rawRouteSegments) {
          final points = seg["points"] ?? [];
          List<LatLng> segLatLngs = [];
          for (var pt in points) {
            final lat =
                double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
            final lng =
                double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
            if (lat != 0.0 && lng != 0.0) {
              segLatLngs.add(LatLng(lat, lng));
            }
          }
          if (segLatLngs.isNotEmpty) {
            parsedSegments.add({
              "points": segLatLngs,
              "travel_count": seg["travel_count"] ?? 1,
              "distance_km": seg["distance_km"] ?? 0.0,
              "first_time": seg["first_time"] ?? "",
              "last_time": seg["last_time"] ?? "",
            });
          }
        }

        // Detect stops on raw GPS data so duration information is preserved
        final detected = _detectStops(rawHist);

        // Clean GPS data for map route plotting
        final cleanHist = _cleanGpsData(rawHist);

        setState(() {
          _fullHistory = cleanHist;
          _fullDetectedStops = detected;
          _backendRouteSegments = parsedSegments;
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

    final isStationary = _isStationaryDay(filteredHist);

    // If tracker remained in the same place all day, consolidate into 1 clean stop
    if (isStationary && filteredHist.isNotEmpty) {
      final firstPt = filteredHist.first;
      final lastPt = filteredHist.last;
      final firstTime = _parseGpsDateTime(firstPt["gps_time"]);
      final lastTime = _parseGpsDateTime(lastPt["gps_time"]);
      int durMins = 0;
      if (firstTime != null && lastTime != null) {
        durMins = lastTime.difference(firstTime).inMinutes.abs();
      }
      if (durMins < 5) durMins = 5;

      String placeName = "Stationary Location";
      String addr = firstPt["address"] ?? lastPt["address"] ?? "";
      for (var gf in userGeofences) {
        final gfLat = double.tryParse(gf["latitude"]?.toString() ?? "") ?? 0.0;
        final gfLng = double.tryParse(gf["longitude"]?.toString() ?? "") ?? 0.0;
        final gfRad =
            double.tryParse(gf["radius_meters"]?.toString() ?? "100") ?? 100.0;
        final firstLat =
            double.tryParse(firstPt["latitude"]?.toString() ?? "") ?? 0.0;
        final firstLng =
            double.tryParse(firstPt["longitude"]?.toString() ?? "") ?? 0.0;
        if (_haversine(firstLat, firstLng, gfLat, gfLng) <= gfRad) {
          placeName = gf["name"];
          break;
        }
      }

      if (placeName == "Stationary Location" && addr.isNotEmpty) {
        final parts = addr.split(",");
        if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
          placeName = parts[0].trim();
        }
      }

      final firstLat =
          double.tryParse(firstPt["latitude"]?.toString() ?? "") ?? 0.0;
      final firstLng =
          double.tryParse(firstPt["longitude"]?.toString() ?? "") ?? 0.0;

      filteredStops.clear();
      filteredStops.add({
        "latitude": firstLat,
        "longitude": firstLng,
        "place_name": placeName,
        "address": addr.isNotEmpty
            ? addr
            : "${firstLat.toStringAsFixed(6)}, ${firstLng.toStringAsFixed(6)}",
        "start_time": firstPt["gps_time"],
        "end_time": lastPt["gps_time"],
        "duration": durMins,
      });
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

      if (isStationary) {
        totalDistanceMeters = 0.0;
      } else {
        // Always use the real, complete GPS points route so all path details are shown
        final rawSegments = _getCleanRouteSegments();
        final List<LatLng> cleanRoute = [];
        for (final seg in rawSegments) {
          cleanRoute.addAll(seg);
        }
        totalDistanceMeters = _calcTotalDistance(cleanRoute);
      }
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
    if (_isStationaryDay(history)) {
      return [];
    }
    final List<List<LatLng>> segments = [];
    List<LatLng> currentSegment = [];
    LatLng? lastValid;
    DateTime? lastTime;

    for (final pt in history) {
      final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
      final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
      final time = _parseGpsDateTime(pt["gps_time"]);

      if (lat == 0.0 || lng == 0.0) {
        continue;
      }

      if (lastValid != null && lastTime != null && time != null) {
        final dist = _haversine(
          lastValid.latitude,
          lastValid.longitude,
          lat,
          lng,
        );
        final seconds = time.difference(lastTime).inSeconds.abs();
        if (seconds > 0) {
          final speedKmH = (dist / seconds) * 3.6;
          if (speedKmH > 160.0 && dist > 400.0) {
            continue;
          }
        }

        // Only split into a new path segment if inactive > 15 minutes or jump > 2.5 km
        if (seconds > 900 || dist > 2500.0) {
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

    final isStationary = _isStationaryDay(history);
    final segments = _getCleanRouteSegments();

    setState(() {
      _polylines.clear();
      _markers.clear();

      if (isStationary) {
        // Vehicle/tracker was stationary all day in one location
        // Show ONE single clean Parked marker, NO messy spiderwebs!
        final pt = history.first;
        final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
        final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;

        if (lat != 0.0 && lng != 0.0) {
          final stop = detectedStops.isNotEmpty ? detectedStops.first : null;
          final duration = stop != null ? (stop["duration"] ?? 0) : 0;
          final place = stop != null
              ? (stop["place_name"] ?? "Parked Location")
              : "Parked Location";
          final addr =
              stop != null ? (stop["address"] ?? "") : (pt["address"] ?? "");

          _markers.add(
            Marker(
              markerId: const MarkerId("parked_single"),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
              infoWindow: InfoWindow(
                title: "🅿️ $place (${_formatStayed(duration)})",
                snippet: addr,
              ),
            ),
          );
        }
      } else {
        // Draw one Polyline per segment with width based on travel_count
        for (int i = 0; i < segments.length; i++) {
          int travelCount = 1;
          double distKm = 0;
          String firstTime = "";
          String lastTime = "";

          if (i < _backendRouteSegments.length) {
            travelCount = _backendRouteSegments[i]["travel_count"] ?? 1;
            distKm = (_backendRouteSegments[i]["distance_km"] ?? 0).toDouble();
            firstTime = _backendRouteSegments[i]["first_time"] ?? "";
            lastTime = _backendRouteSegments[i]["last_time"] ?? "";
          }

          int polyWidth = travelCount >= 4 ? 7 : (travelCount >= 2 ? 6 : 5);

          _polylines.add(
            Polyline(
              polylineId: PolylineId("route_$i"),
              points: segments[i],
              color: _orange,
              width: polyWidth,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              consumeTapEvents: true,
              onTap: () {
                _showSegmentInfo(travelCount, distKm, firstTime, lastTime);
              },
            ),
          );
        }

        // Start marker = GREEN
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
                title: "START",
                snippet:
                    "Time: ${_parseTime(startData?["gps_time"])}\n${startData?["address"] ?? ""}",
              ),
            ),
          );
        }

        // End marker = RED
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
                title: "END",
                snippet:
                    "Time: ${_parseTime(endData?["gps_time"])}\n${endData?["address"] ?? ""}",
              ),
            ),
          );
        }

        // Stop markers = BLUE (clean deduplicated stops)
        for (int i = 0; i < detectedStops.length; i++) {
          final stop = detectedStops[i];
          final stopLat = stop["latitude"] as double;
          final stopLng = stop["longitude"] as double;
          final duration = stop["duration"] ?? stop["duration_minutes"] ?? 0;
          _markers.add(
            Marker(
              markerId: MarkerId("stop_$i"),
              position: LatLng(stopLat, stopLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueBlue,
              ),
              infoWindow: InfoWindow(
                title: "STOP (${_formatStayed(duration)})",
                snippet:
                    "${stop["place_name"] ?? "Stop"}\n${stop["address"] ?? ""}",
              ),
            ),
          );
        }
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

    // Auto-fit camera
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isStationary) {
        final pt = history.first;
        final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
        final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
        if (lat != 0.0 && lng != 0.0) {
          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: LatLng(lat, lng), zoom: 16),
            ),
          );
        }
      } else {
        _fitCameraToBounds(segments);
      }
    });
  }

  void _showSegmentInfo(
    int travelCount,
    double distKm,
    String firstTime,
    String lastTime,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "🛣️  Travelled Road",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _segInfoRow(
              "Travelled",
              "$travelCount time${travelCount > 1 ? 's' : ''}",
            ),
            if (firstTime.isNotEmpty) _segInfoRow("First", firstTime),
            if (lastTime.isNotEmpty) _segInfoRow("Last", lastTime),
            if (distKm > 0)
              _segInfoRow("Distance", "${distKm.toStringAsFixed(1)} km"),
          ],
        ),
      ),
    );
  }

  Widget _segInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _fitCameraToBounds(List<List<LatLng>> segments) {
    if (_mapController == null) return;

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final seg in segments) {
      for (final pt in seg) {
        if (pt.latitude < minLat) minLat = pt.latitude;
        if (pt.latitude > maxLat) maxLat = pt.latitude;
        if (pt.longitude < minLng) minLng = pt.longitude;
        if (pt.longitude > maxLng) maxLng = pt.longitude;
      }
    }

    if (minLat >= maxLat || minLng >= maxLng || (maxLat - minLat).abs() < 0.0005) {
      // Single point or stationary area — smooth center zoom
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
            zoom: 16,
          ),
        ),
      );
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
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
    if (history.isEmpty) return [];

    if (_isStationaryDay(history)) {
      final stop = detectedStops.isNotEmpty ? detectedStops.first : null;
      final dur = stop != null ? (stop["duration"] as int? ?? 0) : 0;
      final place = stop != null
          ? (stop["place_name"] as String? ?? "Stationary Location")
          : "Stationary Location";
      final addr = stop != null
          ? (stop["address"] as String? ?? "")
          : (history.first["address"] ?? "");
      final startT = _parseTime(history.first["gps_time"]);
      final endT = _parseTime(history.last["gps_time"]);

      return [
        _TimelineEvent(
          time: startT != "-" && endT != "-" ? "$startT - $endT" : startT,
          parsedTime:
              _parseGpsDateTime(history.first["gps_time"]) ?? DateTime(1970),
          label: "🅿️ Stationary All Day at $place",
          sublabel:
              "Vehicle stayed in the same location • Stayed: ${_formatStayed(dur)}" +
              (addr.isNotEmpty ? "\n$addr" : ""),
          color: Colors.blueAccent,
          icon: Icons.local_parking_rounded,
        ),
      ];
    }

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

    // 3. Movement Trips between stops
    final segments = _getCleanRouteSegments();
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.length >= 2) {
        final dist = _calcTotalDistance(seg);
        if (dist >= 100.0) {
          // Find matching points in history to get time and addresses
          final firstLatLng = seg.first;
          final lastLatLng = seg.last;

          dynamic firstHistPt;
          dynamic lastHistPt;

          for (var pt in history) {
            final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
            final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
            if (firstHistPt == null && (lat - firstLatLng.latitude).abs() < 0.0001 && (lng - firstLatLng.longitude).abs() < 0.0001) {
              firstHistPt = pt;
            }
            if ((lat - lastLatLng.latitude).abs() < 0.0001 && (lng - lastLatLng.longitude).abs() < 0.0001) {
              lastHistPt = pt;
            }
          }

          final startT = _parseGpsDateTime(firstHistPt?["gps_time"]);
          final endT = _parseGpsDateTime(lastHistPt?["gps_time"]);
          int tripMins = 0;
          if (startT != null && endT != null) {
            tripMins = endT.difference(startT).inMinutes.abs();
          }

          final startTStr = _parseTime(firstHistPt?["gps_time"]);
          final endTStr = _parseTime(lastHistPt?["gps_time"]);
          final fromAddr = firstHistPt?["address"] ?? "Trip Start";
          final toAddr = lastHistPt?["address"] ?? "Trip End";

          events.add(
            _TimelineEvent(
              time: startTStr != "-" && endTStr != "-" ? "$startTStr - $endTStr" : startTStr,
              parsedTime: startT ?? DateTime(1970),
              label: "🚗 Trip • ${_formatDist(dist)}",
              sublabel: "Distance: ${_formatDist(dist)} • Duration: ${tripMins > 0 ? '$tripMins mins' : '< 1 min'}\nFrom: $fromAddr\nTo: $toAddr",
              color: _orange,
              icon: Icons.directions_car_rounded,
            ),
          );
        }
      }
    }

    // 4. All Detected Stops
    for (int i = 0; i < detectedStops.length; i++) {
      final stop = detectedStops[i];
      final duration = stop["duration"] as int? ?? stop["duration_minutes"] as int? ?? 0;
      final place = stop["place_name"] as String? ?? "Visited Location";
      final arrivalTime = _parseTime(stop["start_time"] ?? stop["gps_time"]);
      final departureTime = _parseTime(stop["end_time"] ?? stop["gps_time"]);
      final stopAddress = stop["address"] ?? "";

      final emoji = _getEmojiForPlace(place);
      events.add(
        _TimelineEvent(
          time: arrivalTime != departureTime && departureTime != "-"
              ? "$arrivalTime - $departureTime"
              : arrivalTime,
          parsedTime: _parseGpsDateTime(stop["start_time"] ?? stop["gps_time"]) ?? DateTime(1970),
          label: "$emoji $place",
          sublabel: "Arrival: $arrivalTime • Departure: $departureTime • Stayed: ${_formatStayed(duration)}" +
              (stopAddress.isNotEmpty ? "\n$stopAddress" : ""),
          color: Colors.blueAccent,
          icon: Icons.pause_circle_rounded,
        ),
      );
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
                if (_isStationaryDay(history) && history.isNotEmpty) {
                  final pt = history.first;
                  final lat = double.tryParse(pt["latitude"]?.toString() ?? "") ?? 0.0;
                  final lng = double.tryParse(pt["longitude"]?.toString() ?? "") ?? 0.0;
                  if (lat != 0.0 && lng != 0.0) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      _mapController?.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(target: LatLng(lat, lng), zoom: 16),
                        ),
                      );
                    });
                  }
                } else {
                  final segments = _snappedSegments.isNotEmpty
                      ? _snappedSegments
                      : _getCleanRouteSegments();
                  if (segments.isNotEmpty) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      _fitCameraToBounds(segments);
                    });
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
