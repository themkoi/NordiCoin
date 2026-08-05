// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'data.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OnAppDeviceAdapter extends TypeAdapter<OnAppDevice> {
  @override
  final int typeId = 1;

  @override
  OnAppDevice read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OnAppDevice(
      loudBuzzingTimeS: fields[0] as int,
      silentBuzzingTimeS: fields[1] as int,
      txPower: fields[2] as int,
      turningOffAlertTimeM: fields[3] as int,
      lowAlertLostDeviceTimeM: fields[4] as int,
      mediumAlertLostDeviceTimeM: fields[5] as int,
      highAlertLostDeviceTimeM: fields[6] as int,
      lowAlertAction: fields[7] as ActionType,
      mediumAlertAction: fields[8] as ActionType,
      highAlertAction: fields[9] as ActionType,
    );
  }

  @override
  void write(BinaryWriter writer, OnAppDevice obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.loudBuzzingTimeS)
      ..writeByte(1)
      ..write(obj.silentBuzzingTimeS)
      ..writeByte(2)
      ..write(obj.txPower)
      ..writeByte(3)
      ..write(obj.turningOffAlertTimeM)
      ..writeByte(4)
      ..write(obj.lowAlertLostDeviceTimeM)
      ..writeByte(5)
      ..write(obj.mediumAlertLostDeviceTimeM)
      ..writeByte(6)
      ..write(obj.highAlertLostDeviceTimeM)
      ..writeByte(7)
      ..write(obj.lowAlertAction)
      ..writeByte(8)
      ..write(obj.mediumAlertAction)
      ..writeByte(9)
      ..write(obj.highAlertAction);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnAppDeviceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class DeviceAdapter extends TypeAdapter<Device> {
  @override
  final int typeId = 2;

  @override
  Device read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Device(
      aliasName: fields[0] as String,
      macAddress: fields[1] as String,
      batteryVoltage: fields[2] as double,
      lastSeenTime: fields[3] as DateTime,
      lastSeenRssi: fields[4] as int,
      id: fields[5] as String,
      lastSeenUptimeM: fields[6] as int,
      deviceSettings: fields[7] as OnAppDevice,
      enabledAlerts: fields[8] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Device obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.aliasName)
      ..writeByte(1)
      ..write(obj.macAddress)
      ..writeByte(2)
      ..write(obj.batteryVoltage)
      ..writeByte(3)
      ..write(obj.lastSeenTime)
      ..writeByte(4)
      ..write(obj.lastSeenRssi)
      ..writeByte(5)
      ..write(obj.id)
      ..writeByte(6)
      ..write(obj.lastSeenUptimeM)
      ..writeByte(7)
      ..write(obj.deviceSettings)
      ..writeByte(8)
      ..write(obj.enabledAlerts);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SettingsAdapter extends TypeAdapter<Settings> {
  @override
  final int typeId = 3;

  @override
  Settings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Settings(
      alertsManualOverride: fields[0] as bool,
      alertsManualOverrideAlert: fields[1] as bool,
      alertsOffAfterTimeH: fields[2] as int,
      alertsOffAfterTimeM: fields[3] as int,
      alertsOnAfterTimeH: fields[4] as int,
      alertsOnAfterTimeM: fields[5] as int,
      scanFrequencyTimeM: fields[6] as int,
      scanDurationS: fields[7] as int,
      defaultDeviceSettings: fields[8] as OnAppDevice,
    );
  }

  @override
  void write(BinaryWriter writer, Settings obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.alertsManualOverride)
      ..writeByte(1)
      ..write(obj.alertsManualOverrideAlert)
      ..writeByte(2)
      ..write(obj.alertsOffAfterTimeH)
      ..writeByte(3)
      ..write(obj.alertsOffAfterTimeM)
      ..writeByte(4)
      ..write(obj.alertsOnAfterTimeH)
      ..writeByte(5)
      ..write(obj.alertsOnAfterTimeM)
      ..writeByte(6)
      ..write(obj.scanFrequencyTimeM)
      ..writeByte(7)
      ..write(obj.scanDurationS)
      ..writeByte(8)
      ..write(obj.defaultDeviceSettings);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ActionTypeAdapter extends TypeAdapter<ActionType> {
  @override
  final int typeId = 0;

  @override
  ActionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ActionType.none;
      case 1:
        return ActionType.notification;
      case 2:
        return ActionType.buzzing;
      case 3:
        return ActionType.loudAlarm;
      default:
        return ActionType.none;
    }
  }

  @override
  void write(BinaryWriter writer, ActionType obj) {
    switch (obj) {
      case ActionType.none:
        writer.writeByte(0);
        break;
      case ActionType.notification:
        writer.writeByte(1);
        break;
      case ActionType.buzzing:
        writer.writeByte(2);
        break;
      case ActionType.loudAlarm:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
