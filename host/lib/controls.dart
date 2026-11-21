import 'dart:io';

import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

/// Whether to draw Mac controls; Material ones are used on Windows and Linux.
bool mac = Platform.isMacOS;

/// Colours and text styles shared by both looks.
class Look {
  Look.of(BuildContext context) : scheme = Theme.of(context).colorScheme, text = Theme.of(context).textTheme;
  final ColorScheme scheme;
  final TextTheme text;

  bool get dark => scheme.brightness == Brightness.dark;
  Color get _ink => dark ? Colors.white : Colors.black;
  Color get secondary => mac ? _ink.withValues(alpha: 0.55) : scheme.onSurfaceVariant;
  Color get hairline => mac ? _ink.withValues(alpha: dark ? 0.12 : 0.1) : scheme.outlineVariant;
  Color get groupFill => mac ? _ink.withValues(alpha: dark ? 0.05 : 0.035) : scheme.surfaceContainerLow;

  TextStyle get title => mac
      ? TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink.withValues(alpha: 0.85))
      : text.titleMedium!;
  TextStyle get body =>
      mac ? TextStyle(fontSize: 13, color: _ink.withValues(alpha: 0.85), height: 1.25) : text.bodyLarge!;
  TextStyle get caption => mac
      ? TextStyle(fontSize: 11, color: secondary, height: 1.3)
      : text.bodySmall!.copyWith(color: scheme.onSurfaceVariant);
  TextStyle get header => mac
      ? TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondary)
      : text.labelLarge!.copyWith(color: scheme.primary);
}

/// A heading above a [Group].
class GroupHeader extends StatelessWidget {
  const GroupHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(mac ? title.toUpperCase() : title, style: Look.of(context).header),
  );
}

/// A rounded box of rows with hairlines between them.
class Group extends StatelessWidget {
  const Group({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Container(
      decoration: BoxDecoration(
        color: look.groupFill,
        borderRadius: BorderRadius.circular(mac ? 8 : 12),
        border: Border.all(color: look.hairline, width: mac ? 0.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(height: mac ? 0.5 : 1, margin: const EdgeInsets.only(left: 12), color: look.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One setting: what it is on the left, its control on the right.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.title, this.detail, this.detailColor, this.control, this.below});
  final String title;
  final String? detail;
  final Color? detailColor;
  final Widget? control;

  /// Shown under the title across the full width, e.g. a row of buttons.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final look = Look.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: mac ? 9 : 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: look.body),
                    if (detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SelectableText(detail!, style: look.caption.copyWith(color: detailColor)),
                      ),
                  ],
                ),
              ),
              if (control != null) ...[const SizedBox(width: 16), control!],
            ],
          ),
          if (below != null) Padding(padding: const EdgeInsets.only(top: 8), child: below),
        ],
      ),
    );
  }
}

class Toggle extends StatelessWidget {
  const Toggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) =>
      mac ? MacosSwitch(value: value, onChanged: onChanged) : Switch(value: value, onChanged: onChanged);
}

class Field extends StatelessWidget {
  const Field({
    super.key,
    required this.controller,
    required this.width,
    this.hint,
    this.obscure = false,
    this.number = false,
    this.onChanged,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final double width;
  final String? hint;
  final bool obscure;
  final bool number;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: mac
        ? MacosTextField(
            controller: controller,
            placeholder: hint,
            obscureText: obscure,
            maxLines: 1,
            keyboardType: number ? TextInputType.number : null,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          )
        : TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: number ? TextInputType.number : null,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
  );
}

class ActionButton extends StatelessWidget {
  const ActionButton(this.label, {super.key, required this.onPressed, this.primary = false});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    if (mac) {
      return PushButton(
        controlSize: ControlSize.regular,
        secondary: !primary,
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return primary
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton(onPressed: onPressed, child: Text(label));
  }
}

/// A drop-down list.
class Choice<T> extends StatelessWidget {
  const Choice({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    if (mac) {
      return MacosPopupButton<T>(
        value: value,
        onChanged: (v) => onChanged(v as T),
        items: [for (final e in options.entries) MacosPopupMenuItem(value: e.key, child: Text(e.value))],
      );
    }
    return DropdownButton<T>(
      value: value,
      isDense: true,
      onChanged: (v) => onChanged(v as T),
      items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
    );
  }
}
