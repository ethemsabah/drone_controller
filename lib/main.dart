import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drone Kontrol',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const DroneControlPage(),
    );
  }
}

class DroneControlPage extends StatefulWidget {
  const DroneControlPage({super.key});

  @override
  State<DroneControlPage> createState() => _DroneControlPageState();
}

class _DroneControlPageState extends State<DroneControlPage> {
  final List<int> motorValues = List.filled(4, 0);
  final List<Timer?> motorTimers = List.filled(4, null);
  BluetoothDevice? selectedDevice;
  IO.Socket? socket;
  String connectionStatus = 'Bağlantı yok';
  bool isBluetoothConnected = false;
  bool isWifiConnected = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Önce konum izni iste
    var locationStatus = await Permission.location.request();
    if (locationStatus.isDenied) {
      setState(() {
        connectionStatus = 'Konum izni gerekli';
      });
      return;
    }

    // Sonra Bluetooth izinlerini iste
    var bluetoothStatus = await Permission.bluetooth.request();
    var bluetoothScanStatus = await Permission.bluetoothScan.request();
    var bluetoothConnectStatus = await Permission.bluetoothConnect.request();

    if (bluetoothStatus.isDenied || bluetoothScanStatus.isDenied || bluetoothConnectStatus.isDenied) {
      setState(() {
        connectionStatus = 'Bluetooth izinleri gerekli';
      });
    }
  }

  Future<void> _showConnectionDialog(bool isBluetooth) async {
    if (isBluetooth) {
      try {
        if (await FlutterBluePlus.isSupported == false) {
          setState(() {
            connectionStatus = 'Bluetooth desteklenmiyor';
          });
          return;
        }

        // Konum servislerinin açık olduğundan emin ol
        if (await Permission.location.isDenied) {
          setState(() {
            connectionStatus = 'Konum servisleri gerekli';
          });
          return;
        }

        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
        
        if (!mounted) return;

        // İlk bulunan cihaza bağlan
        FlutterBluePlus.scanResults.listen((results) {
          if (results.isNotEmpty) {
            final device = results.first.device;
            device.connect().then((_) {
              setState(() {
                selectedDevice = device;
                isBluetoothConnected = true;
                connectionStatus = 'Bluetooth bağlandı: ${device.platformName}';
              });
            });
          }
        });

      } catch (e) {
        setState(() {
          connectionStatus = 'Bluetooth bağlantı hatası: $e';
        });
      }
    } else {
      try {
        final info = NetworkInfo();
        final wifiName = await info.getWifiName();
        
        if (!mounted) return;

        // Varsayılan IP adresi ile bağlanmayı dene
        const defaultIp = '192.168.1.100';
        socket = IO.io('http://$defaultIp:3000', <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': false,
        });

        socket!.connect();
        socket!.onConnect((_) {
          setState(() {
            isWifiConnected = true;
            connectionStatus = 'WiFi bağlandı: $defaultIp';
          });
        });

        socket!.onDisconnect((_) {
          setState(() {
            isWifiConnected = false;
            connectionStatus = 'WiFi bağlantısı kesildi';
          });
        });

      } catch (e) {
        setState(() {
          connectionStatus = 'WiFi bağlantı hatası: $e';
        });
      }
    }
  }

  void _startMotorTimer(int motorIndex) {
    motorTimers[motorIndex]?.cancel();
    
    motorTimers[motorIndex] = Timer.periodic(const Duration(milliseconds: 2), (timer) {
      if (motorValues[motorIndex] > 0) {
        setState(() {
          motorValues[motorIndex] = (motorValues[motorIndex] - 1).clamp(0, 255);
          _sendMotorValues();
        });
      } else {
        timer.cancel();
        motorTimers[motorIndex] = null;
      }
    });
  }

  void _stopMotorTimer(int motorIndex) {
    motorTimers[motorIndex]?.cancel();
    motorTimers[motorIndex] = null;
  }

  Future<void> _sendMotorValues() async {
    final data = motorValues.join(',');
    if (isBluetoothConnected && selectedDevice != null) {
      try {
        final services = await selectedDevice!.discoverServices();
        for (var service in services) {
          for (var characteristic in service.characteristics) {
            if (characteristic.properties.write) {
              await characteristic.write(data.codeUnits);
              break;
            }
          }
        }
      } catch (e) {
        setState(() {
          connectionStatus = 'Veri gönderme hatası: $e';
        });
      }
    }
    if (isWifiConnected && socket != null) {
      socket!.emit('motor_values', data);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final motorWidth = (screenSize.width - 32) / 4; // 4 motor için eşit genişlik
    final motorHeight = screenSize.height * 0.7; // Ekran yüksekliğinin %70'i

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drone Kontrol'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.bluetooth,
              color: isBluetoothConnected ? Colors.green : Colors.grey,
              size: 28,
            ),
            onPressed: () {
              if (isBluetoothConnected) {
                selectedDevice?.disconnect();
                setState(() {
                  isBluetoothConnected = false;
                  connectionStatus = 'Bluetooth bağlantısı kesildi';
                });
              } else {
                _showConnectionDialog(true);
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.wifi,
              color: isWifiConnected ? Colors.green : Colors.grey,
              size: 28,
            ),
            onPressed: () {
              if (isWifiConnected) {
                socket?.disconnect();
                setState(() {
                  isWifiConnected = false;
                  connectionStatus = 'WiFi bağlantısı kesildi';
                });
              } else {
                _showConnectionDialog(false);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                connectionStatus,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (index) {
                  return SizedBox(
                    width: motorWidth,
                    height: motorHeight,
                    child: Card(
                      margin: const EdgeInsets.all(8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Motor ${index + 1}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 16,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 10,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 20,
                                    ),
                                    activeTrackColor: Colors.blue,
                                    inactiveTrackColor: Colors.grey[300],
                                    thumbColor: Colors.blue,
                                    overlayColor: Colors.blue.withOpacity(0.2),
                                  ),
                                  child: Slider(
                                    value: motorValues[index].toDouble(),
                                    min: 0,
                                    max: 255,
                                    divisions: 255,
                                    label: motorValues[index].toString(),
                                    onChanged: (value) {
                                      setState(() {
                                        motorValues[index] = value.toInt();
                                        _sendMotorValues();
                                      });
                                    },
                                    onChangeStart: (_) {
                                      _stopMotorTimer(index);
                                    },
                                    onChangeEnd: (_) {
                                      _startMotorTimer(index);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Değer: ${motorValues[index]}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (var timer in motorTimers) {
      timer?.cancel();
    }
    selectedDevice?.disconnect();
    socket?.disconnect();
    super.dispose();
  }
}
