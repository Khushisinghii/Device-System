import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/firebase_service.dart';
import 'core/constants/firebase_options.dart';
import 'core/services/notification_helper.dart';
import 'routes/app_router.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/loading_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _initialized = false;
  bool _isLoggedIn = false;
  String _role = "";
  int _userId = 0;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      // 1. Initialize Firebase Options
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 2. Fetch SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final bool loggedIn = prefs.getBool("isLoggedIn") ?? false;
      final String userRole = prefs.getString("role") ?? "";
      final int id = prefs.getInt("userId") ?? 0;

      if (loggedIn && id != 0) {
        FcmService.updateTokenOnServer(id);
      }

      // 3. Initialize Notification services with a brief delay
      Future.delayed(const Duration(milliseconds: 500), () async {
        try {
          await FcmService.initialize();
          await NotificationHelper.init();
        } catch (e) {
          debugPrint("Error initializing notifications: $e");
        }
      });

      if (mounted) {
        setState(() {
          _isLoggedIn = loggedIn;
          _role = userRole;
          _userId = id;
          _initialized = true;
        });
      }
    } catch (e) {
      debugPrint("Startup Error: $e");
      // Still show the login page as fallback instead of black screen
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      // Show a premium dark screen with simple loader during splash-to-app transition
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF0D0F11),
          body: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6600)),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _isLoggedIn
          ? LoadingPage(
              role: _role,
              userId: _userId,
            )
          : const LoginPage(),
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
