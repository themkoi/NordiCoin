import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

typedef DeviceOperation = Future<void> Function(BluetoothDevice device);

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
    await device.connect();

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
