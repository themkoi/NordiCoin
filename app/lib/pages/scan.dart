import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../consts.dart';
import '../utils/ble.dart';
import '../data.dart';
import '../utils/other.dart';
import 'status_devices.dart';

class ScanScreen extends StatefulWidget {
  final GlobalKey<StatusDevicesPageState> statusKey;

  const ScanScreen({super.key, required this.statusKey});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  @override
  void initState() {
    super.initState();

    // Clear on init
    FlutterBluePlus.stopScan();
    setState(() {
      _scanResults = [];
      _isScanning = false;
    });

    _scanResultsSubscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        if (mounted) {
          setState(() => _scanResults = results);
        }
      },
      onError: (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(prettyException("Scan Error:", e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (mounted) {
        setState(() => _isScanning = state);
      }
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    super.dispose();
  }

  Future onScanPressed() async {
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: true,
        continuousDivisor: 1,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(prettyException("Start Scan Error:", e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future onStopPressed() async {
    try {
      FlutterBluePlus.stopScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(prettyException("Stop Scan Error:", e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> onConnectPressed(BluetoothDevice device) async {
    final box = Hive.box(hiveBoxDevices);
    final deviceName = device.platformName;
    final deviceId = deviceName.contains('-')
        ? deviceName.split('-').skip(1).join('-')
        : deviceName;

    final aliasName = deviceName.isEmpty ? '(No name)' : deviceName;
    final resolvedDeviceId = deviceId.isEmpty ? '(No id)' : deviceId;

    final success = await connectAndOperate(
      macAddress: device.remoteId.str,
      context: context,
      operationMessage: "Setting up device...",
      operation: (connectedDevice) async {
        final allChars = <BluetoothCharacteristic>[];
        for (final service in connectedDevice.servicesList) {
          allChars.addAll(service.characteristics);
        }

        BluetoothCharacteristic charFor(Guid uuid) {
          return allChars.firstWhere((c) => c.uuid == uuid);
        }

        final bondedChar = charFor(bondedCharUuid);
        await bondedChar.write([1]);

        final settingsBox = Hive.box(hiveBoxSettings);
        final settings = settingsBox.get(0) as Settings;
        final defaultSettings = settings.defaultDeviceSettings;
        final txPowerChar = charFor(txPowerCharUuid);
        await txPowerChar.write([defaultSettings.txPower]);

        final uptimeChar = charFor(uptimeCharUuid);
        final uptimeBytes = await uptimeChar.read();
        final uptimeMinutes = ByteData.sublistView(
          Uint8List.fromList(uptimeBytes),
        ).getUint32(0, Endian.little);
        final onAppDevice = OnAppDevice(txPower: defaultSettings.txPower);

        final newDevice = Device(
          aliasName: aliasName,
          macAddress: device.remoteId.str,
          id: resolvedDeviceId,
          lastSeenTime: DateTime.now(),
          lastSeenUptimeM: uptimeMinutes,
          deviceSettings: onAppDevice,
        );

        box.put(box.values.length, newDevice);
      },
    );

    if (success && mounted) {
      widget.statusKey.currentState?.loadDevices();
      Navigator.of(context).pop();
    }
  }

  Widget buildScanButton() {
    final button = _isScanning
        ? ElevatedButton(
            onPressed: onStopPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text("STOP"),
          )
        : ElevatedButton(
            onPressed: onScanPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text("SCAN"),
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [if (_isScanning) buildSpinner(), button],
    );
  }

  Widget buildSpinner() {
    return const Padding(
      padding: EdgeInsets.only(right: 20.0),
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }

  Iterable<Widget> _buildScanResultTiles() {
    return _scanResults.map(
      (r) => ScanResultTile(result: r, onTap: () => onConnectPressed(r.device)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Find Devices'),
        actions: [buildScanButton(), const SizedBox(width: 15)],
      ),
      body: ListView(children: <Widget>[..._buildScanResultTiles()]),
    );
  }
}

class ScanResultTile extends StatefulWidget {
  const ScanResultTile({super.key, required this.result, this.onTap});

  final ScanResult result;
  final VoidCallback? onTap;

  @override
  State<ScanResultTile> createState() => _ScanResultTileState();
}

class _ScanResultTileState extends State<ScanResultTile> {
  late StreamSubscription<BluetoothConnectionState>
  _connectionStateSubscription;

  @override
  void initState() {
    super.initState();

    _connectionStateSubscription = widget.result.device.connectionState.listen((
      state,
    ) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    super.dispose();
  }

  Widget _buildTitle(BuildContext context) {
    final displayName = widget.result.advertisementData.advName;
    if (displayName.isNotEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(displayName, overflow: TextOverflow.ellipsis),
          Text(
            widget.result.device.remoteId.str,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    } else {
      return Text(widget.result.device.remoteId.str);
    }
  }

  bool _isAlreadyBonded() {
    final box = Hive.box(hiveBoxDevices);
    final scannedMac = widget.result.device.remoteId.str;
    for (final key in box.keys) {
      final device = box.get(key) as Device;
      if (device.macAddress.toLowerCase() == scannedMac.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final alreadyBonded = _isAlreadyBonded();
    return ListTile(
      title: _buildTitle(context),
      leading: Text(widget.result.rssi.toString()),
      trailing: alreadyBonded
          ? ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                foregroundColor: Colors.grey,
              ),
              child: const Text('Already bonded'),
            )
          : ElevatedButton(
              onPressed: widget.onTap,
              child: const Text('Connect'),
            ),
    );
  }
}
