import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';

/// Labelled text field. [serverError] shows a field error returned by the API
/// (from AppException.fieldErrors) until the user edits the field.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.validator,
    this.serverError,
    this.required = false,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.obscure = false,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textInputAction,
    this.helper,
    this.readOnly = false,
    this.onTap,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final Validator? validator;
  final String? serverError;
  final bool required;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final int? maxLength;
  final bool enabled;
  final bool obscure;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final String? helper;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: obscure ? 1 : maxLines,
      maxLength: maxLength,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      obscureText: obscure,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      autofocus: autofocus,
      textInputAction: textInputAction,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        helperText: helper,
        errorText: serverError,
        counterText: '',
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 18),
        suffixIcon: suffix,
      ),
    );
  }
}

/// Integer / decimal input formatters.
class Formatters {
  Formatters._();
  static final digits = [FilteringTextInputFormatter.digitsOnly];
  static final signedInt = [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))];
  static final decimal = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))];
}

class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.itemLabel,
    this.validator,
    this.required = false,
    this.serverError,
    this.enabled = true,
    this.hint,
  });

  final String label;
  final List<T> items;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String Function(T item)? itemLabel;
  final FormFieldValidator<T>? validator;
  final bool required;
  final String? serverError;
  final bool enabled;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: items.contains(value) ? value : null,
      isExpanded: true,
      items: [for (final i in items) DropdownMenuItem<T>(value: i, child: Text(itemLabel?.call(i) ?? i.toString(), overflow: TextOverflow.ellipsis))],
      onChanged: enabled ? onChanged : null,
      validator: validator ?? (required ? (v) => v == null ? '$label is required' : null : null),
      style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
      borderRadius: BorderRadius.circular(Radii.md),
      decoration: InputDecoration(labelText: required ? '$label *' : label, errorText: serverError, hintText: hint),
    );
  }
}

/// Two fields side by side that stack on narrow widths.
class FieldRow extends StatelessWidget {
  const FieldRow({super.key, required this.children, this.gap = Gap.lg, this.breakpoint = 480});
  final List<Widget> children;
  final double gap;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(width: gap), Expanded(child: children[i])],
      ]);
    });
  }
}

/// Vertical list of fields with consistent spacing.
class FormColumn extends StatelessWidget {
  const FormColumn({super.key, required this.children, this.gap = Gap.lg});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
    ]);
  }
}

class FormSectionTitle extends StatelessWidget {
  const FormSectionTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
          if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      Switch(value: value, onChanged: onChanged),
    ]);
  }
}

/// Compact numeric cell editor used in quantity grids (allocation, approval, receiving).
class QuantityInput extends StatefulWidget {
  const QuantityInput({super.key, required this.value, required this.onChanged, this.max, this.min = 0, this.width = 88, this.enabled = true, this.error = false});
  final int value;
  final ValueChanged<int> onChanged;
  final int? max;
  final int min;
  final double width;
  final bool enabled;
  final bool error;

  @override
  State<QuantityInput> createState() => _QuantityInputState();
}

class _QuantityInputState extends State<QuantityInput> {
  late final TextEditingController _c = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant QuantityInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (int.tryParse(_c.text) != widget.value) _c.text = '${widget.value}';
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final over = widget.max != null && widget.value > widget.max!;
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _c,
        enabled: widget.enabled,
        textAlign: TextAlign.right,
        keyboardType: TextInputType.number,
        inputFormatters: Formatters.digits,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: over || widget.error ? AppColors.danger : AppColors.textPrimary),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          enabledBorder: over || widget.error
              ? OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.sm), borderSide: const BorderSide(color: AppColors.danger))
              : null,
        ),
        onChanged: (v) {
          final n = int.tryParse(v) ?? 0;
          widget.onChanged(n < widget.min ? widget.min : n);
        },
      ),
    );
  }
}
