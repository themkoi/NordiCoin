import 'package:hive_flutter/hive_flutter.dart';

part 'data.g.dart';

@HiveType(typeId: 0)
enum ActionType {
  @HiveField(0)
  none,

  @HiveField(1)
  notification,

  @HiveField(2)
  buzzing,

  @HiveField(3)
  loudAlarm,
}

@HiveType(typeId: 1)
class OnAppDevice extends HiveObject {
  @HiveField(0)
  late int loudBuzzingTimeS;

  @HiveField(1)
  late int silentBuzzingTimeS;

  @HiveField(2)
  late int txPower;

  @HiveField(3)
  late int turningOffAlertTimeM;

  @HiveField(4)
  late int lowAlertLostDeviceTimeM;

  @HiveField(5)
  late int mediumAlertLostDeviceTimeM;

  @HiveField(6)
  late int highAlertLostDeviceTimeM;

  @HiveField(7)
  late ActionType lowAlertAction;

  @HiveField(8)
  late ActionType mediumAlertAction;

  @HiveField(9)
  late ActionType highAlertAction;

  OnAppDevice({
    this.loudBuzzingTimeS = 0,
    this.silentBuzzingTimeS = 0,
    this.txPower = 0,
    this.turningOffAlertTimeM = 15,
    this.lowAlertLostDeviceTimeM = 5,
    this.mediumAlertLostDeviceTimeM = 10,
    this.highAlertLostDeviceTimeM = 15,
    this.lowAlertAction = ActionType.none,
    this.mediumAlertAction = ActionType.none,
    this.highAlertAction = ActionType.none,
  });
}

@HiveType(typeId: 2)
class Device extends HiveObject {
  @HiveField(0)
  late String aliasName;

  @HiveField(1)
  late String macAddress;

  @HiveField(2)
  late double batteryVoltage;

  @HiveField(3)
  late DateTime lastSeenTime;

  @HiveField(4)
  late int lastSeenRssi;

  @HiveField(5)
  late String id;

  @HiveField(6)
  late int lastSeenUptimeS;

  @HiveField(7)
  late OnAppDevice deviceSettings;

  Device({
    this.aliasName = '',
    this.macAddress = '',
    this.batteryVoltage = 3.3,
    required this.lastSeenTime,
    this.lastSeenRssi = 0,
    this.id = '',
    this.lastSeenUptimeS = 0,
    required this.deviceSettings,
  });
}

@HiveType(typeId: 3)
class Settings extends HiveObject {
  @HiveField(0)
  late bool alertsManualOverride;

  @HiveField(1)
  late int alertsOffAfterTimeH;

  @HiveField(2)
  late int alertsOffAfterTimeM;

  @HiveField(3)
  late int alertsOnAfterTimeH;

  @HiveField(4)
  late int alertsOnAfterTimeM;

  @HiveField(5)
  late int scanFrequencyTimeM;

  @HiveField(6)
  late OnAppDevice defaultDeviceSettings;

  Settings({
    this.alertsManualOverride = false,
    this.alertsOffAfterTimeH = 0,
    this.alertsOffAfterTimeM = 0,
    this.alertsOnAfterTimeH = 0,
    this.alertsOnAfterTimeM = 0,
    this.scanFrequencyTimeM = 2,
    required this.defaultDeviceSettings,
  });
}
