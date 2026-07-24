import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

typedef DeviceOperation = Future<void> Function(BluetoothDevice device);

Future<void> connectAndOperate({
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

  try {
    await device.connect();

    if (dialogState != null) {
      _updateLoadingDialog(dialogState, "Discovering services...");
    }
    await device.discoverServices();

    if (dialogState != null) {
      _updateLoadingDialog(dialogState, operationMessage);
    }
    await operation(device);
  } finally {
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

class DialogState {
  final BuildContext context;
  final void Function(String message) update;
  final void Function() close;
  DialogState({
    required this.context,
    required this.update,
    required this.close,
  });
}

DialogState _showLoadingDialog(BuildContext context, String message) {
  late StateSetter setState;
  String currentMessage = message;

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
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(currentMessage),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () {
                        if (Navigator.canPop(dialogContext)) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                      child: const Text("Cancel"),
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
