import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static Future<Map<String, String>> _getHeaders([Map<String, String>? customHeaders]) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    final headers = {
      'Content-Type': 'application/json',
      ...?customHeaders,
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final finalHeaders = await _getHeaders(headers);
    return http.get(url, headers: finalHeaders);
  }

  static Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final finalHeaders = await _getHeaders(headers);
    return http.post(url, headers: finalHeaders, body: body, encoding: encoding);
  }

  static Future<http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final finalHeaders = await _getHeaders(headers);
    return http.put(url, headers: finalHeaders, body: body, encoding: encoding);
  }

  static Future<http.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final finalHeaders = await _getHeaders(headers);
    return http.delete(url, headers: finalHeaders, body: body, encoding: encoding);
  }
}
