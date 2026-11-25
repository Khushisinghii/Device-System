import 'package:flutter/material.dart';
import 'dart:convert';
import '../../core/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/app_loading_widget.dart';

enum AlertType { lowBattery, enteredZone, leftZone, speed, sos, fullBattery }

class AppAlert {
  final int id;
  final AlertType type;
  final String title;
  final String subtitle;
  final String time;
  final String date;

  AppAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.date,
  });
}

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  static const Color _bg = Color(0xFF0D0F11);
  static const Color _card = Color(0xFF1A1D21);
  static const Color _orange = Color(0xFFFF6600);

  final String baseUrl =
      "https://b58k998z-5000.inc1.devtunnels.ms";
  List<AppAlert> _alerts = [];
  bool _loading = true;
  bool _hasError = false;
  int _userId = 0;

  // Multi-selection variables
  bool _isSelectMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getInt("userId") ?? 0;

      if (_userId == 0) {
        setState(() {
          _loading = false;
          _alerts = [];
        });
        return;
      }

      final res = await ApiService.get(
        Uri.parse("$baseUrl/notifications/$_userId"),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json["status"] == true && json["alerts"] != null) {
          final List<AppAlert> list = [];
          for (var item in json["alerts"]) {
            AlertType type;
            switch (item["type"]) {
              case "lowBattery":
                type = AlertType.lowBattery;
                break;
              case "enteredZone":
                type = AlertType.enteredZone;
                break;
              case "leftZone":
                type = AlertType.leftZone;
                break;
              case "speed":
                type = AlertType.speed;
                break;
              case "sos":
                type = AlertType.sos;
                break;
              case "fullBattery":
                type = AlertType.fullBattery;
                break;
              default:
                type = AlertType.lowBattery;
            }
            list.add(
              AppAlert(
                id: item["id"] ?? 0,
                type: type,
                title: item["title"] ?? "Alert",
                subtitle: item["subtitle"] ?? "",
                time: item["time"] ?? "",
                date: item["date"] ?? "",
              ),
            );
          }
          setState(() {
            _alerts = list;
            _loading = false;
          });
          return;
        }
      }
      setState(() {
        _loading = false;
        _hasError = true;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _deleteNotifications(List<int> ids) async {
    if (ids.isEmpty) return;

    setState(() {
      _loading = true;
    });

    try {
      final res = await ApiService.post(
        Uri.parse("$baseUrl/notifications/delete"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"ids": ids}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json["status"] == true) {
          setState(() {
            _alerts.removeWhere((alert) => ids.contains(alert.id));
            _selectedIds.removeAll(ids);
            if (_alerts.isEmpty) {
              _isSelectMode = false;
            }
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(json["message"] ?? "Deleted successfully"),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(json["message"] ?? "Failed to delete")),
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Network error occurred")));
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _clearAllNotifications() async {
    if (_userId == 0) return;

    // Confirm clear all
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Clear All Alerts",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  "Are you sure you want to permanently delete all notifications? This action cannot be undone.",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.12),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text(
                          "Cancel",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          "Clear All",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _loading = true;
    });

    try {
      final res = await ApiService.delete(
        Uri.parse("$baseUrl/notifications/$_userId"),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json["status"] == true) {
          setState(() {
            _alerts.clear();
            _selectedIds.clear();
            _isSelectMode = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to clear notifications")),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
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
                onPressed: () {
                  if (_isSelectMode) {
                    setState(() {
                      _isSelectMode = false;
                      _selectedIds.clear();
                    });
                  } else {
                    Navigator.pop(context);
                  }
                },
              )
            : null,
        title: Text(
          _isSelectMode ? "${_selectedIds.length} Selected" : "Alerts",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: _isSelectMode
            ? [
                IconButton(
                  icon: const Icon(
                    Icons.select_all_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_selectedIds.length == _alerts.length) {
                        _selectedIds.clear();
                      } else {
                        _selectedIds.addAll(_alerts.map((a) => a.id));
                      }
                    });
                  },
                  tooltip: "Select All",
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_rounded,
                    color: Colors.redAccent,
                  ),
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => _deleteNotifications(_selectedIds.toList()),
                  tooltip: "Delete Selected",
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _isSelectMode = false;
                      _selectedIds.clear();
                    });
                  },
                  tooltip: "Cancel",
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(
                    Icons.checklist_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _alerts.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _isSelectMode = true;
                          });
                        },
                  tooltip: "Select Mode",
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_sweep_rounded,
                    color: Colors.grey.shade500,
                    size: 22,
                  ),
                  onPressed: _alerts.isEmpty ? null : _clearAllNotifications,
                  tooltip: "Clear All",
                ),
              ],
      ),
      body: _loading
          ? const AppLoadingWidget()
          : _hasError
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 60,
                    color: Colors.redAccent.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Failed to load alerts",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _fetchNotifications,
                    child: const Text(
                      "Retry",
                      style: TextStyle(color: _orange),
                    ),
                  ),
                ],
              ),
            )
          : _alerts.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 60,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No alerts in the last 7 days",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _buildDismissibleTile(_alerts[i]),
            ),
    );
  }

  Widget _buildDismissibleTile(AppAlert alert) {
    if (_isSelectMode) {
      return _alertTile(alert);
    }

    return Dismissible(
      key: Key(alert.id.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        _deleteNotifications([alert.id]);
      },
      child: _alertTile(alert),
    );
  }

  Widget _alertTile(AppAlert alert) {
    final Color iconBg;
    final Color iconColor;
    final IconData icon;

    switch (alert.type) {
      case AlertType.lowBattery:
        iconBg = Colors.red.withOpacity(0.15);
        iconColor = Colors.redAccent;
        icon = Icons.battery_alert_rounded;
        break;
      case AlertType.enteredZone:
        iconBg = Colors.green.withOpacity(0.15);
        iconColor = Colors.green;
        icon = Icons.shield_rounded;
        break;
      case AlertType.leftZone:
        iconBg = Colors.amber.withOpacity(0.15);
        iconColor = Colors.amber;
        icon = Icons.directions_run_rounded;
        break;
      case AlertType.speed:
        iconBg = _orange.withOpacity(0.15);
        iconColor = _orange;
        icon = Icons.speed_rounded;
        break;
      case AlertType.sos:
        iconBg = Colors.red.withOpacity(0.2);
        iconColor = Colors.red;
        icon = Icons.sos_rounded;
        break;
      case AlertType.fullBattery:
        iconBg = Colors.green.withOpacity(0.15);
        iconColor = Colors.green;
        icon = Icons.battery_charging_full_rounded;
        break;
    }

    final bool isSelected = _selectedIds.contains(alert.id);

    return GestureDetector(
      onTap: () {
        if (_isSelectMode) {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(alert.id);
            } else {
              _selectedIds.add(alert.id);
            }
          });
        }
      },
      onLongPress: () {
        if (!_isSelectMode) {
          setState(() {
            _isSelectMode = true;
            _selectedIds.add(alert.id);
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? _orange.withOpacity(0.5)
                : Colors.white.withOpacity(0.06),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            if (_isSelectMode) ...[
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isSelected ? _orange : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 14),
            ],
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    alert.subtitle,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  alert.time,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  alert.date,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
