import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../consts.dart';
import '../data.dart';

// The device broadcasts battery as a single byte with type 0x21 in the AD structure.
// Battery encoding: 0 = 1.800V, 255 = 3.300V, resolution = 0.006V
// Formula: voltage = 1.800 + (byte * 0.006)
double? parseBatteryFromRawAdvBytes(List<int>? rawAdvBytes) {
  if (rawAdvBytes == null || rawAdvBytes.isEmpty) {
    return null;
  }
  int n = 0;
  while (n < rawAdvBytes.length) {
    final fieldLen = rawAdvBytes[n];
    // End of ADV data
    if (fieldLen <= 0 || n + fieldLen >= rawAdvBytes.length) {
      break;
    }
    final dataType = rawAdvBytes[n + 1];
    if (dataType == 0x21 && fieldLen >= 2) {
      final byteValue = rawAdvBytes[n + 2];
      return 1.800 + (byteValue * 0.006);
    }
    n += fieldLen + 1;
  }
  return null;
}

Future<String> startScan() async {
  print('Starting BLE scan...');

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

  final subscription = FlutterBluePlus.onScanResults.listen((results) {
    // Keep only the best RSSI result per device
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
            print('${device.aliasName}: found (RSSI: ${newResult.rssi} dBm)');
            break;
          }
        }
      }

      // Early stop: all bonded devices found
      if (foundMacAddresses.length == devices.length && devices.isNotEmpty) {
        print(
          'All ${devices.length} bonded device(s) found, stopping scan early.',
        );
        FlutterBluePlus.stopScan();
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
  } catch (e) {
    print('Error starting scan: $e');
    await subscription.cancel();
    rethrow;
  }

  // Wait for scan to finish (either by timeout or early stop)
  await FlutterBluePlus.isScanning.firstWhere((isScanning) => !isScanning);
  await subscription.cancel();
  print('Scan finished.');

  print('Scan Found ${collectedResults.length} devices');

  final errors = <String>[];
  final scannedMacs = <String>{};

  for (final result in collectedResults) {
    final scannedMac = result.device.remoteId.str.toLowerCase();
    scannedMacs.add(scannedMac);

    for (final device in devices) {
      if (device.macAddress.toLowerCase() == scannedMac) {
        device.lastSeenTime = DateTime.now();
        device.lastSeenRssi = result.rssi;

        // A bonded device doesn't advertise its name.
        final deviceName = result.advertisementData.advName;
        if (deviceName.isNotEmpty) {
          errors.add('Device ($deviceName) unbonded itself');
        } else {
          final batteryVoltage = parseBatteryFromRawAdvBytes(
            result.advertisementData.rawAdvBytes,
          );
          print('${device.aliasName}: found (RSSI: ${result.rssi} dBm)');
          if (batteryVoltage != null) {
            device.batteryVoltage = batteryVoltage;
            print('Battery: ${batteryVoltage.toStringAsFixed(2)}V');
          } else {
            errors.add(
              'Failed to retrieve battery level for ${device.aliasName}',
            );
          }
        }
        await device.save();
        break;
      }
    }
  }

  for (final device in devices) {
    if (!scannedMacs.contains(device.macAddress.toLowerCase())) {
      errors.add('Device ${device.aliasName} wasn\'t found');
    }
  }

  return errors.join('\n');
}
