import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const String hiveBoxDevices = 'devices';
const String hiveBoxSettings = 'settings';

// Valid range for hardcoded notification IDs: 0-999
const int notifIdBackgroundScanRunning = 1;
const int notifIdBackgroundScanError = 2;
const int notifIdTest = 999;

/// NordCoin Service UUID (16-bit: 0x0001)
final Guid nordCoinServiceUuid = Guid("00000001-0000-1000-8000-00805f9b34fb");

/// Find Me Loud Characteristic UUID (16-bit: 0x0002)
/// Type: u8 - Duration in seconds to turn on the Buzzer
final Guid findMeLoudCharUuid = Guid("00000002-0000-1000-8000-00805f9b34fb");

/// Find Me Quiet Characteristic UUID (16-bit: 0x0003)
/// Type: u8 - Duration in seconds to turn on the LED
final Guid findMeQuietCharUuid = Guid("00000003-0000-1000-8000-00805f9b34fb");

/// Uptime Characteristic UUID (16-bit: 0x0004)
/// Type: u32 - Device uptime in minutes (read-only)
final Guid uptimeCharUuid = Guid("00000004-0000-1000-8000-00805f9b34fb");

/// TX Power Characteristic UUID (16-bit: 0x0005)
/// Type: i8 - Transmission power level (write-only)
final Guid txPowerCharUuid = Guid("00000005-0000-1000-8000-00805f9b34fb");

/// Bonded Characteristic UUID (16-bit: 0x0006)
/// Type: bool - Bonding status (write-only)
final Guid bondedCharUuid = Guid("00000006-0000-1000-8000-00805f9b34fb");
