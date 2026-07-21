import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BlePermissionGate extends StatefulWidget {
  const BlePermissionGate({
    super.key,
    required this.onBluetoothReady,
  });

  final VoidCallback onBluetoothReady;

  @override
  State<BlePermissionGate> createState() => _BlePermissionGateState();
}

class _BlePermissionGateState extends State<BlePermissionGate> {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  late StreamSubscription<BluetoothAdapterState> _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      if (mounted) {
        setState(() {});
      }
      // When Bluetooth turns on, notify the parent
      if (state == BluetoothAdapterState.on) {
        widget.onBluetoothReady();
      }
    });
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
    String? state = _adapterState.toString().split(".").last;
    return Text(
      'Bluetooth Adapter is ${state ?? 'not available'}',
      style: Theme.of(context).primaryTextTheme.titleSmall?.copyWith(
            color: Colors.white,
          ),
    );
  }

  Widget buildTurnOnButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ElevatedButton(
        child: const Text('TURN ON'),
        onPressed: () async {
          try {
            if (!kIsWeb && Platform.isAndroid) {
              await FlutterBluePlus.turnOn();
            }
          } catch (e, backtrace) {
            print("Error turning on Bluetooth: $e");
            print("backtrace: $backtrace");
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            buildBluetoothOffIcon(context),
            buildTitle(context),
            if (!kIsWeb &&
                Platform.isAndroid &&
                _adapterState != BluetoothAdapterState.on)
              buildTurnOnButton(context),
          ],
        ),
      ),
    );
  }
}
