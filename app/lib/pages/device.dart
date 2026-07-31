import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../consts.dart';
import '../data.dart';
import '../utils/battery.dart';
import '../utils/ble.dart';
import '../utils/other.dart';
import 'status_devices.dart';

class DevicePage extends StatefulWidget {
  final Device device;
  final GlobalKey<StatusDevicesPageState> statusKey;

  const DevicePage({super.key, required this.device, required this.statusKey});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late Device _device;
  late OnAppDevice _settings;
  late TextEditingController _aliasController;
  late double _batteryPercentage;
  late Color _batteryColor;
  bool _settingsExpanded = false;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _settings = _device.deviceSettings;
    _aliasController = TextEditingController(text: _device.aliasName);
    _batteryPercentage = batteryPercentageFromVoltage(_device.batteryVoltage);
    _batteryColor = batteryColorFromPercentage(_batteryPercentage);
  }

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  void _refreshUptime() {
    connectAndOperate(
      macAddress: _device.macAddress,
      operation: (device) async {
        final services = await device.discoverServices();
        final nordCoinService = services.firstWhere(
          (s) => s.serviceUuid == nordCoinServiceUuid,
          orElse: () => throw Exception('NordCoin service not found'),
        );
        final uptimeChar = nordCoinService.characteristics.firstWhere(
          (c) => c.characteristicUuid == uptimeCharUuid,
          orElse: () => throw Exception('Uptime characteristic not found'),
        );
        final uptimeBytes = await uptimeChar.read();
        final uptimeMinutes = ByteData.sublistView(
          Uint8List.fromList(uptimeBytes),
        ).getUint32(0, Endian.little);
        setState(() {
          _device.lastSeenUptimeM = uptimeMinutes;
        });
        _device.save();
        widget.statusKey.currentState?.loadDevices();
      },
      context: context,
      operationMessage: 'Reading uptime...',
    ).then((success) {
      if (mounted && success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Uptime refreshed')));
      }
    });
  }

  void _loudFind() {
    final duration = _settings.loudBuzzingTimeS;
    connectAndOperate(
      macAddress: _device.macAddress,
      operation: (device) async {
        final services = await device.discoverServices();
        final loudService = services.firstWhere(
          (s) => s.serviceUuid == nordCoinServiceUuid,
          orElse: () => throw Exception('NordCoin service not found'),
        );
        final loudCharHandle = loudService.characteristics.firstWhere(
          (c) => c.characteristicUuid == findMeLoudCharUuid,
          orElse: () => throw Exception('Loud find characteristic not found'),
        );
        final silentCharHandle = loudService.characteristics.firstWhere(
          (c) => c.characteristicUuid == findMeQuietCharUuid,
          orElse: () => throw Exception('Quiet find characteristic not found'),
        );
        await loudCharHandle.write([duration]);
        await silentCharHandle.write([duration]);
      },
      context: context,
      operationMessage: 'Triggering loud find...',
    ).then((success) {
      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Loud find triggered for ${_settings.loudBuzzingTimeS}s',
            ),
          ),
        );
      }
    });
  }

  void _quietFind() {
    final duration = _settings.silentBuzzingTimeS;
    connectAndOperate(
      macAddress: _device.macAddress,
      operation: (device) async {
        final services = await device.discoverServices();
        final loudService = services.firstWhere(
          (s) => s.serviceUuid == nordCoinServiceUuid,
          orElse: () => throw Exception('NordCoin service not found'),
        );
        final silentCharHandle = loudService.characteristics.firstWhere(
          (c) => c.characteristicUuid == findMeQuietCharUuid,
          orElse: () => throw Exception('Quiet find characteristic not found'),
        );
        await silentCharHandle.write([duration]);
      },
      context: context,
      operationMessage: 'Triggering quiet find...',
    ).then((success) {
      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Quiet find triggered for ${_settings.silentBuzzingTimeS}s',
            ),
          ),
        );
      }
    });
  }

  void _applyTxPower() {
    connectAndOperate(
      macAddress: _device.macAddress,
      operation: (device) async {
        final services = await device.discoverServices();
        final nordCoinService = services.firstWhere(
          (s) => s.serviceUuid == nordCoinServiceUuid,
          orElse: () => throw Exception('NordCoin service not found'),
        );
        final txPowerChar = nordCoinService.characteristics.firstWhere(
          (c) => c.characteristicUuid == txPowerCharUuid,
          orElse: () => throw Exception('TX Power characteristic not found'),
        );
        await txPowerChar.write([_settings.txPower]);
      },
      context: context,
      operationMessage: 'Applying TX Power...',
    ).then((success) {
      if (mounted && success) {
        _device.save();
        widget.statusKey.currentState?.loadDevices();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('TX Power applied')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_device.aliasName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAliasSection(),
          const SizedBox(height: 16),

          _buildBatterySection(),
          const SizedBox(height: 16),

          _buildFindButtons(),
          const SizedBox(height: 16),

          _buildUptimeSection(),
          const SizedBox(height: 16),

          _buildDeviceInfoSection(),
          const SizedBox(height: 16),

          _buildSettingsSection(),

          const SizedBox(height: 16),
          _buildRemoveButton(),
        ],
      ),
    );
  }

  Widget _buildAliasSection() {
    return Row(
      children: [
        Expanded(
          child: Text(
            _device.aliasName.isEmpty ? 'Unnamed Device' : _device.aliasName,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit, size: 20),
          onPressed: () => _showEditAliasDialog(),
          tooltip: 'Edit alias',
        ),
      ],
    );
  }

  void _showEditAliasDialog() {
    _aliasController.text = _device.aliasName;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Alias'),
        content: TextField(
          controller: _aliasController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter device alias',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            Navigator.pop(context);
            _saveAlias();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _saveAlias();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _saveAlias() {
    final newAlias = _aliasController.text.trim();
    if (newAlias.isNotEmpty) {
      setState(() {
        _device.aliasName = newAlias;
      });
      _device.save();
      widget.statusKey.currentState?.loadDevices();
    }
  }

  Widget _buildBatterySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Battery',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _batteryPercentage / 100,
            minHeight: 12,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(_batteryColor),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              '${_device.batteryVoltage.toStringAsFixed(2)} V',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
            ),
            const SizedBox(width: 12),
            Text(
              '${_batteryPercentage.round()}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _batteryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFindButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _loudFind,
            icon: const Icon(Icons.volume_up, size: 18),
            label: const Text('Loud Find'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _quietFind,
            icon: const Icon(Icons.volume_off, size: 18),
            label: const Text('Quiet Find'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              foregroundColor: Theme.of(
                context,
              ).colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUptimeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Last Seen Uptime',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _refreshUptime,
                ),
                const SizedBox(width: 8),
                Text(
                  formatMinutes(_device.lastSeenUptimeM),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDeviceInfoSection() {
    final clockColor = alertColorFromDevice(_device);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(
              icon: Icons.access_time,
              label: 'Last seen',
              value:
                  '${formatTimeAgo(_device.lastSeenTime)} (${_device.lastSeenTime.toString().substring(0, 19)})',
              valueColor: clockColor,
            ),
            const SizedBox(height: 4),
            _buildDetailRow(
              icon: Icons.signal_cellular_alt,
              label: 'RSSI',
              value: '${_device.lastSeenRssi} dBm',
              valueColor: dbmColor(_device.lastSeenRssi),
            ),
            const SizedBox(height: 4),
            _buildDetailRow(
              icon: Icons.devices,
              label: 'MAC',
              value: _device.macAddress,
            ),
            const SizedBox(height: 4),
            _buildDetailRow(
              icon: Icons.qr_code,
              label: 'ID',
              value: _device.id,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _device.enabledAlerts = !_device.enabledAlerts;
                });
                _device.save();
                widget.statusKey.currentState?.loadDevices();
              },
              icon: Icon(
                _device.enabledAlerts
                    ? Icons.notifications_off
                    : Icons.notifications_active,
                size: 18,
              ),
              label: Text(
                _device.enabledAlerts ? 'Disable Alerts' : 'Enable Alerts',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _device.enabledAlerts
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: _device.enabledAlerts
                    ? Theme.of(context).colorScheme.onErrorContainer
                    : Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[400]),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: valueColor),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _settingsExpanded = !_settingsExpanded;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _settingsExpanded
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[800]!),
            ),
            child: Row(
              children: [
                Icon(
                  _settingsExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Device Settings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_settingsExpanded) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTxPowerField(),
                  const Divider(),
                  _buildIntField(
                    label: 'Loud Buzzing Duration',
                    value: _settings.loudBuzzingTimeS,
                    suffix: 's',
                    onChanged: (v) {
                      setState(() {
                        _settings.loudBuzzingTimeS = v;
                        _device.save();
                      });
                    },
                  ),
                  _buildIntField(
                    label: 'Silent Buzzing Duration',
                    value: _settings.silentBuzzingTimeS,
                    suffix: 's',
                    onChanged: (v) {
                      setState(() {
                        _settings.silentBuzzingTimeS = v;
                        _device.save();
                      });
                    },
                  ),
                  _buildIntField(
                    label: 'Turning Off Alert Time',
                    value: _settings.turningOffAlertTimeM,
                    suffix: 'min',
                    onChanged: (v) {
                      setState(() {
                        _settings.turningOffAlertTimeM = v;
                        _device.save();
                      });
                    },
                  ),
                  const Divider(),
                  Text(
                    'Alert Actions',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _buildEnumField<ActionType>(
                    label: 'Low Alert',
                    value: _settings.lowAlertAction,
                    options: const {
                      ActionType.none: 'None',
                      ActionType.notification: 'Notification',
                      ActionType.buzzing: 'Buzzing',
                      ActionType.loudAlarm: 'Loud Alarm',
                    },
                    onChanged: (v) {
                      setState(() {
                        _settings.lowAlertAction = v;
                        _device.save();
                      });
                    },
                  ),
                  _buildEnumField<ActionType>(
                    label: 'Medium Alert',
                    value: _settings.mediumAlertAction,
                    options: const {
                      ActionType.none: 'None',
                      ActionType.notification: 'Notification',
                      ActionType.buzzing: 'Buzzing',
                      ActionType.loudAlarm: 'Loud Alarm',
                    },
                    onChanged: (v) {
                      setState(() {
                        _settings.mediumAlertAction = v;
                        _device.save();
                      });
                    },
                  ),
                  _buildEnumField<ActionType>(
                    label: 'High Alert',
                    value: _settings.highAlertAction,
                    options: const {
                      ActionType.none: 'None',
                      ActionType.notification: 'Notification',
                      ActionType.buzzing: 'Buzzing',
                      ActionType.loudAlarm: 'Loud Alarm',
                    },
                    onChanged: (v) {
                      setState(() {
                        _settings.highAlertAction = v;
                        _device.save();
                      });
                    },
                  ),
                  const Divider(),
                  Text(
                    'Lost Device Alert Times',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _buildIntField(
                    label: 'Low Alert Time',
                    value: _settings.lowAlertLostDeviceTimeM,
                    suffix: 'min',
                    onChanged: (v) {
                      setState(() {
                        _settings.lowAlertLostDeviceTimeM = v;
                        _device.save();
                      });
                    },
                  ),
                  _buildIntField(
                    label: 'Medium Alert Time',
                    value: _settings.mediumAlertLostDeviceTimeM,
                    suffix: 'min',
                    onChanged: (v) {
                      setState(() {
                        _settings.mediumAlertLostDeviceTimeM = v;
                        _device.save();
                      });
                    },
                  ),
                  _buildIntField(
                    label: 'High Alert Time',
                    value: _settings.highAlertLostDeviceTimeM,
                    suffix: 'min',
                    onChanged: (v) {
                      setState(() {
                        _settings.highAlertLostDeviceTimeM = v;
                        _device.save();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTxPowerField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TX Power',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _settings.txPower,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                items: txPowerValues.map((v) {
                  return DropdownMenuItem<int>(
                    value: v,
                    child: Text(txPowerToString(v)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _settings.txPower = v;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _applyTxPower,
              child: const Text('Apply'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIntField({
    required String label,
    required int value,
    required void Function(int) onChanged,
    String? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 80,
            child: TextField(
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                suffixText: suffix,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              onChanged: (v) {
                final val = int.tryParse(v) ?? 0;
                onChanged(val);
              },
              controller: TextEditingController(text: value.toString()),
            ),
          ),
        ],
      ),
    );
  }

  void _removeDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text(
          'Are you sure you want to remove "${_device.aliasName.isEmpty ? 'Unnamed Device' : _device.aliasName}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final box = Hive.box(hiveBoxDevices);
      // Maybe using index instead of ID was in fact stupid ;d
      for (final key in box.keys) {
        final value = box.get(key);
        if (value is Device && value.id == _device.id) {
          await box.delete(key);
          break;
        }
      }
      if (mounted) {
        widget.statusKey.currentState?.loadDevices();
        Navigator.of(context).pop();
      }
    }
  }

  Widget _buildRemoveButton() {
    return Center(
      child: OutlinedButton.icon(
        onPressed: _removeDevice,
        icon: const Icon(Icons.delete_forever, size: 18),
        label: const Text('Remove Device'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(color: Theme.of(context).colorScheme.error),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildEnumField<T>({
    required String label,
    required T value,
    required Map<T, String> options,
    required void Function(T) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<T>(
              initialValue: value,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              items: options.entries.map((e) {
                return DropdownMenuItem<T>(value: e.key, child: Text(e.value));
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  onChanged(v);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
