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
