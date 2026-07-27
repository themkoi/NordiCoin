import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../consts.dart';
import '../data.dart';
import '../utils/battery.dart';
import '../utils/other.dart';
import '../utils/scan.dart';
import 'device.dart';

class StatusDevicesPage extends StatefulWidget {
  const StatusDevicesPage({super.key});

  @override
  State<StatusDevicesPage> createState() => StatusDevicesPageState();
}

class StatusDevicesPageState extends State<StatusDevicesPage> {
  List<Device> _devices = [];
  int? _highlightedIndex;

  @override
  void initState() {
    super.initState();
    loadDevices();
  }

  Future<void> loadDevices() async {
    final box = Hive.box(hiveBoxDevices);
    final devices = <Device>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value is Device) {
        devices.add(value);
      }
    }
    // Sort alphabetically by alias name
    devices.sort((a, b) => a.aliasName.compareTo(b.aliasName));
    if (mounted) {
      setState(() {
        _devices = devices;
      });
    }
  }

  void _onDeviceTap(int index) {
    setState(() {
      if (_highlightedIndex == index) {
        _highlightedIndex = null;
      } else {
        _highlightedIndex = index;
      }
    });
  }

  Widget _buildDeviceTile(Device device, int index) {
    final isHighlighted = _highlightedIndex == index;
    final percentage = batteryPercentageFromVoltage(device.batteryVoltage);
    final batteryColor = batteryColorFromPercentage(percentage);
    final lastSeenStr = formatTimeAgo(device.lastSeenTime);

    return Column(
      children: [
        InkWell(
          onTap: () => _onDeviceTap(index),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          device.aliasName,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: isHighlighted
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        lastSeenStr,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.battery_full, size: 16, color: batteryColor),
                      const SizedBox(width: 2),
                      Text(
                        '${percentage.round()}%',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: batteryColor),
                      ),
                    ],
                  ),
                ),
                // Button to navigate to device detail page
                IconButton(
                  icon: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: isHighlighted
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[600],
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => DevicePage(
                          device: device,
                          statusKey: widget.key as GlobalKey<StatusDevicesPageState>,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (isHighlighted)
          Container(
            margin: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 8,
              top: 4,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(
                  icon: Icons.access_time,
                  label: 'Last seen',
                  value: device.lastSeenTime.toString().substring(0, 19),
                ),
                const SizedBox(height: 4),
                _buildDetailRow(
                  icon: Icons.battery_std,
                  label: 'Battery voltage',
                  value: '${device.batteryVoltage.toStringAsFixed(2)} V',
                ),
                const SizedBox(height: 4),
                _buildDetailRow(
                  icon: Icons.signal_cellular_alt,
                  label: 'Latest RSSI',
                  value: '${device.lastSeenRssi} dBm',
                ),
                const SizedBox(height: 4),
                _buildDetailRow(
                  icon: Icons.network_wifi,
                  label: 'MAC address',
                  value: device.macAddress,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[400]),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
          ),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No devices added yet',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey[400]),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to scan and add devices',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await startScan();
        await loadDevices();
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 2),
        itemCount: _devices.length,
        itemBuilder: (context, index) =>
            _buildDeviceTile(_devices[index], index),
      ),
    );
  }
}
