import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../pages/geofence/geofence_page.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

class AddZonePage extends StatefulWidget {
  final GeofenceZone? editZone; // null = add new, non-null = edit
  const AddZonePage({super.key, this.editZone});

  @override
  State<AddZonePage> createState() => _AddZonePageState();
}

class _AddZonePageState extends State<AddZonePage>
    with SingleTickerProviderStateMixin {
  // ── Colors ──────────────────────────────────────────────────
  static const Color _bg = Color(0xFF0D0F11);
  static const Color _card = Color(0xFF1A1D21);
  static const Color _orange = Color(0xFFFF6600);
  static const Color _inputBg = Color(0xFF1E2227);
  final String baseUrl =
      "https://b58k998z-5000.inc1.devtunnels.ms";

  // ── Step state ───────────────────────────────────────────────
  int _step = 0; // 0=Select Location, 1=Zone Details, 2=Alerts

  // ── Map ──────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  LatLng _selectedLatLng = const LatLng(11.017565, 76.955836);
  String _selectedAddress = "Race Course, Coimbatore, Tamil Nadu, India";
  bool _locationPicked = true;
  bool _showTooltip = true;
  final TextEditingController _searchCtrl = TextEditingController();

  // ── Zone details ─────────────────────────────────────────────
  final TextEditingController _nameCtrl = TextEditingController();
  double _radiusMeters = 200;
  bool _saving = false;
  Color _zoneColor = _orange;
  String _selectedIconName = "home";
  bool _enterAlert = true; // true=Enter, false=Exit
  bool _notifyEnter = true;
  bool _notifyExit = false;
  bool _soundAlert = true;
  bool _vibrate = true;

  final List<Map<String, dynamic>> _iconOptions = [
    {"name": "home", "icon": Icons.home_rounded},
    {"name": "school", "icon": Icons.school_rounded},
    {"name": "hospital", "icon": Icons.local_hospital_rounded},
    {"name": "park", "icon": Icons.park_rounded},
    {"name": "office", "icon": Icons.work_rounded},
    {"name": "gym", "icon": Icons.fitness_center_rounded},
    {"name": "shop", "icon": Icons.shopping_bag_rounded},
    {"name": "restaurant", "icon": Icons.restaurant_rounded},
    {"name": "airport", "icon": Icons.flight_takeoff_rounded},
    {"name": "default", "icon": Icons.location_on_rounded},
  ];

  // ── Color palette ────────────────────────────────────────────
  final List<Color> _palette = [
    const Color(0xFFFF6600), // Orange
    const Color(0xFFEF5350), // Red
    const Color(0xFF4CAF50), // Green
    const Color(0xFF2196F3), // Blue
    const Color(0xFF9C27B0), // Purple
    const Color(0xFFFFB300), // Amber
    const Color(0xFF00BCD4), // Cyan
    const Color(0xFFE91E63), // Pink
    const Color(0xFF3F51B5), // Indigo
    const Color(0xFF009688), // Teal
  ];

  // ── Search geocoding state ────────────────────────────────────
  List<dynamic> _suggestions = [];
  Timer? _debounce;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    try {
      final response = await ApiService.get(
        Uri.parse(
          "https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&countrycodes=in&viewbox=76.0,8.0,80.5,14.0&limit=8",
        ),
        headers: {"User-Agent": "ScanID_App"},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          _suggestions = data;
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    if (widget.editZone != null) {
      final z = widget.editZone!;
      _nameCtrl.text = z.name;
      _radiusMeters = z.radiusMeters;
      _selectedLatLng = LatLng(z.lat, z.lng);
      _locationPicked = true;
      _selectedIconName = z.iconName;
      _zoneColor = z.color;
      _selectedAddress = "Locating address...";
      _reverseGeocode(_selectedLatLng);
    }
    // Hide tooltip after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showTooltip = false);
    });

    if (widget.editZone == null) {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    Position position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _selectedLatLng = LatLng(position.latitude, position.longitude);
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_selectedLatLng, 15.0),
      );
      _reverseGeocode(_selectedLatLng);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController?.dispose();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Map circles ──────────────────────────────────────────────
  Set<Circle> get _circles => {
    Circle(
      circleId: const CircleId("zone"),
      center: _selectedLatLng,
      radius: _radiusMeters,
      fillColor: _zoneColor.withAlpha(40),
      strokeColor: _zoneColor.withAlpha(200),
      strokeWidth: 2,
    ),
    Circle(
      circleId: const CircleId("zone_glow"),
      center: _selectedLatLng,
      radius: _radiusMeters * 1.06,
      fillColor: Colors.transparent,
      strokeColor: _zoneColor.withAlpha(60),
      strokeWidth: 6,
    ),
  };

  Set<Marker> get _markers => {
    Marker(
      markerId: const MarkerId("center"),
      position: _selectedLatLng,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      anchor: const Offset(0.5, 1.0),
    ),
  };

  void _onMapLongPress(LatLng pos) {
    setState(() {
      _selectedLatLng = pos;
      _locationPicked = true;
      _showTooltip = false;
      _selectedAddress = "Locating address...";
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
    _reverseGeocode(pos);
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    try {
      final response = await ApiService.get(
        Uri.parse(
          "https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}",
        ),
        headers: {"User-Agent": "ScanID_App"},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String displayName = data["display_name"] ?? "";
        if (displayName.isNotEmpty && mounted) {
          setState(() {
            _selectedAddress = displayName;
          });
        }
      }
    } catch (_) {}
  }

  void _recenter() {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _selectedLatLng, zoom: 15),
      ),
    );
  }

  // ── Save zone ─────────────────────────────────────────────────
  Future<void> _saveZone() async {
    if (_saving) return;

    final String name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Please enter a zone name"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final prefs = await SharedPreferences.getInstance();
    final int userId = prefs.getInt("userId") ?? 0;

    final String url = widget.editZone != null
        ? "$baseUrl/geofences/${widget.editZone!.id}"
        : "$baseUrl/geofences";

    try {
      final headers = {"Content-Type": "application/json"};
      final body = jsonEncode({
        "user_id": userId,
        "name": name,
        "radius_meters": _radiusMeters,
        "latitude": _selectedLatLng.latitude,
        "longitude": _selectedLatLng.longitude,
        "icon": _selectedIconName,
        "color":
            "#${_zoneColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}",
      });

      http.Response response;
      if (widget.editZone != null) {
        response = await ApiService.put(
          Uri.parse(url),
          headers: headers,
          body: body,
        );
      } else {
        response = await ApiService.post(
          Uri.parse(url),
          headers: headers,
          body: body,
        );
      }

      final resData = jsonDecode(response.body);
      if (resData["status"] == true) {
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        setState(() => _saving = false);
      }
    } catch (_) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Error saving to database. Check network."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: _step == 0
          ? _buildStep0()
          : _step == 1
          ? _buildStep1()
          : _buildStep2(),
    );
  }

  // ── APP BAR ─────────────────────────────────────────────────
  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 20,
        ),
        onPressed: () {
          if (_step > 0) {
            setState(() => _step--);
          } else {
            Navigator.pop(context);
          }
        },
      ),
      title: Text(
        widget.editZone != null ? "Edit Zone" : "Add Zone",
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      centerTitle: true,
      actions: [
        TextButton(
          onPressed: (_step == 2 && !_saving) ? _saveZone : null,
          child: Text(
            "SAVE",
            style: TextStyle(
              color: (_step == 2 && !_saving) ? _orange : Colors.grey.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  // ── STEP INDICATOR ──────────────────────────────────────────
  Widget _buildStepIndicator() {
    final steps = ["Select Location", "Zone Details", "Alerts"];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line
            final lineStep = i ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                color: _step > lineStep ? _orange : Colors.white.withAlpha(30),
              ),
            );
          }
          final idx = i ~/ 2;
          final isActive = _step == idx;
          final isDone = _step > idx;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive || isDone ? _orange : _card,
                  border: Border.all(
                    color: isActive || isDone
                        ? _orange
                        : Colors.white.withAlpha(40),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 14,
                        )
                      : Text(
                          "${idx + 1}",
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                steps[idx],
                style: TextStyle(
                  color: isActive ? _orange : Colors.grey.shade600,
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  STEP 0 — SELECT LOCATION
  // ════════════════════════════════════════════════════════════
  Widget _buildStep0() {
    return Stack(
      children: [
        Column(
          children: [
            _buildStepIndicator(),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: _inputBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withAlpha(20)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      Icons.search_rounded,
                      color: Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: "Search location or address",
                          hintStyle: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (v) {
                          if (v.isNotEmpty) {
                            _fetchSuggestions(v);
                          }
                        },
                      ),
                    ),
                    if (_searchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _suggestions = []);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.grey.shade500,
                            size: 18,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 14),
                  ],
                ),
              ),
            ),

            // Map
            Expanded(
              child: Stack(
                children: [
                  // Google Map
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _selectedLatLng,
                      zoom: 14,
                    ),
                    markers: _markers,
                    circles: _circles,
                    onMapCreated: (c) => _mapController = c,
                    onLongPress: _onMapLongPress,
                    onTap: (_) => setState(() {
                      _showTooltip = false;
                      _suggestions = [];
                    }),
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    mapType: MapType.normal,
                  ),

                  // Long press tooltip
                  if (_showTooltip)
                    Positioned(
                      top: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(200),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "Long press on map to\nselect location",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Right side controls
                  Positioned(
                    right: 12,
                    bottom: 16,
                    child: Column(
                      children: [
                        _mapBtn(Icons.my_location_rounded, _recenter),
                        const SizedBox(height: 8),
                        _mapBtn(Icons.add_rounded, () {
                          _mapController?.animateCamera(CameraUpdate.zoomIn());
                        }),
                        const SizedBox(height: 8),
                        _mapBtn(Icons.remove_rounded, () {
                          _mapController?.animateCamera(CameraUpdate.zoomOut());
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Selected location card
            Container(
              color: _bg,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Selected Location",
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withAlpha(20)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          color: _orange,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedAddress,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                "${_selectedLatLng.latitude.toStringAsFixed(6)}, ${_selectedLatLng.longitude.toStringAsFixed(6)}",
                                style: TextStyle(
                                  color: _orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _nextButton(
                    label: "NEXT",
                    onTap: () {
                      if (!_locationPicked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              "Long press map to select a location",
                            ),
                            backgroundColor: _orange,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                        return;
                      }
                      setState(() => _step = 1);
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),

        // Suggestions Dropdown Overlay
        if (_suggestions.isNotEmpty)
          Positioned(
            top: 110, // Under search bar
            left: 16,
            right: 16,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(30)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length,
                itemBuilder: (context, idx) {
                  final item = _suggestions[idx];
                  final String name = item["display_name"] ?? "";
                  return ListTile(
                    dense: true,
                    title: Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      final lat = double.tryParse(
                        item["lat"]?.toString() ?? "",
                      );
                      final lon = double.tryParse(
                        item["lon"]?.toString() ?? "",
                      );
                      if (lat != null && lon != null) {
                        setState(() {
                          _selectedLatLng = LatLng(lat, lon);
                          _selectedAddress = name;
                          _suggestions = [];
                          _searchCtrl.text = name;
                        });
                        _mapController?.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(target: _selectedLatLng, zoom: 15),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════
  //  STEP 1 — ZONE DETAILS
  // ════════════════════════════════════════════════════════════
  Widget _buildStep1() {
    final int radiusInt = _radiusMeters.round();
    final radiusInputCtrl = TextEditingController(text: radiusInt.toString());

    return Column(
      children: [
        _buildStepIndicator(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Zone Name ──────────────────────────────
                _sectionLabel("Zone Name"),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _inputBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  child: TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "e.g. Home, School, Office",
                      hintStyle: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                      prefixIcon: Icon(
                        Icons.label_outline_rounded,
                        color: _orange,
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Zone Icon ──────────────────────────────
                _sectionLabel("Zone Icon"),
                const SizedBox(height: 12),
                SizedBox(
                  height: 60,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    children: _iconOptions.map((opt) {
                      final isSelected = _selectedIconName == opt["name"];
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedIconName = opt["name"]),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 48,
                          height: 48,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? _zoneColor : _inputBg,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white.withOpacity(0.8)
                                  : Colors.white.withOpacity(0.08),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Icon(
                            opt["icon"],
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade400,
                            size: 20,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Radius Slider ──────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionLabel("Radius"),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _radiusLabel(_radiusMeters),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      "50 m",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: _orange,
                          inactiveTrackColor: Colors.white.withAlpha(30),
                          thumbColor: _orange,
                          overlayColor: _orange.withAlpha(30),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                          trackHeight: 3,
                        ),
                        child: Slider(
                          value: _radiusMeters.clamp(50, 1000),
                          min: 50,
                          max: 1000,
                          onChanged: (v) => setState(() => _radiusMeters = v),
                        ),
                      ),
                    ),
                    Text(
                      "1000 m",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Manual input box
                    Container(
                      width: 64,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _inputBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _orange.withAlpha(120)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: radiusInputCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (v) {
                                final val = double.tryParse(v);
                                if (val != null) {
                                  setState(
                                    () => _radiusMeters = val.clamp(50, 1000),
                                  );
                                }
                              },
                            ),
                          ),
                          Text(
                            "m",
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Zone Color ─────────────────────────────
                _sectionLabel("Zone Color"),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: _palette.map((c) {
                    final selected = _zoneColor == c;
                    return GestureDetector(
                      onTap: () => setState(() => _zoneColor = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: c.withAlpha(120),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : [],
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                // ── Zone Type ──────────────────────────────
                Row(
                  children: [
                    _sectionLabel("Zone Type"),
                    const SizedBox(width: 6),
                    Text(
                      "(Select what triggers alert)",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _zoneTypeCard(
                        icon: Icons.login_rounded,
                        label: "Enter Alert",
                        desc: "Notify when device enters zone",
                        selected: _enterAlert,
                        onTap: () => setState(() => _enterAlert = true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _zoneTypeCard(
                        icon: Icons.logout_rounded,
                        label: "Exit Alert",
                        desc: "Notify when device exits zone",
                        selected: !_enterAlert,
                        onTap: () => setState(() => _enterAlert = false),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),

        // NEXT button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: _nextButton(
            label: "NEXT",
            onTap: () {
              if (_nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("Please enter a zone name"),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
                return;
              }
              setState(() => _step = 2);
            },
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════
  //  STEP 2 — ALERTS
  // ════════════════════════════════════════════════════════════
  Widget _buildStep2() {
    return Column(
      children: [
        _buildStepIndicator(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _orange.withAlpha(60)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _zoneColor,
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nameCtrl.text.isEmpty
                                  ? "Unnamed Zone"
                                  : _nameCtrl.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              "${_radiusLabel(_radiusMeters)} radius  •  ${_enterAlert ? 'Enter Alert' : 'Exit Alert'}",
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                _sectionLabel("Notification Type"),
                const SizedBox(height: 12),

                _alertToggle(
                  icon: Icons.login_rounded,
                  iconColor: Colors.green,
                  label: "Entry Notification",
                  desc: "Alert when device enters zone",
                  value: _notifyEnter,
                  onChanged: (v) => setState(() => _notifyEnter = v),
                ),
                const SizedBox(height: 10),
                _alertToggle(
                  icon: Icons.logout_rounded,
                  iconColor: Colors.redAccent,
                  label: "Exit Notification",
                  desc: "Alert when device leaves zone",
                  value: _notifyExit,
                  onChanged: (v) => setState(() => _notifyExit = v),
                ),

                const SizedBox(height: 24),
                _sectionLabel("Alert Settings"),
                const SizedBox(height: 12),

                _alertToggle(
                  icon: Icons.volume_up_rounded,
                  iconColor: _orange,
                  label: "Sound Alert",
                  desc: "Play sound when zone is crossed",
                  value: _soundAlert,
                  onChanged: (v) => setState(() => _soundAlert = v),
                ),
                const SizedBox(height: 10),
                _alertToggle(
                  icon: Icons.vibration_rounded,
                  iconColor: Colors.blue,
                  label: "Vibration",
                  desc: "Vibrate when zone is crossed",
                  value: _vibrate,
                  onChanged: (v) => setState(() => _vibrate = v),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),

        // SAVE button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: _nextButton(
            label: _saving ? "SAVING..." : "SAVE ZONE",
            onTap: _saving ? () {} : _saveZone,
          ),
        ),
      ],
    );
  }

  // ── HELPERS ──────────────────────────────────────────────────

  String _radiusLabel(double m) {
    if (m >= 1000) return "${(m / 1000).toStringAsFixed(1)} km";
    return "${m.round()} m";
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: TextStyle(
      color: Colors.grey.shade400,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.4,
    ),
  );

  Widget _nextButton({required String label, required VoidCallback onTap}) =>
      SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _orange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          onPressed: onTap,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.5,
            ),
          ),
        ),
      );

  Widget _mapBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _bg.withAlpha(230),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 8),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );

  Widget _zoneTypeCard({
    required IconData icon,
    required String label,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: selected ? _orange.withAlpha(20) : _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? _orange : Colors.white.withAlpha(25),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: selected
                  ? _orange.withAlpha(40)
                  : Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: selected ? _orange : Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey.shade400,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    ),
  );

  Widget _alertToggle({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withAlpha(20)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withAlpha(30),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: _orange,
          inactiveThumbColor: Colors.grey.shade600,
          inactiveTrackColor: Colors.white.withAlpha(20),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    ),
  );
}
