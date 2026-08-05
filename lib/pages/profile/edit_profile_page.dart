import 'package:flutter/material.dart';
import 'dart:convert';
import '../../core/services/api_service.dart';

class EditProfilePage extends StatefulWidget {
  final int userId;
  final Map<String, dynamic> currentData;

  const EditProfilePage({
    super.key,
    required this.userId,
    required this.currentData,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController nameController;
  late TextEditingController usernameController;
  late TextEditingController phNoController;
  late TextEditingController imeiController;
  late TextEditingController addressController;

  bool loading = false;

  static const Color _bg = Color(0xFF0D0F11);
  static const Color _card = Color(0xFF1A1D21);
  static const Color _orange = Color(0xFFFF6600);

  final String baseUrl =
      "https://partners-vegetables-algebra-dryer.trycloudflare.com";

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(
      text: widget.currentData["name"]?.toString() ?? "",
    );
    usernameController = TextEditingController(
      text: widget.currentData["username"]?.toString() ?? "",
    );
    phNoController = TextEditingController(
      text: widget.currentData["ph_no"]?.toString() ?? "",
    );
    imeiController = TextEditingController(
      text: widget.currentData["imei"]?.toString() ?? "",
    );
    addressController = TextEditingController(
      text: widget.currentData["address"]?.toString() ?? "",
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);

    try {
      final response = await ApiService.post(
        Uri.parse("$baseUrl/update_profile"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.userId,
          "name": nameController.text.trim(),
          "username": usernameController.text.trim(),
          "ph_no": phNoController.text.trim(),
          "imei": imeiController.text.trim(),
          "address": addressController.text.trim(),
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && data["status"] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile updated successfully!")),
        );
        Navigator.pop(context, true); // Return true to trigger reload
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data["message"] ?? "Failed to update profile"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          "Edit Profile",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFieldCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Personal Info",
                      style: TextStyle(
                        color: _orange,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildTextField(
                      controller: nameController,
                      label: "Full Name",
                      icon: Icons.person_outline,
                      validator: (v) => v!.isEmpty ? "Name is required" : null,
                    ),
                    const SizedBox(height: 15),
                    _buildTextField(
                      controller: usernameController,
                      label: "Username",
                      icon: Icons.alternate_email_outlined,
                      validator: (v) =>
                          v!.isEmpty ? "Username is required" : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              _buildFieldCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Contact & Device Info",
                      style: TextStyle(
                        color: _orange,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildTextField(
                      controller: phNoController,
                      label: "Phone Number",
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: (v) =>
                          v!.isEmpty ? "Phone number is required" : null,
                    ),
                    const SizedBox(height: 15),
                    _buildTextField(
                      controller: imeiController,
                      label: "IMEI Number",
                      icon: Icons.fingerprint_rounded,
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          v!.isEmpty ? "IMEI number is required" : null,
                    ),
                    const SizedBox(height: 15),
                    _buildTextField(
                      controller: addressController,
                      label: "Address",
                      icon: Icons.home_outlined,
                      validator: (v) =>
                          v!.isEmpty ? "Address is required" : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Container(
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(
                    colors: [_orange, Color(0xFFFF8800)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: ElevatedButton(
                  onPressed: loading ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "SAVE CHANGES",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: child,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    required String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        prefixIcon: Icon(icon, color: _orange, size: 18),
        filled: true,
        fillColor: _bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
