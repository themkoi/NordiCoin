import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../consts.dart';
import '../data.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Settings _settings;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final box = Hive.box(hiveBoxSettings);
    _settings = box.get(0) as Settings;
    setState(() {
      _hasChanges = false;
    });
  }

  Future<void> _saveSettings() async {
    await _settings.save();
    setState(() {
      _hasChanges = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
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
        _hasChanges = true;
      });
      await box.put(0, _settings);
      setState(() {
        _hasChanges = false;
      });
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
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
          Expanded(
            child: Text(label),
          ),
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
          Expanded(
            child: Text(label),
          ),
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<T>(
              value: value,
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
                return DropdownMenuItem<T>(
                  value: e.key,
                  child: Text(e.value),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          _buildSection(
            'Alert Schedule',
            [
              _buildSwitchField(
                label: 'Manual Override',
                value: _settings.alertsManualOverride,
                onChanged: (v) {
                  setState(() {
                    _settings.alertsManualOverride = v;
                    _hasChanges = true;
                  });
                },
              ),
              const Divider(),
              Text(
                'Alerts OFF from',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _buildIntField(
                label: '  Hour',
                value: _settings.alertsOffAfterTimeH,
                onChanged: (v) {
                  setState(() {
                    _settings.alertsOffAfterTimeH = v;
                    _hasChanges = true;
                  });
                },
                suffix: 'h',
              ),
              _buildIntField(
                label: '  Minute',
                value: _settings.alertsOffAfterTimeM,
                onChanged: (v) {
                  setState(() {
                    _settings.alertsOffAfterTimeM = v;
                    _hasChanges = true;
                  });
                },
                suffix: 'm',
              ),
              const Divider(),
              Text(
                'Alerts ON from',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _buildIntField(
                label: '  Hour',
                value: _settings.alertsOnAfterTimeH,
                onChanged: (v) {
                  setState(() {
                    _settings.alertsOnAfterTimeH = v;
                    _hasChanges = true;
                  });
                },
                suffix: 'h',
              ),
              _buildIntField(
                label: '  Minute',
                value: _settings.alertsOnAfterTimeM,
                onChanged: (v) {
                  setState(() {
                    _settings.alertsOnAfterTimeM = v;
                    _hasChanges = true;
                  });
                },
                suffix: 'm',
              ),
            ],
          ),
          _buildSection(
            'Scan Settings',
            [
              _buildIntField(
                label: 'Scan Frequency',
                value: _settings.scanFrequencyTimeM,
                onChanged: (v) {
                  setState(() {
                    _settings.scanFrequencyTimeM = v;
                    _hasChanges = true;
                  });
                },
                suffix: 'min',
              ),
            ],
          ),
          _buildSection(
            'Default Device Settings',
            [
              _buildIntField(
                label: 'Loud Buzzing Duration',
                value: _settings.defaultDeviceSettings.loudBuzzingTimeS,
                onChanged: (v) {
                  setState(() {
                    _settings.defaultDeviceSettings.loudBuzzingTimeS = v;
                    _hasChanges = true;
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
                    _hasChanges = true;
                  });
                },
                suffix: 's',
              ),
              _buildIntField(
                label: 'TX Power',
                value: _settings.defaultDeviceSettings.txPower,
                onChanged: (v) {
                  setState(() {
                    _settings.defaultDeviceSettings.txPower = v;
                    _hasChanges = true;
                  });
                },
              ),
              _buildIntField(
                label: 'Turning Off Alert Time',
                value: _settings.defaultDeviceSettings.turningOffAlertTimeM,
                onChanged: (v) {
                  setState(() {
                    _settings.defaultDeviceSettings.turningOffAlertTimeM = v;
                    _hasChanges = true;
                  });
                },
                suffix: 'min',
              ),
              const Divider(),
              Text(
                'Alert Actions',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _buildEnumField<ActionType>(
                label: '  Low Alert',
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
                    _hasChanges = true;
                  });
                },
              ),
              _buildEnumField<ActionType>(
                label: '  Medium Alert',
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
                    _hasChanges = true;
                  });
                },
              ),
              _buildEnumField<ActionType>(
                label: '  High Alert',
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
                    _hasChanges = true;
                  });
                },
              ),
              const Divider(),
              Text(
                'Lost Device Alert Times',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _buildIntField(
                label: '  Low Alert Time',
                value: _settings.defaultDeviceSettings.lowAlertLostDeviceTimeM,
                onChanged: (v) {
                  setState(() {
                    _settings.defaultDeviceSettings.lowAlertLostDeviceTimeM = v;
                    _hasChanges = true;
                  });
                },
                suffix: 'min',
              ),
              _buildIntField(
                label: '  Medium Alert Time',
                value: _settings.defaultDeviceSettings.mediumAlertLostDeviceTimeM,
                onChanged: (v) {
                  setState(() {
                    _settings.defaultDeviceSettings.mediumAlertLostDeviceTimeM = v;
                    _hasChanges = true;
                  });
                },
                suffix: 'min',
              ),
              _buildIntField(
                label: '  High Alert Time',
                value: _settings.defaultDeviceSettings.highAlertLostDeviceTimeM,
                onChanged: (v) {
                  setState(() {
                    _settings.defaultDeviceSettings.highAlertLostDeviceTimeM = v;
                    _hasChanges = true;
                  });
                },
                suffix: 'min',
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Save and Reset buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _hasChanges ? _saveSettings : null,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasChanges
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetToDefaults,
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset to Defaults'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
