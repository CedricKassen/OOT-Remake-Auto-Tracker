/// The controls of the desktop panes, each drawn with the widgets of the
/// system the window's [DesktopStyle] is for.
library;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:material_ui/material_ui.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:oot_ui/oot_ui.dart';

import 'style.dart';

class DesktopButton extends StatelessWidget {
  const DesktopButton(this.label, {super.key, required this.onPressed, this.primary = true, this.small = false});
  final String label;
  final VoidCallback? onPressed;

  /// The action the row or page is about; drawn in the accent colour.
  final bool primary;
  final bool small;

  @override
  Widget build(BuildContext context) {
    switch (DesktopStyle.of(context).look) {
      case DesktopLook.mac:
        return PushButton(
          controlSize: small ? ControlSize.small : ControlSize.regular,
          secondary: !primary,
          onPressed: onPressed,
          child: Text(label),
        );
      case DesktopLook.windows:
        return primary
            ? fluent.FilledButton(onPressed: onPressed, child: Text(label))
            : fluent.Button(onPressed: onPressed, child: Text(label));
      case DesktopLook.linux:
        final style = small
            ? const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, 30)),
                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
              )
            : null;
        return primary
            ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
            : OutlinedButton(onPressed: onPressed, style: style, child: Text(label));
    }
  }
}

class DesktopCheckbox extends StatelessWidget {
  const DesktopCheckbox({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return switch (DesktopStyle.of(context).look) {
      DesktopLook.mac => MacosCheckbox(value: value, size: 15, onChanged: onChanged),
      DesktopLook.windows => fluent.Checkbox(
        checked: value,
        onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
      ),
      DesktopLook.linux => SizedBox.square(
        dimension: 20,
        child: Checkbox(value: value, onChanged: onChanged == null ? null : (v) => onChanged(v ?? false)),
      ),
    };
  }
}

class DesktopSwitch extends StatelessWidget {
  const DesktopSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => switch (DesktopStyle.of(context).look) {
    DesktopLook.mac => MacosSwitch(value: value, onChanged: onChanged),
    DesktopLook.windows => fluent.ToggleSwitch(checked: value, onChanged: onChanged),
    DesktopLook.linux => AdwSwitch(value: value, onChanged: onChanged),
  };
}

class DesktopTextField extends StatelessWidget {
  const DesktopTextField({
    super.key,
    required this.controller,
    this.placeholder,
    this.obscure = false,
    this.onSubmitted,
  });
  final TextEditingController? controller;
  final String? placeholder;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => switch (DesktopStyle.of(context).look) {
    DesktopLook.mac => MacosTextField(
      controller: controller,
      placeholder: placeholder,
      obscureText: obscure,
      maxLines: 1,
      onSubmitted: onSubmitted,
    ),
    DesktopLook.windows => fluent.TextBox(
      controller: controller,
      placeholder: placeholder,
      obscureText: obscure,
      maxLines: 1,
      onSubmitted: onSubmitted,
    ),
    DesktopLook.linux => TextField(
      controller: controller,
      obscureText: obscure,
      style: DesktopStyle.of(context).body,
      decoration: InputDecoration(hintText: placeholder),
      onSubmitted: onSubmitted,
    ),
  };
}

class DesktopTooltip extends StatelessWidget {
  const DesktopTooltip({super.key, required this.message, required this.child});
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (DesktopStyle.of(context).look) {
    DesktopLook.mac => MacosTooltip(message: message, child: child),
    DesktopLook.windows => fluent.Tooltip(message: message, child: child),
    DesktopLook.linux => Tooltip(message: message, child: child),
  };
}
