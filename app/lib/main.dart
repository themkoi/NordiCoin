import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'consts.dart';
import 'data.dart';
import 'pages/ble_permission.dart';
import 'pages/scan.dart';
import 'pages/settings.dart';
import 'pages/status_devices.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive init
  await Hive.initFlutter();
  Hive.registerAdapter(ActionTypeAdapter());
  Hive.registerAdapter(OnAppDeviceAdapter());
  Hive.registerAdapter(DeviceAdapter());
  Hive.registerAdapter(SettingsAdapter());
  final devicesBox = await Hive.openBox(hiveBoxDevices);
  final settingsBox = await Hive.openBox(hiveBoxSettings);

  if (settingsBox.isEmpty) {
    final defaultSettings = Settings(defaultDeviceSettings: OnAppDevice());
    await settingsBox.put(0, defaultSettings);
  }

  print('Hive boxes opened:');
  print(
    '$hiveBoxDevices: ${devicesBox.length} items, keys=${devicesBox.keys.toList()}',
  );
  print(
    '$hiveBoxSettings: ${settingsBox.length} items, keys=${settingsBox.keys.toList()}',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NordiCoin',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigoAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BleGateWrapper(),
    );
  }
}

// Gate: shows BlePermissionGate until all requirements are met, then MyHomePage
class BleGateWrapper extends StatefulWidget {
  const BleGateWrapper({super.key});

  @override
  State<BleGateWrapper> createState() => _BleGateWrapperState();
}

class _BleGateWrapperState extends State<BleGateWrapper> {
  bool _allGranted = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  // Similar to _checkPermissions in ble_permission
  Future<void> _check() async {
    final state = await FlutterBluePlus.adapterState.first;
    final fine = await Permission.location.isGranted;
    final bg = await Permission.locationAlways.isGranted;
    final bt = await Permission.bluetoothScan.isGranted;
    if (mounted) {
      setState(() {
        _allGranted = state == BluetoothAdapterState.on && fine && bg && bt;
      });
    }
  }

  void _onReady() {
    setState(() {
      _allGranted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_allGranted) {
      return const MyHomePage();
    }
    return BlePermissionGate(onBluetoothReady: _onReady);
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [const StatusDevicesPage(), const SettingsPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('NordiCoin', style: TextStyle(fontSize: 20)),
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        elevation: 8,
        selectedFontSize: 16,
        unselectedFontSize: 12,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
        selectedIconTheme: IconThemeData(size: 30, opacity: 1.0),
        unselectedIconTheme: IconThemeData(size: 24, opacity: 0.6),
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.device_hub),
            label: 'Status',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => const ScanScreen()));
        },
        tooltip: 'Scan Devices',
        child: const Icon(Icons.add),
      ),
    );
  }
}


