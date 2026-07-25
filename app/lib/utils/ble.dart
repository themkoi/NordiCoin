import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../consts.dart';
import '../data.dart';

typedef DeviceOperation = Future<void> Function(BluetoothDevice device);

const List<int> txPowerValues = [
  -40,
  -20,
  -16,
  -12,
  -8,
  -4,
  0,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  10,
  12,
  14,
  16,
  18,
  20,
];

String txPowerToString(int value) {
  if (value > 0) {
    return '+$value dBm';
  } else if (value == 0) {
    return '0 dBm';
  } else {
    return '$value dBm';
  }
}

int txPowerFromString(String str) {
  final cleaned = str.replaceAll('dBm', '').trim();
  return int.tryParse(cleaned) ?? 0;
}

({bool isOn, String reason}) areAlertsOn() {
  final box = Hive.box(hiveBoxSettings);
  final settings = box.get(0) as Settings;

  if (settings.alertsManualOverride && settings.alertsManualOverrideAlert) {
    return (isOn: true, reason: 'Manual override forced');
  }

  if (settings.alertsManualOverride && !settings.alertsManualOverrideAlert) {
    return (isOn: false, reason: 'Manual override disabled');
  }

  final now = DateTime.now();
  final currentMinutes = now.hour * 60 + now.minute;

  final onTimeMinutes =
      settings.alertsOnAfterTimeH * 60 + settings.alertsOnAfterTimeM;
  final offTimeMinutes =
      settings.alertsOffAfterTimeH * 60 + settings.alertsOffAfterTimeM;

  // Normal and overnight
  if (onTimeMinutes <= offTimeMinutes) {
    final isOn =
        currentMinutes >= onTimeMinutes && currentMinutes < offTimeMinutes;
    final onStr =
        '${settings.alertsOnAfterTimeH.toString().padLeft(2, '0')}:${settings.alertsOnAfterTimeM.toString().padLeft(2, '0')}';
    final offStr =
        '${settings.alertsOffAfterTimeH.toString().padLeft(2, '0')}:${settings.alertsOffAfterTimeM.toString().padLeft(2, '0')}';
    return (
      isOn: isOn,
      reason: isOn
          ? 'Within alert window ($onStr - $offStr)'
          : 'Outside alert window ($onStr - $offStr)',
    );
  } else {
    final isOn =
        currentMinutes >= offTimeMinutes || currentMinutes < onTimeMinutes;
    final onStr =
        '${settings.alertsOnAfterTimeH.toString().padLeft(2, '0')}:${settings.alertsOnAfterTimeM.toString().padLeft(2, '0')}';
    final offStr =
        '${settings.alertsOffAfterTimeH.toString().padLeft(2, '0')}:${settings.alertsOffAfterTimeM.toString().padLeft(2, '0')}';
    return (
      isOn: isOn,
      reason: isOn
          ? 'Within alert window ($offStr - $onStr)'
          : 'Outside alert window ($offStr - $onStr)',
    );
  }
}

Future<bool> connectAndOperate({
  required String macAddress,
  required DeviceOperation operation,
  BuildContext? context,
  required String operationMessage,
}) async {
  final device = BluetoothDevice.fromId(macAddress);

  DialogState? dialogState;
  if (context != null) {
    dialogState = _showLoadingDialog(context, "Connecting");
  }

  var hasError = false;
  try {
    await device.connect(license: License.nonprofit);

    if (dialogState != null) {
      _updateLoadingDialog(dialogState, "Discovering services...");
    }
    await device.discoverServices();

    if (dialogState != null) {
      _updateLoadingDialog(dialogState, operationMessage);
    }
    await operation(device);
  } catch (e) {
    hasError = true;
    if (dialogState != null) {
      dialogState.showError("Error: $e");
    }
    return false;
  } finally {
    if (hasError) {
      if (device.isConnected) {
        await device.disconnect();
      }
    } else {
      if (dialogState != null) {
        _updateLoadingDialog(dialogState, "Disconnecting");
      }
      if (device.isConnected) {
        await device.disconnect();
      }
      if (dialogState != null) {
        dialogState.close();
      }
    }
  }
  return true;
}

class DialogState {
  final BuildContext context;
  final void Function(String message) update;
  final void Function(String message) showError;
  final void Function() close;
  DialogState({
    required this.context,
    required this.update,
    required this.showError,
    required this.close,
  });
}

DialogState _showLoadingDialog(BuildContext context, String message) {
  late StateSetter setState;
  String currentMessage = message;
  bool isError = false;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (ctx, setStates) {
          setState = setStates;
          return Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isError)
                      const CircularProgressIndicator()
                    else
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                      ),
                    const SizedBox(height: 16),
                    Text(currentMessage),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () {
                        if (Navigator.canPop(dialogContext)) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                      child: Text(isError ? "Ok" : "Cancel"),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  return DialogState(
    context: context,
    update: (newMessage) {
      setState(() {
        currentMessage = newMessage;
        isError = false;
      });
    },
    showError: (errorMessage) {
      setState(() {
        currentMessage = errorMessage;
        isError = true;
      });
    },
    close: () {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    },
  );
}

void _updateLoadingDialog(DialogState dialogState, String message) {
  dialogState.update(message);
}
