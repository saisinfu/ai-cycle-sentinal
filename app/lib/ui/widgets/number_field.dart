import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Labeled number input that saves when editing finishes.
class NumberField extends StatefulWidget {
  const NumberField({super.key, required this.label, required this.value, required this.onSaved, this.decimals = 0, this.suffix});

  final String label;
  final double value;
  final ValueChanged<double> onSaved;
  final int decimals;
  final String? suffix;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _c = TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();

  String _fmt(double v) => widget.decimals == 0 ? v.round().toString() : v.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) _c.text = _fmt(widget.value);
  }

  void _save() {
    final v = double.tryParse(_c.text.replaceAll(',', '').trim());
    if (v == null || v < 0) {
      _c.text = _fmt(widget.value);
      return;
    }
    if (v != widget.value) widget.onSaved(v);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(widget.label, style: const TextStyle(fontSize: 13.5, height: 1.35))),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _c,
              focusNode: _focus,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _save(),
              style: const TextStyle(fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]),
              decoration: InputDecoration(
                suffixText: widget.suffix,
                suffixStyle: const TextStyle(color: AppColors.muted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
