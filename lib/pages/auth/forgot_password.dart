import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final usernameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final newPasswordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();

  bool hide1 = true;
  bool hide2 = true;
  bool isLoading = false;

  // Theme Colors
  final Color brandOrange = const Color(0xFFFF6600);
  final Color brandDark = const Color(0xFF1A1A1B);

  // Update this to your server IP
  final String baseUrl =
      "https://huntington-ware-seasons-first.trycloudflare.com";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: brandDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Reset Password",
          style: TextStyle(color: brandDark, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // --- ICON/LOGO AREA ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: brandOrange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_reset_rounded,
                  size: 80,
                  color: brandOrange,
                ),
              ),

              const SizedBox(height: 30),

              Text(
                "Secure Your Account",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: brandDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Enter your details to set a new password",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),

              const SizedBox(height: 40),

              // --- INPUT FIELDS ---
              _buildInputField(
                controller: usernameCtrl,
                hint: "Username",
                icon: Icons.person_outline,
              ),

              _buildInputField(
                controller: phoneCtrl,
                hint: "Registered Phone Number",
                icon: Icons.phone_android,
                type: TextInputType.phone,
              ),

              _buildInputField(
                controller: newPasswordCtrl,
                hint: "New Password",
                icon: Icons.lock_outline,
                isPass: true,
                obscure: hide1,
                onToggle: () => setState(() => hide1 = !hide1),
              ),

              _buildInputField(
                controller: confirmPasswordCtrl,
                hint: "Confirm New Password",
                icon: Icons.lock_reset_outlined,
                isPass: true,
                obscure: hide2,
                onToggle: () => setState(() => hide2 = !hide2),
              ),

              const SizedBox(height: 30),

              // --- RESET BUTTON ---
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _handlePasswordReset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandOrange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 5,
                    shadowColor: brandOrange.withOpacity(0.4),
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "CHANGE PASSWORD",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget for attractive inputs
  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPass = false,
    bool obscure = false,
    VoidCallback? onToggle,
    TextInputType type = TextInputType.text,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: type,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: brandOrange),
          suffixIcon: isPass
              ? IconButton(
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: onToggle,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 20,
          ),
        ),
      ),
    );
  }

  Future<void> _handlePasswordReset() async {
    // 1. Validation
    if (usernameCtrl.text.isEmpty ||
        phoneCtrl.text.isEmpty ||
        newPasswordCtrl.text.isEmpty) {
      _showSnack("Please fill in all fields", Colors.redAccent);
      return;
    }

    if (newPasswordCtrl.text != confirmPasswordCtrl.text) {
      _showSnack("Passwords do not match", Colors.redAccent);
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await ApiService.post(
        Uri.parse("$baseUrl/forgot_password"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": usernameCtrl.text.trim(),
          "ph_no": phoneCtrl.text.trim(),
          "new_password": newPasswordCtrl.text.trim(),
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data["status"] == true) {
        _showSnack(data["message"] ?? "Success!", Colors.green);
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.pop(context);
        });
      } else {
        _showSnack(data["message"] ?? "Failed to reset password", brandDark);
      }
    } catch (e) {
      _showSnack("Connection Error. Check Server.", brandDark);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
