import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../consts.dart';
import '../data.dart';

// Enabled / Disabled device
const Color disabledGreyColor = Color(0xFF757575);

Color alertColorFromDevice(Device device) {
  final settings = device.deviceSettings;
  final minutesSinceLastSeen = DateTime.now()
      .difference(device.lastSeenTime)
      .inMinutes;

  if (!device.enabledAlerts) {
    return disabledGreyColor;
  }

  if (minutesSinceLastSeen > settings.highAlertLostDeviceTimeM) {
    return Colors.red;
  } else if (minutesSinceLastSeen > settings.mediumAlertLostDeviceTimeM) {
    return Colors.orange;
  } else if (minutesSinceLastSeen > settings.lowAlertLostDeviceTimeM) {
    return Colors.green;
  }
  return Colors.grey[400]!;
}

Future<void> initHive() async {
  await Hive.initFlutter();
  Hive.registerAdapter(ActionTypeAdapter());
  Hive.registerAdapter(OnAppDeviceAdapter());
  Hive.registerAdapter(DeviceAdapter());
  Hive.registerAdapter(SettingsAdapter());

  try {
    await Hive.openBox(hiveBoxDevices);
  } catch (e) {
    debugPrint('Devices box corrupted, clearing and starting fresh: $e');
    await Hive.deleteBoxFromDisk(hiveBoxDevices);
    await Hive.openBox(hiveBoxDevices);
  }

  try {
    await Hive.openBox(hiveBoxSettings);
  } catch (e) {
    debugPrint('Settings box corrupted, clearing and starting fresh: $e');
    await Hive.deleteBoxFromDisk(hiveBoxSettings);
    await Hive.openBox(hiveBoxSettings);
  }
}

Color dbmColor(int dbm) {
  if (dbm >= -50) return Colors.green;
  if (dbm >= -65) return Colors.lightGreen;
  if (dbm >= -75) return Colors.amber;
  if (dbm >= -85) return Colors.orange;
  return Colors.red;
}

String formatTimeAgo(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);

  if (difference.inSeconds < 60) {
    return '${difference.inSeconds}s ago';
  } else if (difference.inMinutes < 60) {
    final mins = difference.inMinutes;
    final secs = difference.inSeconds % 60;
    return secs > 0 ? '${mins}m ${secs}s' : '${mins}m';
  } else if (difference.inHours < 24) {
    final hours = difference.inHours;
    final mins = (difference.inMinutes % 60);
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  } else {
    final days = difference.inDays;
    final hours = (difference.inHours % 24);
    return hours > 0 ? '${days}d ${hours}h' : '${days}d';
  }
}

String prettyException(String prefix, dynamic e) {
  if (e is FlutterBluePlusException) {
    return "$prefix ${e.description}";
  } else if (e is PlatformException) {
    return "$prefix ${e.message}";
  }
  return prefix + e.toString();
}

String formatMinutes(int minutes) {
  if (minutes < 1) return '0m';

  final years = minutes ~/ 525600;
  final days = (minutes % 525600) ~/ 1440;
  final hours = (minutes % 1440) ~/ 60;
  final mins = minutes % 60;

  final parts = <String>[];
  if (years > 0) parts.add('${years}y');
  if (days > 0) parts.add('${days}d');
  if (hours > 0) parts.add('${hours}h');
  if (mins > 0) parts.add('${mins}m');

  return parts.join(' ');
}
