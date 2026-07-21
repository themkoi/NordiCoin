import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'data.dart';
import 'pages/ble_permission.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive init
  await Hive.initFlutter();
  Hive.registerAdapter(ActionTypeAdapter());
  Hive.registerAdapter(OnAppDeviceAdapter());
  Hive.registerAdapter(DeviceAdapter());
  Hive.registerAdapter(SettingsAdapter());
  await Hive.openBox('devices');
  await Hive.openBox('settings');

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

// Manages bluetooth permissions -> main page
class BleGateWrapper extends StatefulWidget {
  const BleGateWrapper({super.key});

  @override
  State<BleGateWrapper> createState() => _BleGateWrapperState();
}

class _BleGateWrapperState extends State<BleGateWrapper> {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  bool _showMain = false;

  late StreamSubscription<BluetoothAdapterState> _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _adapterStateSubscription.cancel();
    super.dispose();
  }

  void _onBluetoothReady() {
    setState(() {
      _showMain = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_adapterState == BluetoothAdapterState.on || _showMain) {
      return const MyHomePage();
    }
    return BlePermissionGate(onBluetoothReady: _onBluetoothReady);
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [const StatusPage(), const SettingsPage()];

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
        onPressed: () {},
        tooltip: 'Action',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class StatusPage extends StatelessWidget {
  const StatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Status', style: TextStyle(fontSize: 24)));
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Settings (Coming Soon)', style: TextStyle(fontSize: 24)),
    );
  }
}
