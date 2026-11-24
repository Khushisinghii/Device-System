import 'package:flutter/material.dart';

// Import all pages
import '../pages/auth/forgot_password.dart';
import '../pages/auth/loading_page.dart';
import '../pages/auth/login_page.dart';
import '../pages/auth/signup_page.dart';
import '../pages/dashboard/admin_dashboard.dart';
import '../pages/dashboard/alerts_page.dart';
import '../pages/dashboard/user_dashboard.dart';
import '../pages/dashboard/user_home_page.dart';
import '../pages/geofence/add_zone_page.dart';
import '../pages/geofence/geofence_page.dart';
import '../pages/history/history_page.dart';
import '../pages/live_tracking/map_page.dart';
import '../pages/profile/device_info_page.dart';
import '../pages/profile/edit_profile_page.dart';
import '../pages/profile/profile_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/settings/sos_page.dart';

class AppRouter {
  // Define Route Names
  static const String login = '/';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgotPassword';
  static const String loading = '/loading';

  static const String adminDashboard = '/adminDashboard';
  static const String userDashboard = '/userDashboard';
  static const String userHome = '/userHome';
  static const String alerts = '/alerts';

  static const String map = '/map';
  static const String history = '/history';

  static const String geofence = '/geofence';
  static const String addZone = '/addZone';

  static const String profile = '/profile';
  static const String editProfile = '/editProfile';
  static const String deviceInfo = '/deviceInfo';

  static const String settings = '/settings';
  static const String sos = '/sos';

  static Route<dynamic> generateRoute(RouteSettings routeSettings) {
    // Parse arguments safely
    final args = routeSettings.arguments as Map<String, dynamic>? ?? {};

    switch (routeSettings.name) {
      // -- AUTH --
      case login:
        return MaterialPageRoute(builder: (_) => const LoginPage());
      case signup:
        return MaterialPageRoute(builder: (_) => const SignupPage());
      case forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordPage());
      case loading:
        return MaterialPageRoute(
          builder: (_) => LoadingPage(
            role: args['role'] as String? ?? '',
            userId: args['userId'] as int? ?? 0,
          ),
        );

      // -- DASHBOARDS --
      case adminDashboard:
        return MaterialPageRoute(builder: (_) => const AdminDashboard());
      case userDashboard:
        return MaterialPageRoute(
          builder: (_) => UserDashboard(
            userId: args['userId'] as int? ?? 0,
            initialData: args['initialData'],
          ),
        );
      case userHome:
        return MaterialPageRoute(
          builder: (_) => UserHomePage(
            userId: args['userId'] as int? ?? 0,
            initialDashboardData: args['initialDashboardData'],
          ),
        );
      case alerts:
        return MaterialPageRoute(builder: (_) => const AlertsPage());

      // -- TRACKING & HISTORY --
      case map:
        return MaterialPageRoute(
          builder: (_) => MapPage(userId: args['userId'] as int? ?? 0),
        );
      case history:
        return MaterialPageRoute(
          builder: (_) => HistoryPage(userId: args['userId'] as int? ?? 0),
        );

      // -- GEOFENCE --
      case geofence:
        return MaterialPageRoute(builder: (_) => const GeofencePage());
      case addZone:
        return MaterialPageRoute(
          builder: (_) => AddZonePage(editZone: args['editZone']),
        );

      // -- PROFILE --
      case profile:
        return MaterialPageRoute(
          builder: (_) => ProfilePage(userId: args['userId'] as int? ?? 0),
        );
      case editProfile:
        return MaterialPageRoute(
          builder: (_) => EditProfilePage(
            userId: args['userId'] as int? ?? 0,
            currentData: args['currentData'] as Map<String, dynamic>? ?? {},
          ),
        );
      case deviceInfo:
        return MaterialPageRoute(
          builder: (_) => DeviceInfoPage(userId: args['userId'] as int? ?? 0),
        );

      // -- SETTINGS & SOS --
      case settings:
        return MaterialPageRoute(
          builder: (_) => SettingsPage(userId: args['userId'] as int? ?? 0),
        );
      case sos:
        return MaterialPageRoute(
          builder: (_) => SosPage(userId: args['userId'] as int? ?? 0),
        );

      // -- FALLBACK --
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(
              child: Text('No route defined for ${routeSettings.name}'),
            ),
          ),
        );
    }
  }
}

class ApiRoutes {
  static const String baseUrl =
      'https://ireland-calculations-chair-unfortunately.trycloudflare.com';

  // -- AUTH --
  static const String login = '$baseUrl/login';
  static const String signup = '$baseUrl/signup';
  static const String forgotPassword = '$baseUrl/forgot_password';

  // -- USERS --
  static String userDashboard(int userId) => '$baseUrl/user_dashboard/$userId';
  static String userProfile(int userId) => '$baseUrl/users/$userId';
  static const String updateProfile = '$baseUrl/update_profile';
  static String userSettings(int userId) => '$baseUrl/users/$userId/settings';

  // -- ADMIN --
  static const String usersCount = '$baseUrl/users/count';
  static const String allUsers = '$baseUrl/users';

  // -- NOTIFICATIONS --
  static String notifications(int userId) => '$baseUrl/notifications/$userId';
  static const String deleteNotifications = '$baseUrl/notifications/delete';

  // -- GEOFENCE --
  static String geofences(int userId) => '$baseUrl/geofences/$userId';
  static String geofenceZone(int zoneId) => '$baseUrl/geofences/$zoneId';

  // -- TRACKING & HISTORY --
  static String locationHistory(int userId, String date) =>
      '$baseUrl/location_history/$userId?date=$date';

  // -- SOS & DEVICE --
  static String sos(int userId) => '$baseUrl/sos/$userId';
}
