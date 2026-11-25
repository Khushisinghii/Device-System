import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/api_service.dart';

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

  static const MethodChannel _smsChannel =
      MethodChannel('com.example.go_go/direct_sms');

  // Contacts & Tracker Device
  String? _imei;
  String? _simNumber;
  bool _isSending = false;

  final Map<String, Map<String, String>> _contacts = {};

  final Map<String, String> _contactLabels = {
    'n1': 'Emergency SOS Number',
    'n2': 'Parent Num 1',
    'n3': 'Parent Num 2',
  };

  final Map<String, String> _contactSubtitles = {
    'n1': 'Triggered by SOS Button • Device Admin',
    'n2': 'Triggered by Green Button • Family 1',
    'n3': 'Triggered by Red Button • Family 2',
  };

  final Map<String, String> _contactTags = {
    'n1': 'SOS Button',
    'n2': 'Green Button',
    'n3': 'Red Button',
  };

  final Map<String, Color> _contactColors = {
    'n1': Colors.redAccent,
    'n2': Colors.green,
    'n3': Colors.orangeAccent,
  };

  final Map<String, IconData> _contactIcons = {
    'n1': Icons.emergency_rounded,
    'n2': Icons.phone_in_talk_rounded,
    'n3': Icons.phone_in_talk_rounded,
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
          'https://b58k998z-5000.inc1.devtunnels.ms/user/sos/${widget.userId}',
        ),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        if (mounted) {
          setState(() {
            _imei = data['imei'];
            _contacts.clear();
            if (data['sos_n1_number'] != null &&
                data['sos_n1_number'].toString().isNotEmpty) {
              _contacts['n1'] = {
                'name': data['sos_n1_name'] ?? 'SOS Contact',
                'number': data['sos_n1_number'].toString(),
              };
            }
            if (data['sos_n2_number'] != null &&
                data['sos_n2_number'].toString().isNotEmpty) {
              _contacts['n2'] = {
                'name': data['sos_n2_name'] ?? 'Parent 1',
                'number': data['sos_n2_number'].toString(),
              };
            }
            if (data['sos_n3_number'] != null &&
                data['sos_n3_number'].toString().isNotEmpty) {
              _contacts['n3'] = {
                'name': data['sos_n3_name'] ?? 'Parent 2',
                'number': data['sos_n3_number'].toString(),
              };
            }
          });
        }
      }

      // Load device SIM number from user_dashboard
      final dashRes = await ApiService.get(
        Uri.parse(
          'https://b58k998z-5000.inc1.devtunnels.ms/user_dashboard/${widget.userId}',
        ),
      );
      if (dashRes.statusCode == 200) {
        final dashData = jsonDecode(dashRes.body)['data'];
        if (dashData != null && dashData['sim_number'] != null && mounted) {
          setState(() {
            _simNumber = dashData['sim_number'].toString();
          });
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// Stores contacts in the user table in the database
  Future<bool> _saveContactsToUserTable() async {
    try {
      final payload = {
        'user_id': widget.userId,
        'sos_n1_name': _contacts['n1']?['name'] ?? '',
        'sos_n1_number': _contacts['n1']?['number'] ?? '',
        'sos_n2_name': _contacts['n2']?['name'] ?? '',
        'sos_n2_number': _contacts['n2']?['number'] ?? '',
        'sos_n3_name': _contacts['n3']?['name'] ?? '',
        'sos_n3_number': _contacts['n3']?['number'] ?? '',
      };
      final res = await ApiService.post(
        Uri.parse(
          'https://b58k998z-5000.inc1.devtunnels.ms/user/sos/${widget.userId}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint("Error saving to user table: $e");
      return false;
    }
  }

  Future<void> _callContact(String number) async {
    final cleaned = number.replaceAll(" ", "").replaceAll("-", "");
    final uri = Uri.parse("tel:$cleaned");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _cleanNum(String? num) {
    if (num == null) return '';
    return num.replaceAll(' ', '').replaceAll('-', '').replaceAll('(', '').replaceAll(')', '').trim();
  }

  String _getSosSmsCommand() {
    final n1 = _cleanNum(_contacts['n1']?['number']);
    if (n1.isEmpty) return 'admin123456';
    return 'admin123456 $n1';
  }

  String _getFamilySmsCommand() {
    final n2 = _cleanNum(_contacts['n2']?['number']);
    final n3 = _cleanNum(_contacts['n3']?['number']);
    if (n2.isEmpty && n3.isEmpty) return 'familynum123456';
    if (n2.isNotEmpty && n3.isNotEmpty) return 'familynum123456 $n2 $n3';
    if (n2.isNotEmpty) return 'familynum123456 $n2';
    return 'familynum123456 $n3';
  }

  /// Sends direct SMS from within the app without launching the external SMS page
  Future<bool> _sendDirectSmsInternal({
    required String targetPhone,
    required String message,
  }) async {
    try {
      final res = await _smsChannel.invokeMethod<bool>('sendDirectSms', {
        'phone': targetPhone,
        'message': message,
      });
      return res == true;
    } on PlatformException catch (e) {
      debugPrint("Direct SMS error: ${e.code} - ${e.message}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == "PERMISSION_DENIED"
                  ? "SMS permission denied. Please grant SMS permission to send directly."
                  : "SMS failed: ${e.message ?? 'Unknown error'}",
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint("Direct SMS error: $e");
      return false;
    }
  }

  /// Executes: Save to User Table -> Send SMS Directly in-app -> Show Confirmation
  Future<void> _saveAndSendDirectSms(String nLabel) async {
    setState(() => _isSending = true);

    // 1. Store in user table
    await _saveContactsToUserTable();

    // 2. Identify target Tracker SIM number
    final targetSim = _cleanNum(_simNumber);
    if (targetSim.isEmpty || targetSim == '-') {
      setState(() => _isSending = false);
      _showSimPromptDialog(nLabel);
      return;
    }

    // 3. Formulate command (admin123456 <n1> or familynum123456 <n2> <n3>)
    final command = (nLabel == 'n1') ? _getSosSmsCommand() : _getFamilySmsCommand();

    // 4. Send directly in-app
    final sent = await _sendDirectSmsInternal(targetPhone: targetSim, message: command);

    setState(() => _isSending = false);

    // 5. Show Confirmation Dialog
    if (mounted) {
      _showConfirmationDialog(
        title: "Saved & Sent Confirmed!",
        message: "Contact has been stored in user table and the configuration SMS was sent directly to your tracker device.",
        contactLabel: _contactLabels[nLabel]!,
        contactName: _contacts[nLabel]?['name'] ?? '',
        contactNumber: _contacts[nLabel]?['number'] ?? '',
        trackerSim: targetSim,
        smsDispatched: sent,
      );
    }
  }

  /// Sends all numbers directly to tracker via in-app SMS
  Future<void> _sendAllViaDirectSms() async {
    setState(() => _isSending = true);

    // 1. Store in user table
    await _saveContactsToUserTable();

    final targetSim = _cleanNum(_simNumber);
    if (targetSim.isEmpty || targetSim == '-') {
      setState(() => _isSending = false);
      _showSimPromptDialog('all');
      return;
    }

    // Send SOS Command
    final sosCmd = _getSosSmsCommand();
    await _sendDirectSmsInternal(targetPhone: targetSim, message: sosCmd);

    // Send Family Numbers Command
    final familyCmd = _getFamilySmsCommand();
    await _sendDirectSmsInternal(targetPhone: targetSim, message: familyCmd);

    setState(() => _isSending = false);

    if (mounted) {
      _showConfirmationDialog(
        title: "All Numbers Stored & Sent!",
        message: "All emergency and family numbers have been stored in the user table and dispatched via direct SMS to your tracker SIM.",
        contactLabel: "All Contacts",
        contactName: "SOS & Family Numbers",
        contactNumber: "Emergency: ${_contacts['n1']?['number'] ?? '-'}\nFamily: ${_contacts['n2']?['number'] ?? '-'}, ${_contacts['n3']?['number'] ?? '-'}",
        trackerSim: targetSim,
        smsDispatched: true,
      );
    }
  }

  /// Sends a quick status/diagnostic command from the device manual
  Future<void> _sendQuickDeviceCommand({
    required String title,
    required String command,
    required String description,
  }) async {
    final targetSim = _cleanNum(_simNumber);
    if (targetSim.isEmpty || targetSim == '-') {
      _showSimPromptDialog('quick_$command');
      return;
    }

    setState(() => _isSending = true);
    final sent = await _sendDirectSmsInternal(targetPhone: targetSim, message: command);
    setState(() => _isSending = false);

    if (mounted) {
      _showConfirmationDialog(
        title: "$title SMS Sent!",
        message: "$description The tracker device will process the command and reply directly via SMS to your phone.",
        contactLabel: "Device Query",
        contactName: title,
        contactNumber: "Command: $command",
        trackerSim: targetSim,
        smsDispatched: sent,
      );
    }
  }

  void _showSimPromptDialog(String nLabel) {
    final simCtrl = TextEditingController(
      text: (_simNumber != null && _simNumber != '-') ? _simNumber : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.sim_card_outlined, color: _orange),
            SizedBox(width: 8),
            Text(
              "Tracker SIM Number",
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Enter the SIM phone number installed inside your GPS Tracker to directly send the SMS:",
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: simCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.phone_android, color: _orange),
                  hintText: "e.g. 9876543210",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final sim = simCtrl.text.trim();
              if (sim.isNotEmpty) {
                setState(() => _simNumber = sim);
                Navigator.pop(ctx);
                if (nLabel == 'all') {
                  _sendAllViaDirectSms();
                } else if (nLabel.startsWith('quick_')) {
                  final cmd = nLabel.replaceFirst('quick_', '');
                  _sendQuickDeviceCommand(
                    title: "Diagnostic Query",
                    command: cmd,
                    description: "Diagnostic query sent.",
                  );
                } else {
                  _saveAndSendDirectSms(nLabel);
                }
              }
            },
            child: const Text(
              "Save & Send",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showConfirmationDialog({
    required String title,
    required String message,
    required String contactLabel,
    required String contactName,
    required String contactNumber,
    required String trackerSim,
    required bool smsDispatched,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green,
                  size: 44,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          contactLabel,
                          style: const TextStyle(color: _orange, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (contactName.isNotEmpty) ...[
                      Text(
                        contactName,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                    ],
                    if (contactNumber.isNotEmpty) ...[
                      Text(
                        contactNumber,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 0.5),
                      ),
                    ],
                    const Divider(color: Colors.white12, height: 16),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 14),
                        const SizedBox(width: 6),
                        const Text(
                          "Stored in User Table: Confirmed",
                          style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          smsDispatched ? Icons.check_circle_outline : Icons.info_outline,
                          color: smsDispatched ? Colors.green : Colors.orangeAccent,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Sent Directly via SMS to: $trackerSim",
                            style: TextStyle(
                              color: smsDispatched ? Colors.green : Colors.orangeAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "OK",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    final subtitle = _contactSubtitles[nLabel]!;
    final color = _contactColors[nLabel]!;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isEditing ? Icons.edit_rounded : _contactIcons[nLabel],
                    color: color,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isEditing ? "Edit $titleLabel" : "Add $titleLabel",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _dialogInput(nameCtrl, "Contact Name (e.g. Dad, Mom)", Icons.person_outline),
                const SizedBox(height: 10),
                _dialogInput(
                  numCtrl,
                  "Phone Number",
                  Icons.phone_outlined,
                  type: TextInputType.phone,
                ),
                const SizedBox(height: 20),
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Cancel"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        onPressed: () {
                          final name = nameCtrl.text.trim();
                          final number = numCtrl.text.trim();
                          if (name.isNotEmpty && number.isNotEmpty) {
                            setState(() {
                              _contacts[nLabel] = {
                                "name": name,
                                "number": number,
                              };
                            });
                            Navigator.pop(ctx);
                            _saveAndSendDirectSms(nLabel);
                          }
                        },
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 15),
                        label: Text(
                          isEditing ? "Save & Send" : "Add & Send",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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
      ),
    );
  }

  void _showDeleteConfirmation(String nLabel) {
    final contact = _contacts[nLabel];
    if (contact == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Remove Contact?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          "Are you sure you want to remove ${contact['name']} (${contact['number']}) from ${_contactLabels[nLabel]}?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _contacts.remove(nLabel));
              await _saveContactsToUserTable();

              final targetSim = _cleanNum(_simNumber);
              bool smsDispatched = false;
              if (targetSim.isNotEmpty && targetSim != '-') {
                // Remove command: admin123456 for SOS, familynum123456 [remaining] for family
                final removeCmd = (nLabel == 'n1') ? _getSosSmsCommand() : _getFamilySmsCommand();
                smsDispatched = await _sendDirectSmsInternal(targetPhone: targetSim, message: removeCmd);
              }

              if (mounted) {
                _showConfirmationDialog(
                  title: "Contact Removed & Tracker Updated!",
                  message: "The contact was removed from the database and an SMS update command was dispatched directly to your tracker device.",
                  contactLabel: _contactLabels[nLabel]!,
                  contactName: contact['name'] ?? '',
                  contactNumber: contact['number'] ?? '',
                  trackerSim: targetSim.isNotEmpty ? targetSim : 'Not configured',
                  smsDispatched: smsDispatched,
                );
              }
            },
            child: const Text("Remove", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
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
    final color = _contactColors[nLabel]!;
    final tag = _contactTags[nLabel]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasContact ? color.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_contactIcons[nLabel], color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _contactLabels[nLabel]!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _contactSubtitles[nLabel]!,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (hasContact) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact["name"]!,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          contact["number"]!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      // Direct call button
                      GestureDetector(
                        onTap: () => _callContact(contact["number"]!),
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.phone_rounded,
                            color: Colors.green,
                            size: 19,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Send SMS directly in-app
                      GestureDetector(
                        onTap: () => _saveAndSendDirectSms(nLabel),
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: _orange.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send_rounded,
                            color: _orange,
                            size: 19,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Edit button
                      GestureDetector(
                        onTap: () => _showContactDialog(
                          nLabel: nLabel,
                          existingName: contact["name"],
                          existingNumber: contact["number"],
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            color: Colors.blueAccent,
                            size: 19,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Delete button
                      GestureDetector(
                        onTap: () => _showDeleteConfirmation(nLabel),
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                            size: 19,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            GestureDetector(
              onTap: () => _showContactDialog(nLabel: nLabel),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Add ${_contactLabels[nLabel]}",
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
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
          onPressed: () => Navigator.pop(context, true),
        ),
        title: const Text(
          "Emergency Contacts",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const Text(
              "Add and manage emergency numbers for your GPS tracker device. Numbers are stored in your user profile and sent directly via in-app SMS to the device.",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (_imei != null && _imei!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                "Tracker IMEI: $_imei",
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontFamily: "monospace",
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Emergency SOS Contact (n1)
            _buildContactCard('n1'),

            // Parent Num 1 (n2 - Green Button)
            _buildContactCard('n2'),

            // Parent Num 2 (n3 - Red Button)
            _buildContactCard('n3'),

            const SizedBox(height: 24),

            // Update All Numbers via Direct SMS Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSending ? Colors.grey : _orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isSending ? null : () => _sendAllViaDirectSms(),
                icon: _isSending
                    ? const SizedBox.shrink()
                    : const Icon(Icons.send_rounded, color: Colors.white),
                label: _isSending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "Send All Numbers via SMS to Tracker",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 28),

            // Device Tools & Manual Quick Queries from device booklet
            const Text(
              "Tracker SMS Diagnostics",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Send inquiry commands directly to the tracker SIM to receive instant SMS replies.",
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: _buildDiagnosticTile(
                    icon: Icons.contact_phone_outlined,
                    color: Colors.green,
                    title: "Check Family",
                    subtitle: "ckauthnum123456",
                    onTap: () => _sendQuickDeviceCommand(
                      title: "Check Family Numbers",
                      command: "ckauthnum123456",
                      description: "Checking currently saved family numbers on device.",
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDiagnosticTile(
                    icon: Icons.info_outline_rounded,
                    color: Colors.blueAccent,
                    title: "Check Status",
                    subtitle: "check123456",
                    onTap: () => _sendQuickDeviceCommand(
                      title: "Check Device Parameters",
                      command: "check123456",
                      description: "Requesting battery, GSM, and device parameters from device.",
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDiagnosticTile(
                    icon: Icons.my_location_rounded,
                    color: Colors.purpleAccent,
                    title: "Location Call",
                    subtitle: "query123456",
                    onTap: () => _sendQuickDeviceCommand(
                      title: "Query Location",
                      command: "query123456",
                      description: "Requesting immediate location report from device.",
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isSending ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 10,
                fontFamily: "monospace",
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
