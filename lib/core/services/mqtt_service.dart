import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';

class MqttService {
  final MqttServerClient _client;

  MqttService()
      : _client = MqttServerClient('iotcoimbatore.xyz', 'flutter_client_${DateTime.now().millisecondsSinceEpoch}') {
    _client.port = 1883;
    _client.logging(on: false);
    _client.keepAlivePeriod = 20;
    _client.onDisconnected = _onDisconnected;
    _client.onConnected = _onConnected;
  }

  Future<bool> connect() async {
    try {
      final connMessage = MqttConnectMessage()
          .authenticateAs('iot', '123456')
          .withWillQos(MqttQos.atLeastOnce);
      _client.connectionMessage = connMessage;

      await _client.connect();
      return _client.connectionStatus!.state == MqttConnectionState.connected;
    } catch (e) {
      _client.disconnect();
      return false;
    }
  }

  void _onConnected() {
    print('MQTT Connected');
  }

  void _onDisconnected() {
    print('MQTT Disconnected');
  }

  Future<void> sendSosUpdate(String nLabel, String number, String status) async {
    if (_client.connectionStatus?.state != MqttConnectionState.connected) {
      bool connected = await connect();
      if (!connected) return;
    }

    final payload = jsonEncode({
      nLabel: number,
      "status": status,
    });
    
    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    _client.publishMessage(
      'SOS/GPS001',
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  void disconnect() {
    _client.disconnect();
  }

  Future<bool> sendAndAcknowledge(String topic, Map<String, dynamic> payload, Duration timeout) async {
    if (_client.connectionStatus?.state != MqttConnectionState.connected) {
      bool connected = await connect();
      if (!connected) return false;
    }

    // Subscribe to the topic to listen for response
    _client.subscribe(topic, MqttQos.atLeastOnce);

    final jsonPayload = jsonEncode(payload);
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonPayload);

    _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);

    // Wait for response
    bool receivedAck = false;
    try {
      await for (final List<MqttReceivedMessage<MqttMessage>> event
          in _client.updates!.timeout(timeout)) {
        final MqttPublishMessage recMess = event[0].payload as MqttPublishMessage;
        final String message =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        if (event[0].topic == topic) {
          try {
            final data = jsonDecode(message);
            // Check if it matches {"ref":"sos_status", "response":"ok"}
            if (data["ref"] == "sos_status" && (data["response"] == "ok" || data["responce"] == "ok")) {
              receivedAck = true;
              break;
            }
          } catch (e) {
            // Not JSON or missing fields, ignore
          }
        }
      }
    } catch (e) {
      // Timeout occurred
      print("MQTT Timeout waiting for ACK on $topic: $e");
    }

    // Unsubscribe after we are done
    _client.unsubscribe(topic);

    return receivedAck;
  }
}
