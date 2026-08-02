import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpinBox extends StatefulWidget {
  final int value;
  final String? suffix;
  final void Function(int) onChanged;

  const SpinBox({
    super.key,
    required this.value,
    this.suffix,
    required this.onChanged,
  });

  @override
  State<SpinBox> createState() => _SpinBoxState();
}

class _SpinBoxState extends State<SpinBox> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  late int _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _controller = TextEditingController(text: _currentValue.toString());
  }

  @override
  void didUpdateWidget(SpinBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentValue != widget.value) {
      _currentValue = widget.value;
      if (!_controller.selection.isValid) {
        _controller.text = _currentValue.toString();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _changeValue(int delta) {
    final newValue = _currentValue + delta;
    if (newValue < 0) return;
    _currentValue = newValue;
    _focusNode.unfocus();
    _controller.text = newValue.toString();
    widget.onChanged(newValue);
  }

  void _onTextChanged(String text) {
    final cleaned = text.replaceAll(RegExp(r'^0+(?=\d)'), '');
    if (cleaned.isEmpty) {
      _currentValue = 0;
      widget.onChanged(0);
      _controller.text = '0';
      _controller.selection = TextSelection.collapsed(offset: 1);
      return;
    }
    final val = int.tryParse(cleaned);
    if (val != null && val != _currentValue) {
      _currentValue = val;
      widget.onChanged(val);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _changeValue(-1),
            child: SizedBox(
              width: 32,
              height: 36,
              child: Icon(
                Icons.remove,
                size: 18,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 90,
          child: TextField(
            focusNode: _focusNode,
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _LeadingZeroRemover(),
            ],
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              suffixText: widget.suffix,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.colorScheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
              isDense: true,
            ),
            onChanged: _onTextChanged,
          ),
        ),
        const SizedBox(width: 4),
        Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _changeValue(1),
            child: SizedBox(
              width: 32,
              height: 36,
              child: Icon(
                Icons.add,
                size: 18,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeadingZeroRemover extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final cleaned = text.replaceAll(RegExp(r'^0+(?=\d)'), '');
    if (cleaned == text) return newValue;
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}
