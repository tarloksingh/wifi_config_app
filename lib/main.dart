import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wi-Fi Configurator',
      home: WiFiConfigPage(),
    );
  }
}

class WiFiConfigPage extends StatefulWidget {
  @override
  _WiFiConfigPageState createState() => _WiFiConfigPageState();
}

class _WiFiConfigPageState extends State<WiFiConfigPage> {
  final TextEditingController _passwordController = TextEditingController();
  BluetoothDevice? _piDevice;
  BluetoothCharacteristic? _writeChar;
  final String targetName = "raspberrypi Remote.It Onboard"; // Pi's BLE name
  final String wifiListCharUUID = "12345678-1234-5678-1234-56789abcdef1";
  final String credentialsCharUUID = "12345678-1234-5678-1234-56789abcdef2";

  List<String> _availableNetworks = [];
  String? _selectedNetwork;
  String? _currentPhoneSSID;

  @override
  void initState() {
    super.initState();
    _getCurrentWiFiSSID();
  }

  Future<void> _getCurrentWiFiSSID() async {
    final info = NetworkInfo();
    String? ssid = await info.getWifiName();
    setState(() {
      _currentPhoneSSID = ssid;
    });
    print("Current Phone Wi-Fi: $_currentPhoneSSID");
  }

  void _scanForDevice() async {
    FlutterBlue flutterBlue = FlutterBlue.instance;

    if (await flutterBlue.isScanning.first) {
      print("Stopping ongoing scan...");
      await flutterBlue.stopScan();
      await Future.delayed(Duration(seconds: 1));
    }

    print("Starting BLE scan...");
    flutterBlue.startScan(timeout: Duration(seconds: 5));

    flutterBlue.scanResults.listen((results) async {
      for (ScanResult r in results) {
        print('Found device: ${r.device.name} - ${r.device.id}');
        if (r.device.name == targetName) {
          setState(() {
            _piDevice = r.device;
          });

          print("Stopping scan and attempting to connect...");
          await flutterBlue.stopScan();
          await Future.delayed(Duration(seconds: 2));
          _connectToDevice();
          break;
        }
      }
    });
  }
void _connectToDevice() async {
  if (_piDevice == null) return;

  int maxAttempts = 3;
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      print("Attempt $attempt: Connecting to ${_piDevice!.id}");
      await _piDevice!.connect(timeout: Duration(seconds: 10));
      print("Connected successfully!");

      List<BluetoothService> services = await _piDevice!.discoverServices();

      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString().toLowerCase() == wifiListCharUUID) {
            _listenForWifiNetworks(characteristic);
          } else if (characteristic.uuid.toString().toLowerCase() == credentialsCharUUID) {
            _writeChar = characteristic;
          }
        }
      }
      return; // Exit loop if connection is successful
    } catch (e) {
      print("Failed to connect: $e");
      if (attempt < maxAttempts) {
        print("Retrying in 5 seconds... (${maxAttempts - attempt} attempts left)");
        await Future.delayed(Duration(seconds: 5));
      } else {
        print("All connection attempts failed.");
      }
    }
  }
}


  void _listenForWifiNetworks(BluetoothCharacteristic characteristic) async {
    await characteristic.setNotifyValue(true);
    characteristic.value.listen((value) {
      try {
        String jsonString = utf8.decode(value);
        print("Raw JSON from Pi: $jsonString");

        if (jsonString.isEmpty) {
          throw FormatException("Received empty response");
        }

        List<String> wifiList = List<String>.from(json.decode(jsonString));

        setState(() {
          _availableNetworks = wifiList;
        });

        print("Received Wi-Fi networks: $_availableNetworks");
      } catch (e) {
        print("Error parsing Wi-Fi networks: $e");
        setState(() {
          _availableNetworks = ["Failed to load Wi-Fi networks"];
        });
      }
    });
  }

  void _sendCredentials() async {
    if (_writeChar == null || _selectedNetwork == null) return;
    String data = "$_selectedNetwork,${_passwordController.text}";
    await _writeChar!.write(utf8.encode(data));
    print("Sent credentials: $data");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Wi-Fi Configurator')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Current Phone Wi-Fi: $_currentPhoneSSID"),
            ElevatedButton(
              onPressed: _scanForDevice,
              child: Text('Scan for Pi'),
            ),
            DropdownButton<String>(
              hint: Text("Select Wi-Fi Network"),
              value: _selectedNetwork,
              onChanged: (String? newValue) {
                setState(() {
                  _selectedNetwork = newValue;
                });
              },
              items: _availableNetworks.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: 'Wi-Fi Password'),
              obscureText: true,
            ),
            ElevatedButton(
              onPressed: _sendCredentials,
              child: Text('Send Credentials'),
            ),
          ],
        ),
      ),
    );
  }
}
