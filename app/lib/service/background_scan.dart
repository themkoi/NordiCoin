import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../consts.dart';
import '../data.dart';
import '../utils/scan.dart';
import '../utils/other.dart';
import '../utils/ble.dart';

bool _isRunning = false;
bool _notificationShown = false;
StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'background_scan_id',
  'Background Scan',
  description: 'Notifications for background BLE scanning',
  importance: Importance.low,
);

Future<void> _showRunningNotification() async {
  if (_notificationShown) return;
  await _notificationsPlugin.show(
    1,
    '',
    '',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'background_scan_id',
        'Background Scan',
        icon: '@drawable/notification_icon',
        ongoing: true,
        autoCancel: false,
        importance: Importance.low,
        priority: Priority.low,
      ),
    ),
  );
  _notificationShown = true;
}

Future<void> _hideRunningNotification() async {
  if (!_notificationShown) return;
  await _notificationsPlugin.cancel(1);
  _notificationShown = false;
}

Future<void> initializeBackgroundScanService() async {
  final service = FlutterBackgroundService();

  await _notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_channel);

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
    await _notificationsPlugin.cancel(1);
    service.stopSelf();
  });

  _startScanLoop(service);
}

Future<void> _startScanLoop(ServiceInstance service) async {
  print('Service started, scanning loop initiated.');

  // initial notification
  if (areAlertsOn().isOn) {
    await _showRunningNotification();
  }

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

    final alertsStatus = areAlertsOn();
    if (!alertsStatus.isOn) {
      print('Service: alerts are off, skipping scan (${alertsStatus.reason}).');
      await _hideRunningNotification();
      continue;
    }

    await _showRunningNotification();

    print('Service scan interval complete, starting scan.');
    await _performScan(service);
  }
  print("Scan loop function exited");
}

Future<void> _performScan(ServiceInstance service) async {
  // Load current bonded devices
  final box = Hive.box(hiveBoxDevices);
  final devices = <Device>[];
  for (final key in box.keys) {
    final value = box.get(key);
    if (value is Device) {
      devices.add(value);
    }
  }

  final foundMacAddresses = <String>{};
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

      final scannedMac = newResult.device.remoteId.str.toLowerCase();
      if (!foundMacAddresses.contains(scannedMac)) {
        for (final device in devices) {
          if (device.macAddress.toLowerCase() == scannedMac) {
            foundMacAddresses.add(scannedMac);
            print("Found bonded device: ${device.aliasName}");
            break;
          }
        }
      }

      // Early stop: all bonded devices found
      if (foundMacAddresses.length == devices.length && devices.isNotEmpty) {
        print(
          'All ${devices.length} bonded device(s) found, stopping scan early.',
        );
        try {
          FlutterBluePlus.stopScan();
        } catch (_) {}
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

    // Wait for scan to finish (either by timeout or early stop)
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

  final scannedMacs = <String>{};

  for (final result in collectedResults) {
    final scannedMac = result.device.remoteId.str.toLowerCase();
    scannedMacs.add(scannedMac);

    for (final device in devices) {
      if (device.macAddress.toLowerCase() == scannedMac) {
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
