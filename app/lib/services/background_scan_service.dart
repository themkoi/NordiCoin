import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../consts.dart';
import '../data.dart';
import '../utils/scan.dart';
import '../utils/other.dart';

bool _isRunning = false;
StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

Future<void> initializeBackgroundScanService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: false,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );

  service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  await initHive();

  _isRunning = true;

  service.on('stopScan').listen((event) async {
    print('Background service: received stop command, stopping immediately.');
    _isRunning = false;
    _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;
    FlutterBluePlus.stopScan();
    service.stopSelf();
  });

  _startScanLoop(service);
}

Future<void> _startScanLoop(ServiceInstance service) async {
  print('Service started, scanning loop initiated.');
  while (_isRunning) {
    final settingsBox = Hive.box(hiveBoxSettings);
    final settings = settingsBox.get(0) as Settings;
    int scanIntervalM = settings.scanFrequencyTimeM * 60;

    final waitStart = DateTime.now();
    while (_isRunning &&
        DateTime.now().difference(waitStart).inSeconds < scanIntervalM) {
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!_isRunning) {
      print('Service stopped during wait interval.');
      break;
    }

    print('Service scan interval complete, starting scan.');
    await _performScan(service);
  }
  print("Scan loop function exited");
}

Future<void> _performScan(ServiceInstance service) async {
  final collectedResults = <ScanResult>[];

  _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
    for (final newResult in results) {
      final existingIndex = collectedResults.indexWhere(
        (r) => r.device.remoteId == newResult.device.remoteId,
      );
      if (existingIndex >= 0) {
        if (newResult.rssi > collectedResults[existingIndex].rssi) {
          collectedResults[existingIndex] = newResult;
        }
      } else {
        collectedResults.add(newResult);
      }
    }
  });

  try {
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: true,
      androidScanMode: AndroidScanMode.lowLatency,
      continuousUpdates: true,
      continuousDivisor: 1,
    );

    // Is this the proper way to wait for it to finish?
    await FlutterBluePlus.isScanning.firstWhere((isScanning) => !isScanning);
  } catch (e) {
    print('Service, error during scan: $e');
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;
    return;
  }

  await _scanResultsSubscription?.cancel();
  _scanResultsSubscription = null;

  if (!_isRunning) return;

  print('Service scan finished, found ${collectedResults.length} devices');

  // Load current devices
  final box = Hive.box(hiveBoxDevices);
  final devices = <Device>[];
  for (final key in box.keys) {
    final value = box.get(key);
    if (value is Device) {
      devices.add(value);
    }
  }

  final scannedMacs = <String>{};

  for (final result in collectedResults) {
    final scannedMac = result.device.remoteId.str.toLowerCase();
    scannedMacs.add(scannedMac);

    for (final device in devices) {
      if (device.macAddress.toLowerCase() == scannedMac) {
        print("Found bonded device: ${device.aliasName}");
        device.lastSeenTime = DateTime.now();
        device.lastSeenRssi = result.rssi;

        final batteryVoltage = parseBatteryFromRawAdvBytes(
          result.advertisementData.rawAdvBytes,
        );
        if (batteryVoltage != null) {
          device.batteryVoltage = batteryVoltage;
        }

        await device.save();
      }
    }
  }

  print('Background scan cycle complete');
}
