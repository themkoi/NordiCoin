import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../consts.dart';
import '../data.dart';
import '../service/actions.dart';
import '../utils/scan.dart';
import '../utils/other.dart';
import '../utils/ble.dart';

bool _isRunning = false;
bool _notificationShown = false;
bool _scanErrorNotificationShown = false;
late Settings _cachedSettings;
StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

// For cooldown checking
class TriggeredAlert {
  final String deviceId;
  final ActionType alertAction;
  final DateTime triggeredAt;

  TriggeredAlert({
    required this.deviceId,
    required this.alertAction,
    required this.triggeredAt,
  });
}

// There is no need to clear this, we simply will have more delay?
final List<TriggeredAlert> _triggeredAlerts = [];
// Mac, notification id
final Map<String, int> _notificationDeviceIds = {};

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'background_scan_id',
  'Background Scan',
  description: 'Notifications for background BLE scanning',
  importance: Importance.low,
);

Future<void> _showRunningNotification() async {
  if (_notificationShown) return;
  await _notificationsPlugin.show(
    notifIdBackgroundScanRunning,
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
  try {
    await _notificationsPlugin.cancel(notifIdBackgroundScanRunning);
  } catch (e) {
    // I DONT KNOW
  }
  _notificationShown = false;
}

Future<void> _showScanErrorNotification(String error) async {
  if (_scanErrorNotificationShown) return;
  await _notificationsPlugin.show(
    notifIdBackgroundScanError,
    'BLE Scan Error',
    error,
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
  _scanErrorNotificationShown = true;
}

Future<void> _hideScanErrorNotification() async {
  if (!_scanErrorNotificationShown) return;
  try {
    await _notificationsPlugin.cancel(notifIdBackgroundScanError);
  } catch (e) {
    // ignore
  }
  _scanErrorNotificationShown = false;
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
  // Because the task is a seperate process, or something
  await initHive();
  await initActions();

  // Once at startup only, idk if hive box loading is heavy
  final settingsBox = Hive.box(hiveBoxSettings);
  _cachedSettings = settingsBox.get(0) as Settings;

  // Maybe needed too?
  await _notificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/notification_icon'),
    ),
  );

  _isRunning = true;

  service.on('stopScan').listen((event) async {
    print('Background service: received stop command, stopping immediately.');
    _isRunning = false;
    _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;
    FlutterBluePlus.stopScan();
    await _hideRunningNotification();
    await _hideScanErrorNotification();
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
    int scanIntervalM = _cachedSettings.scanFrequencyTimeM * 60;

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

    print("Per device alert check");
    await _checkDeviceAlerts();

    print("Background loop finished...");
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

  // Also because android restricts for power saving non filtered scans
  if (devices.isEmpty) {
    print('No bonded devices to scan');
    return;
  }

  final foundMacAddresses = <String>{};
  final collectedResults = <ScanResult>[];
  final devicesWithAlerts = devices.where((d) => d.enabledAlerts).toList();

  _scanResultsSubscription = FlutterBluePlus.onScanResults.listen((results) {
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

      // Early stop: all devices with alerts enabled are found
      // No need to check if list is empty, we check this before running scan
      if (devicesWithAlerts.every(
        (d) => foundMacAddresses.contains(d.macAddress.toLowerCase()),
      )) {
        print(
          'All ${devicesWithAlerts.length} device(s) with alerts enabled found, stopping scan early.',
        );
        try {
          FlutterBluePlus.stopScan();
        } catch (_) {}
      }
    }
  });

  try {
    await FlutterBluePlus.startScan(
      // Android power saving needs this, otherwise no devices found
      withRemoteIds: devices.map((d) => d.macAddress).toList(),
      timeout: Duration(seconds: _cachedSettings.scanDurationS),
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
    await _showScanErrorNotification('BLE scan failed: $e');
    return;
  }

  await _scanResultsSubscription?.cancel();
  _scanResultsSubscription = null;

  if (!_isRunning) return;

  await _hideScanErrorNotification();

  print('Service scan finished, found ${collectedResults.length} devices');

  final scannedMacs = <String>{};

  for (final result in collectedResults) {
    final scannedMac = result.device.remoteId.str.toLowerCase();
    scannedMacs.add(scannedMac);

    for (final device in devices) {
      if (device.macAddress.toLowerCase() == scannedMac) {
        // If this device had a notification alert triggered, cancel it
        // Maybe in the config in the future
        final notifId = _notificationDeviceIds.remove(
          device.macAddress.toLowerCase(),
        );
        if (notifId != null) {
          await _notificationsPlugin.cancel(notifId);
        }

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

// Priority order: high -> medium -> low, if higher priority triggers, lower is skipped
Future<void> _checkDeviceAlerts() async {
  // Get devices (Again, ugh)
  final box = Hive.box(hiveBoxDevices);
  final devices = <Device>[];
  for (final key in box.keys) {
    final value = box.get(key);
    if (value is Device) {
      devices.add(value);
    }
  }

  final now = DateTime.now();

  for (final device in devices) {
    // Only check devices with alerts enabled
    if (!device.enabledAlerts) {
      continue;
    }

    final settings = device.deviceSettings;
    final lastSeenDiffM = now.difference(device.lastSeenTime).inMinutes;

    // Check HIGH alert first
    final highAction = settings.highAlertAction;
    if (highAction != ActionType.none &&
        _shouldTriggerAlert(device, highAction, settings, now)) {
      if (lastSeenDiffM >= settings.highAlertLostDeviceTimeM) {
        print(
          'HIGH alert for device: ${device.aliasName} '
          '(last seen ${lastSeenDiffM}m ago, threshold: ${settings.highAlertLostDeviceTimeM}m)',
        );
        final highMessage = _buildAlertMessage(device.aliasName, lastSeenDiffM);
        final highNotifId = _getNotificationId(device.macAddress);
        await executeAction(
          highAction,
          highMessage,
          notificationId: highNotifId,
        );
        if (highAction == ActionType.notification) {
          _notificationDeviceIds[device.macAddress.toLowerCase()] = highNotifId;
        }
        _addTriggeredAlert(device.id, highAction, now);
        // Skip rest alerts
        continue;
      }
    }

    // Check MEDIUM alert
    final mediumAction = settings.mediumAlertAction;
    if (mediumAction != ActionType.none &&
        _shouldTriggerAlert(device, mediumAction, settings, now)) {
      if (lastSeenDiffM >= settings.mediumAlertLostDeviceTimeM) {
        print(
          'MEDIUM alert for device: ${device.aliasName} '
          '(last seen ${lastSeenDiffM}m ago, threshold: ${settings.mediumAlertLostDeviceTimeM}m)',
        );
        final mediumMessage = _buildAlertMessage(
          device.aliasName,
          lastSeenDiffM,
        );
        final mediumNotifId = _getNotificationId(device.macAddress);
        await executeAction(
          mediumAction,
          mediumMessage,
          notificationId: mediumNotifId,
        );
        if (mediumAction == ActionType.notification) {
          _notificationDeviceIds[device.macAddress.toLowerCase()] =
              mediumNotifId;
        }
        _addTriggeredAlert(device.id, mediumAction, now);
        // Skip low
        continue;
      }
    }

    // Check LOW alert
    final lowAction = settings.lowAlertAction;
    if (lowAction != ActionType.none &&
        _shouldTriggerAlert(device, lowAction, settings, now)) {
      if (lastSeenDiffM >= settings.lowAlertLostDeviceTimeM) {
        print(
          'LOW alert for device: ${device.aliasName} '
          '(last seen ${lastSeenDiffM}m ago, threshold: ${settings.lowAlertLostDeviceTimeM}m)',
        );
        final lowMessage = _buildAlertMessage(device.aliasName, lastSeenDiffM);
        final lowNotifId = _getNotificationId(device.macAddress);
        await executeAction(lowAction, lowMessage, notificationId: lowNotifId);
        if (lowAction == ActionType.notification) {
          _notificationDeviceIds[device.macAddress.toLowerCase()] = lowNotifId;
        }
        _addTriggeredAlert(device.id, lowAction, now);
      }
    }
  }
}

// Checks if an alert should be triggered based on cooldown period
bool _shouldTriggerAlert(
  Device device,
  ActionType alertAction,
  OnAppDevice settings,
  DateTime now,
) {
  final trigger = _triggeredAlerts.firstWhere(
    (a) => a.deviceId == device.id && a.alertAction == alertAction,
    orElse: () => TriggeredAlert(
      deviceId: device.id,
      alertAction: ActionType.none,
      triggeredAt: DateTime.now(),
    ),
  );

  if (trigger.alertAction == ActionType.none) {
    // No previous alert for this device, for this action
    return true;
  }

  // Check if turningOffAlertTimeM has passed since the last trigger
  final timeSinceTriggerM = now.difference(trigger.triggeredAt).inMinutes;
  final canTrigger = timeSinceTriggerM >= settings.turningOffAlertTimeM;

  return canTrigger;
}

void _addTriggeredAlert(String deviceId, ActionType alertAction, DateTime now) {
  // Remove any existing alert with the same deviceId and alertAction
  _triggeredAlerts.removeWhere(
    (a) => a.deviceId == deviceId && a.alertAction == alertAction,
  );
  _triggeredAlerts.add(
    TriggeredAlert(
      deviceId: deviceId,
      alertAction: alertAction,
      triggeredAt: now,
    ),
  );
}

String _buildAlertMessage(String deviceName, int minutesNotSeen) {
  return '$deviceName not seen for $minutesNotSeen minutes';
}

// Skip 0-999
int _getNotificationId(String macAddress) {
  return macAddress.hashCode.abs() % 10000 + 1000;
}
