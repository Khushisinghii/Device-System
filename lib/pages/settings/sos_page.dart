import 'dart:convert';
import '../../core/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/app_dialogs.dart';
import '../../core/services/mqtt_service.dart';

class SosPage extends StatefulWidget {
  final int userId;
  const SosPage({super.key, required this.userId});

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  static const Color _bg = Color(0xFF0D0F11);
  static const Color _card = Color(0xFF1A1D21);
  static const Color _orange = Color(0xFFFF6600);

  // Contacts
  String? _imei;
  final MqttService _mqttService = MqttService();
  bool _isSyncing = false;

  final Map<String, Map<String, String>> _contacts = {};

  final Map<String, String> _contactLabels = {
    'n1': 'Emergency SOS Number',
    'n2': 'Parent Num 1',
    'n3': 'Parent Num 2',
  };

  final Map<String, IconData> _contactIcons = {
    'n1': Icons.local_hospital_rounded,
    'n2': Icons.family_restroom_rounded,
    'n3': Icons.family_restroom_rounded,
  };

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final res = await ApiService.get(
        Uri.parse(
          'https://huntington-ware-seasons-first.trycloudflare.com/user/sos/${widget.userId}',
        ),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        setState(() {
          _imei = data['imei'];
          _contacts.clear();
          if (data['sos_n1_number'] != null &&
              data['sos_n1_number'].toString().isNotEmpty) {
            _contacts['n1'] = {
              'name': data['sos_n1_name'] ?? '',
              'number': data['sos_n1_number'],
            };
          }
          if (data['sos_n2_number'] != null &&
              data['sos_n2_number'].toString().isNotEmpty) {
            _contacts['n2'] = {
              'name': data['sos_n2_name'] ?? '',
              'number': data['sos_n2_number'],
            };
          }
          if (data['sos_n3_number'] != null &&
              data['sos_n3_number'].toString().isNotEmpty) {
            _contacts['n3'] = {
              'name': data['sos_n3_name'] ?? '',
              'number': data['sos_n3_number'],
            };
          }
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _saveContacts() async {
    try {
      final payload = {
        'sos_n1_name': _contacts['n1']?['name'] ?? '',
        'sos_n1_number': _contacts['n1']?['number'] ?? '',
        'sos_n2_name': _contacts['n2']?['name'] ?? '',
        'sos_n2_number': _contacts['n2']?['number'] ?? '',
        'sos_n3_name': _contacts['n3']?['name'] ?? '',
        'sos_n3_number': _contacts['n3']?['number'] ?? '',
      };
      await ApiService.post(
        Uri.parse(
          'https://huntington-ware-seasons-first.trycloudflare.com/user/sos/${widget.userId}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _callContact(String number) async {
    final cleaned = number.replaceAll(" ", "");
    final uri = Uri.parse("tel:$cleaned");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _updateDevice() async {
    setState(() => _isSyncing = true);

    // 1. Check if device is ONLINE before proceeding
    try {
      final res = await ApiService.get(
        Uri.parse(
          'https://huntington-ware-seasons-first.trycloudflare.com/user_dashboard/${widget.userId}',
        ),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        final String status =
            data['status']?.toString().toUpperCase() ?? 'OFFLINE';
        if (status != 'ONLINE') {
          setState(() => _isSyncing = false);
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: _card,
                title: const Text(
                  "Device Offline",
                  style: TextStyle(color: Colors.orange),
                ),
                content: const Text(
                  "try to later online",
                  style: TextStyle(color: Colors.white),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("OK", style: TextStyle(color: _orange)),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Failed to check status: $e");
      // Proceed or fail? If we can't check, we should probably assume offline or show an error.
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to connect to server.")),
      );
      return;
    }

    Map<String, dynamic> payload = {"ref": "sos_num"};
    if (_contacts['n1'] != null) payload['sos_n1'] = _contacts['n1']!['number'];
    if (_contacts['n2'] != null) payload['sos_n2'] = _contacts['n2']!['number'];
    if (_contacts['n3'] != null) payload['sos_n3'] = _contacts['n3']!['number'];

    // If there is only the "ref" key (size 1), it means there are no numbers to update
    if (payload.length == 1) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No numbers to update.")));
      return;
    }

    // Using GPRS/GPS001 as specified
    String topic = "GPRS/GPS001";

    bool success = await _mqttService.sendAndAcknowledge(
      topic,
      payload,
      const Duration(seconds: 20),
    );

    setState(() => _isSyncing = false);

    if (success) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _card,
            title: const Text("Success", style: TextStyle(color: Colors.green)),
            content: const Text(
              "Device Updated Successfully!",
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("OK", style: TextStyle(color: _orange)),
              ),
            ],
          ),
        );
      }
    } else {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _card,
            title: const Text(
              "Timeout",
              style: TextStyle(color: Colors.orange),
            ),
            content: const Text(
              "try again later",
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("OK", style: TextStyle(color: _orange)),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showContactDialog({
    required String nLabel,
    String? existingName,
    String? existingNumber,
  }) {
    final nameCtrl = TextEditingController(text: existingName);
    final numCtrl = TextEditingController(text: existingNumber);
    final isEditing = existingNumber != null;
    final titleLabel = _contactLabels[nLabel]!;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isEditing
                      ? Icons.edit_rounded
                      : Icons.person_add_alt_1_rounded,
                  color: _orange,
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isEditing ? "Edit $titleLabel" : "Add $titleLabel",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _dialogInput(nameCtrl, "Contact Name", Icons.person_outline),
              const SizedBox(height: 12),
              _dialogInput(
                numCtrl,
                "Phone Number",
                Icons.phone_outlined,
                type: TextInputType.phone,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _orange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      onPressed: () {
                        if (nameCtrl.text.isNotEmpty &&
                            numCtrl.text.isNotEmpty) {
                          setState(() {
                            _contacts[nLabel] = {
                              "name": nameCtrl.text,
                              "number": numCtrl.text,
                            };
                          });
                          _saveContacts();
                          Navigator.pop(ctx);
                        }
                      },
                      child: Text(
                        isEditing ? "Save" : "Add",
                        style: const TextStyle(
                          color: Colors.white,
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
      ),
    );
  }

  Widget _dialogInput(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType type = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: _orange, size: 18),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildContactCard(String nLabel) {
    final contact = _contacts[nLabel];
    final bool hasContact = contact != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_contactIcons[nLabel], color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                _contactLabels[nLabel]!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (hasContact) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact["name"]!,
                        style: const TextStyle(
                          color: _orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contact["number"]!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _callContact(contact["number"]!),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.phone_rounded,
                          color: Colors.green,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showContactDialog(
                        nLabel: nLabel,
                        existingName: contact["name"],
                        existingNumber: contact["number"],
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          color: Colors.blueAccent,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() => _contacts.remove(nLabel));
                        _saveContacts();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ] else ...[
            GestureDetector(
              onTap: () => _showContactDialog(nLabel: nLabel),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: _orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Add ${_contactLabels[nLabel]}",
                      style: TextStyle(
                        color: _orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Emergency Contacts",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              "Manage your emergency contacts here. These numbers can be quickly dialed in an emergency.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            _buildContactCard('n1'),
            _buildContactCard('n2'),
            _buildContactCard('n3'),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSyncing ? Colors.grey : _orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _isSyncing ? null : _updateDevice,
                child: _isSyncing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "Update Device",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
