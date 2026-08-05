import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../consts.dart';
import '../data.dart';
import '../service/actions.dart';
import '../utils/ble.dart';
import '../utils/spinbox.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Settings _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final box = Hive.box(hiveBoxSettings);
    _settings = box.get(0) as Settings;
  }

  void _autoSave() {
    _settings.save();
  }

  void _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'Are you sure you want to reset all settings to their default values? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final box = Hive.box(hiveBoxSettings);
      setState(() {
        _settings = Settings(defaultDeviceSettings: OnAppDevice());
      });
      await box.put(0, _settings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings reset to defaults')),
        );
      }
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
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
          SpinBox(value: value, suffix: suffix, onChanged: onChanged),
        ],
      ),
    );
  }

  Future<void> _selectTime({
    required BuildContext context,
    required int initialHour,
    required int initialMinute,
    required void Function(int hour, int minute) onTimeSelected,
  }) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onTimeSelected(picked.hour, picked.minute);
    }
  }

  Widget _buildTimeField({
    required String label,
    required int hour,
    required int minute,
    required void Function(int hour, int minute) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          InkWell(
            onTap: () => _selectTime(
              context: context,
              initialHour: hour,
              initialMinute: minute,
              onTimeSelected: onChanged,
            ),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.access_time,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
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

  Widget _buildSwitchField({
    required String label,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label)),
          Switch(
            value: value,
            onChanged: (v) {
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTxPowerField({
    required String label,
    required int value,
    required void Function(int) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<int>(
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
              items: txPowerValues.map((v) {
                return DropdownMenuItem<int>(
                  value: v,
                  child: Text(txPowerToString(v)),
                );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          _buildSection('Alert Schedule', [
            FutureBuilder<({bool isOn, String reason})>(
              future: Future.value(areAlertsOn()),
              builder: (context, snapshot) {
                final status = snapshot.data;
                if (status == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        status.isOn ? Icons.check_circle : Icons.cancel,
                        color: status.isOn ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Alerts ${status.isOn ? "ON" : "OFF"} — ${status.reason}',
                          style: TextStyle(
                            color: status.isOn ? Colors.green : Colors.red,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(),
            _buildSwitchField(
              label: 'Manual Override',
              value: _settings.alertsManualOverride,
              onChanged: (v) {
                setState(() {
                  _settings.alertsManualOverride = v;
                  _autoSave();
                });
              },
            ),
            if (_settings.alertsManualOverride)
              _buildSwitchField(
                label: 'Override Alert',
                value: _settings.alertsManualOverrideAlert,
                onChanged: (v) {
                  setState(() {
                    _settings.alertsManualOverrideAlert = v;
                    _autoSave();
                  });
                },
              ),
            const Divider(),
            Text(
              'Alerts OFF from',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _buildTimeField(
              label: 'Time',
              hour: _settings.alertsOffAfterTimeH,
              minute: _settings.alertsOffAfterTimeM,
              onChanged: (h, m) {
                setState(() {
                  _settings.alertsOffAfterTimeH = h;
                  _settings.alertsOffAfterTimeM = m;
                  _autoSave();
                });
              },
            ),
            const Divider(),
            Text(
              'Alerts ON from',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _buildTimeField(
              label: 'Time',
              hour: _settings.alertsOnAfterTimeH,
              minute: _settings.alertsOnAfterTimeM,
              onChanged: (h, m) {
                setState(() {
                  _settings.alertsOnAfterTimeH = h;
                  _settings.alertsOnAfterTimeM = m;
                  _autoSave();
                });
              },
            ),
          ]),
          _buildSection('Scan Settings', [
            _buildIntField(
              label: 'Scan Frequency',
              value: _settings.scanFrequencyTimeM,
              onChanged: (v) {
                setState(() {
                  _settings.scanFrequencyTimeM = v;
                  _autoSave();
                });
              },
              suffix: 'min',
            ),
            _buildIntField(
              label: 'Scan Duration',
              value: _settings.scanDurationS,
              onChanged: (v) {
                setState(() {
                  _settings.scanDurationS = v;
                  _autoSave();
                });
              },
              suffix: 's',
            ),
          ]),
          _buildSection('Default Device Settings', [
            _buildIntField(
              label: 'Loud Buzzing Duration',
              value: _settings.defaultDeviceSettings.loudBuzzingTimeS,
              onChanged: (v) {
                setState(() {
                  _settings.defaultDeviceSettings.loudBuzzingTimeS = v;
                  _autoSave();
                });
              },
              suffix: 's',
            ),
            _buildIntField(
              label: 'Silent Buzzing Duration',
              value: _settings.defaultDeviceSettings.silentBuzzingTimeS,
              onChanged: (v) {
                setState(() {
                  _settings.defaultDeviceSettings.silentBuzzingTimeS = v;
                  _autoSave();
                });
              },
              suffix: 's',
            ),
            _buildTxPowerField(
              label: 'TX Power',
              value: _settings.defaultDeviceSettings.txPower,
              onChanged: (v) {
                setState(() {
                  _settings.defaultDeviceSettings.txPower = v;
                  _autoSave();
                });
              },
            ),
            _buildIntField(
              label: 'Turning Off Alert Time',
              value: _settings.defaultDeviceSettings.turningOffAlertTimeM,
              onChanged: (v) {
                setState(() {
                  _settings.defaultDeviceSettings.turningOffAlertTimeM = v;
                  _autoSave();
                });
              },
              suffix: 'min',
            ),
            const Divider(),
            Text('Alert Actions', style: Theme.of(context).textTheme.bodySmall),
            _buildEnumField<ActionType>(
              label: 'Low Alert',
              value: _settings.defaultDeviceSettings.lowAlertAction,
              options: const {
                ActionType.none: 'None',
                ActionType.notification: 'Notification',
                ActionType.buzzing: 'Buzzing',
                ActionType.loudAlarm: 'Loud Alarm',
              },
              onChanged: (v) {
                setState(() {
                  _settings.defaultDeviceSettings.lowAlertAction = v;
                  _autoSave();
                });
              },
            ),
            _buildEnumField<ActionType>(
              label: 'Medium Alert',
              value: _settings.defaultDeviceSettings.mediumAlertAction,
              options: const {
                ActionType.none: 'None',
                ActionType.notification: 'Notification',
                ActionType.buzzing: 'Buzzing',
                ActionType.loudAlarm: 'Loud Alarm',
              },
              onChanged: (v) {
                setState(() {
                  _settings.defaultDeviceSettings.mediumAlertAction = v;
                  _autoSave();
                });
              },
            ),
            _buildEnumField<ActionType>(
              label: 'High Alert',
              value: _settings.defaultDeviceSettings.highAlertAction,
              options: const {
                ActionType.none: 'None',
                ActionType.notification: 'Notification',
                ActionType.buzzing: 'Buzzing',
                ActionType.loudAlarm: 'Loud Alarm',
              },
              onChanged: (v) {
                setState(() {
                  _settings.defaultDeviceSettings.highAlertAction = v;
                  _autoSave();
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
              value: _settings.defaultDeviceSettings.lowAlertLostDeviceTimeM,
              onChanged: (v) {
                setState(() {
                  _settings.defaultDeviceSettings.lowAlertLostDeviceTimeM = v;
                  _autoSave();
                });
              },
              suffix: 'min',
            ),
            _buildIntField(
              label: 'Medium Alert Time',
              value: _settings.defaultDeviceSettings.mediumAlertLostDeviceTimeM,
              onChanged: (v) {
                setState(() {
                  _settings.defaultDeviceSettings.mediumAlertLostDeviceTimeM =
                      v;
                  _autoSave();
                });
              },
              suffix: 'min',
            ),
            _buildIntField(
              label: 'High Alert Time',
              value: _settings.defaultDeviceSettings.highAlertLostDeviceTimeM,
              onChanged: (v) {
                setState(() {
                  _settings.defaultDeviceSettings.highAlertLostDeviceTimeM = v;
                  _autoSave();
                });
              },
              suffix: 'min',
            ),
          ]),
          const SizedBox(height: 16),
          // Reset button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _resetToDefaults,
                icon: const Icon(Icons.restore),
                label: const Text('Reset to Defaults'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _showTestActionDialog,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Test Action'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showTestActionDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => const _TestActionDialog(),
    );
  }
}

class _TestActionDialog extends StatefulWidget {
  const _TestActionDialog();

  @override
  State<_TestActionDialog> createState() => _TestActionDialogState();
}

class _TestActionDialogState extends State<_TestActionDialog> {
  ActionType? _selectedAction;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Test Action'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select an action to test:'),
          const SizedBox(height: 16),
          DropdownButtonFormField<ActionType>(
            initialValue: _selectedAction,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items:
                const {
                  ActionType.notification: 'Notification',
                  ActionType.buzzing: 'Buzzing (Vibrate)',
                  ActionType.loudAlarm: 'Loud Alarm (Play Sound)',
                }.entries.map((e) {
                  return DropdownMenuItem<ActionType>(
                    value: e.key,
                    child: Text(e.value),
                  );
                }).toList(),
            onChanged: (v) {
              setState(() {
                _selectedAction = v;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedAction != null
              ? () async {
                  Navigator.of(context).pop();
                  await executeAction(_selectedAction!, 'Test action executed');
                }
              : null,
          child: const Text('Execute'),
        ),
      ],
    );
  }
}
