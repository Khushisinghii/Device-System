import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../pages/auth/login_page.dart';
import '../../pages/live_tracking/map_page.dart';
import '../../widgets/app_loading_widget.dart';
import '../../widgets/app_dialogs.dart';
import '../../pages/history/history_page.dart';

// --- CONFIGURATION ---
const String BASE_URL =
    "https://galleries-symphony-euros-addressing.trycloudflare.com";

class User {
  final int id;
  final String name;
  final String username;
  final String? password;
  final String phNo;
  final String imei;
  final String? address;
  final String role;
  final String createdRole;
  final String? status;
  final double? speed;
  final int? battery;
  final String? gpsTime;

  User({
    required this.id,
    required this.name,
    required this.username,
    this.password,
    required this.phNo,
    required this.imei,
    this.address,
    required this.role,
    required this.createdRole,
    this.status,
    this.speed,
    this.battery,
    this.gpsTime,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      username: json['username'] ?? '',
      password: json['password'],
      phNo: json['ph_no'] ?? '',
      imei: json['imei'] ?? '',
      address: json['address'],
      role: json['role'] ?? 'user',
      createdRole: json['created_role'] ?? 'admin',
      status: json['status'],
      speed: json['speed'] != null
          ? double.tryParse(json['speed'].toString())
          : null,
      battery: json['battery'] != null
          ? int.tryParse(json['battery'].toString())
          : null,
      gpsTime: json['gps_time'],
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final Color brandOrange = const Color(0xFFFF6600);
  final Color brandDark = const Color(0xFF1A1A1B);

  int userCount = 0;
  List<User> usersList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadDashboardData();
  }

  Future<void> loadDashboardData() async {
    setState(() => isLoading = true);
    await Future.wait([fetchUserCount(), fetchUsers()]);
    setState(() => isLoading = false);
  }

  Future<void> fetchUserCount() async {
    try {
      final response = await ApiService.get(Uri.parse('$BASE_URL/users/count'));
      if (response.statusCode == 200) {
        setState(
          () => userCount = json.decode(response.body)['total_users'] ?? 0,
        );
      }
    } catch (_) {}
  }

  Future<void> fetchUsers() async {
    try {
      final response = await ApiService.get(Uri.parse('$BASE_URL/users'));
      if (response.statusCode == 200) {
        final body = json.decode(response.body);

        final List data = body["users"];

        setState(() {
          usersList = data.map((i) => User.fromJson(i)).toList();
        });
      }
    } catch (_) {}
  }

  // --- UI BUILDER ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Text(
              "Scan",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: brandDark,
                fontSize: 24,
              ),
            ),
            Text(
              "ID",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: brandOrange,
                fontSize: 24,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();

              await prefs.clear();

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: brandOrange,
        onPressed: () => showUserForm(null),
        label: const Text(
          "ADD USER",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        icon: const Icon(Icons.add, color: Colors.white),
      ),
      body: isLoading
          ? const AppLoadingWidget()
          : RefreshIndicator(
              onRefresh: loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 25),
                    const Text(
                      "ACTIVE USERS",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 15),
                    ...usersList.map((user) => _buildUserCard(user)).toList(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: brandDark,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: brandOrange.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "MANAGEMENT",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 5),
              Text(
                "Total User Base",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          Text(
            userCount.toString(),
            style: TextStyle(
              color: brandOrange,
              fontSize: 48,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(User user) {
    final bool isOnline = user.status?.toUpperCase() == "ONLINE";
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: brandOrange.withOpacity(0.1),
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : "?",
                style: TextStyle(
                  color: brandOrange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                user.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (user.status != null)
              Text(
                user.status!,
                style: TextStyle(
                  color: isOnline ? Colors.green : Colors.red,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              "@${user.username}  |  ${user.phNo}",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            if (user.speed != null || user.battery != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (user.speed != null) ...[
                    const Icon(Icons.speed, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      "${user.speed} km/h",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (user.battery != null) ...[
                    const Icon(
                      Icons.battery_3_bar_rounded,
                      size: 12,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "${user.battery}%",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => _showDetailsSheet(user),
      ),
    );
  }

  // --- ATTRACTIVE FORM (ADD / EDIT) ---

  void showUserForm(User? user) {
    bool isEdit = user != null;
    bool hidePassword = true;
    final name = TextEditingController(text: user?.name);
    final uname = TextEditingController(text: user?.username);
    final pass = TextEditingController(text: isEdit ? "********" : "");
    final ph = TextEditingController(text: user?.phNo);
    final imei = TextEditingController(text: user?.imei);
    final addr = TextEditingController(text: user?.address);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: EdgeInsets.only(
          left: 25,
          right: 25,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isEdit ? "Update Profile" : "Register User",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 25),
              _styledInput(name, "Full Name", Icons.badge_outlined),
              _styledInput(
                uname,
                "Username",
                Icons.person_outline,
                enabled: !isEdit,
              ),
              StatefulBuilder(
                builder: (context, setModalState) {
                  return TextField(
                    controller: pass,
                    obscureText: hidePassword,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.lock_outline, color: brandOrange),
                      labelText: "Secure Password",
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: brandOrange),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setModalState(() {
                            hidePassword = !hidePassword;
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
              _styledInput(
                ph,
                "Phone Number",
                Icons.phone_android,
                type: TextInputType.phone,
              ),
              _styledInput(
                imei,
                "Device IMEI",
                Icons.developer_mode,
                type: TextInputType.number,
              ),
              _styledInput(addr, "Address (Optional)", Icons.map_outlined),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandOrange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: () async {
                    if (name.text.isEmpty ||
                        uname.text.isEmpty ||
                        pass.text.isEmpty ||
                        ph.text.isEmpty ||
                        imei.text.isEmpty)
                      return;
                    final body = {
                      "name": name.text,
                      "username": uname.text,
                      "password": pass.text,
                      "ph_no": ph.text,
                      "imei": imei.text,
                      "address": addr.text,
                      "role": "user",
                      "created_role": "1",
                    };
                    final url = isEdit
                        ? '$BASE_URL/users/${user.id}'
                        : '$BASE_URL/users';
                    final response =
                        await (isEdit ? ApiService.put : ApiService.post)(
                          Uri.parse(url),
                          headers: {"Content-Type": "application/json"},
                          body: jsonEncode(body),
                        );
                    if (response.statusCode < 300) {
                      Navigator.pop(context);
                      loadDashboardData();
                    }
                  },
                  child: Text(
                    isEdit ? "UPDATE USER" : "CREATE ACCOUNT",
                    style: const TextStyle(
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

  Widget _styledInput(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool isPass = false,
    bool enabled = true,
    TextInputType type = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: ctrl,
        obscureText: isPass,
        enabled: enabled,
        keyboardType: type,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: brandOrange),
          labelText: label,
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: brandOrange),
          ),
        ),
      ),
    );
  }

  // --- DETAILS MODAL ---

  void _showDetailsSheet(User user) {
    final bool isOnline = user.status?.toUpperCase() == "ONLINE";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: brandOrange,
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : "?",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "@${user.username}",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    user.status ?? "OFFLINE",
                    style: TextStyle(
                      color: isOnline ? Colors.green : Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 30),
            _infoRow("Phone", user.phNo),
            _infoRow("IMEI", user.imei),
            _infoRow("Address", user.address ?? "Not Provided"),
            if (user.gpsTime != null) _infoRow("Last Sync Time", user.gpsTime!),
            if (user.speed != null) _infoRow("Speed", "${user.speed} km/h"),
            if (user.battery != null)
              _infoRow("Battery Level", "${user.battery}%"),

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MapPage(userId: user.id),
                        ),
                      );
                    },
                    icon: const Icon(Icons.map_rounded),
                    label: const Text(
                      "TRACK LIVE",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HistoryPage(userId: user.id),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history_rounded),
                    label: const Text(
                      "VIEW HISTORY",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      showUserForm(user);
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text(
                      "EDIT ACCOUNT",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.1),
                      foregroundColor: Colors.redAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final confirm = await AppDialogs.showConfirm(
                        context,
                        title: "Delete User",
                        message:
                            "Are you sure you want to delete ${user.name}? This action cannot be undone.",
                        confirmText: "Delete",
                        cancelText: "Cancel",
                        isDeleteAction: true,
                      );
                      if (confirm == true) {
                        final res = await ApiService.delete(
                          Uri.parse('$BASE_URL/users/${user.id}'),
                        );
                        if (res.statusCode == 200) {
                          if (!mounted) return;
                          Navigator.pop(context);
                          loadDashboardData();
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_rounded, size: 18),
                    label: const Text(
                      "DELETE USER",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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
  }

  Widget _infoRow(String title, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            "$title: ",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          Text(val, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
