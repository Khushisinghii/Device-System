import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static Future<Map<String, String>> _getHeaders([Map<String, String>? customHeaders]) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    final headers = {
      'Content-Type': 'application/json',
      ...?customHeaders,
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      debugPrint("⚠️ ApiService: Missing jwt_token in SharedPreferences!");
    }

    return headers;
  }

  static Future<void> _handleResponse(http.Response response) async {
    if (response.statusCode == 401) {
      debugPrint("⚠️ ApiService 401: Unauthorized / Missing token. Resetting login session.");
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final finalHeaders = await _getHeaders(headers);
    final res = await http.get(url, headers: finalHeaders);
    await _handleResponse(res);
    return res;
  }

  static Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final finalHeaders = await _getHeaders(headers);
    final res = await http.post(url, headers: finalHeaders, body: body, encoding: encoding);
    await _handleResponse(res);
    return res;
  }

  static Future<http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final finalHeaders = await _getHeaders(headers);
    final res = await http.put(url, headers: finalHeaders, body: body, encoding: encoding);
    await _handleResponse(res);
    return res;
  }

  static Future<http.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final finalHeaders = await _getHeaders(headers);
    final res = await http.delete(url, headers: finalHeaders, body: body, encoding: encoding);
    await _handleResponse(res);
    return res;
  }
}
