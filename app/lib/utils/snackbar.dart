import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum SnackbarLocation {
  primary,
  secondary,
  tertiary,
}

class Snackbar {
  static final snackBarKeyPrimary = GlobalKey<ScaffoldMessengerState>();
  static final snackBarKeySecondary = GlobalKey<ScaffoldMessengerState>();
  static final snackBarKeyTertiary = GlobalKey<ScaffoldMessengerState>();

  static GlobalKey<ScaffoldMessengerState> getSnackbar(SnackbarLocation location) {
    switch (location) {
      case SnackbarLocation.primary:
        return snackBarKeyPrimary;
      case SnackbarLocation.secondary:
        return snackBarKeySecondary;
      case SnackbarLocation.tertiary:
        return snackBarKeyTertiary;
    }
  }

  static void show(SnackbarLocation location, String msg, {required bool success}) {
    final snackBar = success
        ? SnackBar(content: Text(msg), backgroundColor: Colors.blue)
        : SnackBar(content: Text(msg), backgroundColor: Colors.red);
    getSnackbar(location).currentState?.removeCurrentSnackBar();
    getSnackbar(location).currentState?.showSnackBar(snackBar);
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
