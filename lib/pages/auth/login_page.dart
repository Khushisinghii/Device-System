import 'package:flutter/material.dart';
import 'dart:convert';
import '../../core/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../pages/auth/forgot_password.dart';
import '../../pages/auth/loading_page.dart';
import '../../widgets/app_dialogs.dart';
import '../../core/services/firebase_service.dart';
import '../../pages/auth/signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool _isLoading = false;

  // Colors based on your image
  final Color brandOrange = const Color(0xFFFF6600);
  final Color brandDark = const Color(0xFF1A1A1B);
  final Color lightGrey = const Color(0xFFF5F5F5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // --- Top Left Orange Decoration ---
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: brandOrange,
                shape: BoxShape.circle,
              ),
            ),
          ),

          // --- Bottom Right Decorations ---
          Positioned(
            bottom: -80,
            right: -20,
            child: Transform.rotate(
              angle: -0.2,
              child: Container(
                width: 300,
                height: 200,
                decoration: BoxDecoration(
                  color: brandOrange,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(150),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Transform.rotate(
              angle: -0.1,
              child: Container(
                width: 250,
                height: 150,
                decoration: BoxDecoration(
                  color: brandDark,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(150),
                  ),
                ),
              ),
            ),
          ),

          // --- Main Content ---
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 1. Logo (Replace with your actual image asset)
                    Image.asset(
                      'assets/logo.png', // Ensure you add this to pubspec.yaml
                      height: 200,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.map,
                        size: 100,
                        color: Colors.orange,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 2. Welcome Text
                    const Text(
                      "Welcome Back",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "Login to continue",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // 3. Username Field
                    Container(
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
                        controller: usernameController,
                        decoration: InputDecoration(
                          hintText: "Username",
                          prefixIcon: Icon(Icons.person, color: brandOrange),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 4. Password Field
                    Container(
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
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          hintText: "Password",
                          prefixIcon: Icon(Icons.lock, color: brandOrange),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(
                              () => obscurePassword = !obscurePassword,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                      ),
                    ),

                    // 5. Forgot Password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordPage(),
                            ),
                          );
                        },
                        child: Text(
                          "Forgot Password?",
                          style: TextStyle(
                            color: brandOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 6. Login Button with Gradient
                    Container(
                      width: double.infinity,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(
                          colors: [brandOrange, const Color(0xFFFF8800)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: brandOrange.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                if (usernameController.text.trim().isEmpty ||
                                    passwordController.text.trim().isEmpty) {
                                  AppDialogs.showError(
                                    context,
                                    title: "Missing Fields",
                                    message:
                                        "Please enter username and password.",
                                  );
                                  return;
                                }
                                setState(() => _isLoading = true);
                                try {
                                  // Cloudflare tunnel requires these headers to bypass
                                  // the browser challenge / interstitial page
                                  final headers = {
                                    "Content-Type": "application/json",
                                    "Accept": "application/json",
                                    "CF-Access-Client-Id": "bypass",
                                    "ngrok-skip-browser-warning": "true",
                                  };

                                  http.Response response;
                                  try {
                                    response = await ApiService.post(
                                          Uri.parse(
                                            "https://huntington-ware-seasons-first.trycloudflare.com/login",
                                          ),
                                          headers: headers,
                                          body: jsonEncode({
                                            "username": usernameController.text
                                                .trim(),
                                            "password": passwordController.text
                                                .trim(),
                                          }),
                                        )
                                        .timeout(const Duration(seconds: 20));
                                  } catch (e) {
                                    if (!mounted) return;
                                    AppDialogs.showError(
                                      context,
                                      title: "Network Error",
                                      message:
                                          "Cannot reach server. Make sure your phone has internet access.\n\nError: $e",
                                    );
                                    return;
                                  }

                                  if (!mounted) return;

                                  debugPrint(
                                    "Login status: ${response.statusCode}",
                                  );
                                  debugPrint(
                                    "Login body: ${response.body.substring(0, response.body.length.clamp(0, 300))}",
                                  );

                                  // Check if Cloudflare returned an HTML challenge page
                                  if (response.body.trim().startsWith('<')) {
                                    AppDialogs.showError(
                                      context,
                                      title: "Tunnel Error",
                                      message:
                                          "The server tunnel returned an unexpected page. Please wait a moment and try again.",
                                    );
                                    return;
                                  }

                                  Map<String, dynamic> data;
                                  try {
                                    data = jsonDecode(response.body);
                                  } catch (e) {
                                    AppDialogs.showError(
                                      context,
                                      title: "Response Error",
                                      message:
                                          "Server returned an unexpected response (status ${response.statusCode}). Please try again.",
                                    );
                                    return;
                                  }

                                  if (data["status"] == true) {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    if (data["token"] != null) {
                                      await prefs.setString("jwt_token", data["token"]);
                                    }
                                    await prefs.setBool("isLoggedIn", true);
                                    await prefs.setString(
                                      "role",
                                      data["user"]["role"],
                                    );
                                    await prefs.setInt(
                                      "userId",
                                      data["user"]["id"],
                                    );
                                    FcmService.updateTokenOnServer(
                                      data["user"]["id"],
                                    );
                                    if (!mounted) return;
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => LoadingPage(
                                          role: data["user"]["role"],
                                          userId: data["user"]["id"],
                                        ),
                                      ),
                                    );
                                  } else {
                                    AppDialogs.showError(
                                      context,
                                      title: "Login Failed",
                                      message:
                                          data["message"] ??
                                          "Invalid username or password.",
                                    );
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  AppDialogs.showError(
                                    context,
                                    title: "Error",
                                    message: "An unexpected error occurred: $e",
                                  );
                                } finally {
                                  if (mounted)
                                    setState(() => _isLoading = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                "LOGIN",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // 7. Divider "OR"
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: Text(
                            "OR",
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                      ],
                    ),

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SignupPage(),
                              ),
                            );
                          },
                          child: Text(
                            "Sign Up",
                            style: TextStyle(
                              color: brandOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
