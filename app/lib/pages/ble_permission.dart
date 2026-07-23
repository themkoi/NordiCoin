import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/snackbar.dart';

class BlePermissionGate extends StatefulWidget {
  const BlePermissionGate({super.key, required this.onBluetoothReady});

  final VoidCallback onBluetoothReady;

  @override
  State<BlePermissionGate> createState() => _BlePermissionGateState();
}

class _BlePermissionGateState extends State<BlePermissionGate> {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  bool _fineLocationGranted = false;
  bool _bgLocationGranted = false;
  bool _bluetoothScanGranted = false;
  bool _allGranted = false;

  late StreamSubscription<BluetoothAdapterState> _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      if (mounted) {
        setState(() {
          _allGranted = _checkAll();
        });
      }
      if (state == BluetoothAdapterState.on) {
        _checkPermissions();
      }
    });
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final fine = await Permission.location.isGranted;
    final bg = await Permission.locationAlways.isGranted;
    final bt = await Permission.bluetoothScan.isGranted;
    if (mounted) {
      setState(() {
        _fineLocationGranted = fine;
        _bgLocationGranted = bg;
        _bluetoothScanGranted = bt;
        _allGranted = _checkAll();
      });
    }
  }

  bool _checkAll() {
    return _adapterState == BluetoothAdapterState.on &&
        _fineLocationGranted &&
        _bgLocationGranted &&
        _bluetoothScanGranted;
  }

  Future<void> _requestFineLocation() async {
    final status = await Permission.location.request();
    setState(() {
      _fineLocationGranted = status.isGranted;
      _allGranted = _checkAll();
    });
    if (!status.isGranted) {
      Snackbar.show(
        SnackbarLocation.secondary,
        'Fine location permission is required for Bluetooth scanning.',
        success: false,
      );
    }
  }

  Future<void> _requestBackgroundLocation() async {
    final status = await Permission.locationAlways.request();
    setState(() {
      _bgLocationGranted = status.isGranted;
      _allGranted = _checkAll();
    });
    if (status.isPermanentlyDenied) {
      openAppSettings();
      Snackbar.show(
        SnackbarLocation.secondary,
        'Please enable "Allow all the time" in app settings.',
        success: false,
      );
    } else if (!status.isGranted) {
      Snackbar.show(
        SnackbarLocation.secondary,
        'Background location permission is required for continuous tracking.',
        success: false,
      );
    }
  }

  Future<void> _requestBluetoothScan() async {
    final status = await Permission.bluetoothScan.request();
    setState(() {
      _bluetoothScanGranted = status.isGranted;
      _allGranted = _checkAll();
    });
    if (!status.isGranted) {
      Snackbar.show(
        SnackbarLocation.secondary,
        'Bluetooth scan permission is required.',
        success: false,
      );
    }
  }

  @override
  void dispose() {
    _adapterStateSubscription.cancel();
    super.dispose();
  }

  Widget buildBluetoothOffIcon(BuildContext context) {
    return const Icon(
      Icons.bluetooth_disabled,
      size: 200.0,
      color: Colors.white54,
    );
  }

  Widget buildTitle(BuildContext context) {
    String state = _adapterState.toString().split(".").last;
    return Text(
      'Bluetooth Adapter is $state',
      style: Theme.of(
        context,
      ).primaryTextTheme.titleSmall?.copyWith(color: Colors.white),
    );
  }

  Widget buildTurnOnButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ElevatedButton(
        child: const Text('TURN ON'),
        onPressed: () async {
          try {
            // This is here because FlutterBluePlus.turnOn also request it, but the GUI later is broken otherwise
            await _requestBluetoothScan();
            await FlutterBluePlus.turnOn();
          } catch (e) {
            Snackbar.show(
              SnackbarLocation.secondary,
              prettyException("Turn On Error:", e),
              success: false,
            );
          }
        },
      ),
    );
  }

  Widget buildPermissionButton({
    required String title,
    required String message,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: Text(title),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeySecondary,
      child: Scaffold(
        backgroundColor: Colors.lightBlue,
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                buildBluetoothOffIcon(context),
                buildTitle(context),
                if (_adapterState != BluetoothAdapterState.on)
                  buildTurnOnButton(context),
                if (_adapterState == BluetoothAdapterState.on) ...[
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30.0),
                    child: Column(
                      children: [
                        if (!_bluetoothScanGranted)
                          buildPermissionButton(
                            title: 'Bluetooth Scan',
                            message:
                                'This permission is required to discover nearby Bluetooth devices.',
                            onPressed: _requestBluetoothScan,
                          ),
                        if (!_fineLocationGranted)
                          buildPermissionButton(
                            title: 'Fine Location',
                            message:
                                'This permission is required because Bluetooth scanning uses location data.',
                            onPressed: _requestFineLocation,
                          ),
                        if (!_bgLocationGranted)
                          buildPermissionButton(
                            title: 'Allow All the Time',
                            message:
                                'This permission allows the app to track your location in the background for continuous device discovery.',
                            onPressed: _requestBackgroundLocation,
                          ),
                        if (_allGranted) ...[
                          const SizedBox(height: 10),
                          const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 60,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'All permissions granted!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () {
                              widget.onBluetoothReady();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                                vertical: 12,
                              ),
                            ),
                            child: const Text('Continue'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
