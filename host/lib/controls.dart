import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:material_ui/material_ui.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:oot_ui/oot_ui.dart';

export 'package:oot_ui/oot_ui.dart' show DesktopLook;

/// Which system's controls to draw: macos_ui on a Mac, fluent_ui on
/// Windows, the GNOME look on Linux.
DesktopLook desktopLook = DesktopLook.platform;

T _pick<T>(T mac, T windows, T linux) => switch (desktopLook) {
  DesktopLook.mac => mac,
  DesktopLook.windows => windows,
  DesktopLook.linux => linux,
};

/// Colours, text styles and measures of the current [desktopLook].
class Look {
  Look.of(BuildContext context) : scheme = Theme.of(context).colorScheme;
  final ColorScheme scheme;

  bool get dark => scheme.brightness == Brightness.dark;
  Color get _ink => dark ? Colors.white : Colors.black;
  Color get label => _ink.withValues(alpha: dark ? _pick(0.85, 1.0, 1.0) : _pick(0.85, 0.9, 0.8));
  Color get secondary => _ink.withValues(alpha: dark ? _pick(0.55, 0.77, 0.55) : _pick(0.55, 0.62, 0.45));
  Color get hairline => _ink.withValues(alpha: dark ? _pick(0.12, 0.09, 0.1) : _pick(0.1, 0.07, 0.08));

  /// The window behind the groups.
  Color get window => _pick(
    dark ? const Color(0xFF1E1E1E) : const Color(0xFFECECEC),
    dark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
    Adwaita(dark).window,
  );

  /// A group's outline and fill.
  BoxDecoration get group => desktopLook == DesktopLook.linux
      ? adwaitaCard(Adwaita(dark))
      : BoxDecoration(
          color: _pick(
            _ink.withValues(alpha: dark ? 0.05 : 0.035),
            dark ? const Color(0x0DFFFFFF) : const Color(0xB3FFFFFF),
            null,
          ),
          borderRadius: BorderRadius.circular(_pick(8, 4, 12)),
          border: Border.all(color: hairline, width: hairlineWidth),
        );
  double get hairlineWidth => _pick(0.5, 1, 1);

  /// How far the lines between the rows of a group are indented.
  double get hairlineInset => _pick(12, 0, 0);
  EdgeInsets get rowPadding => _pick(
    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  static String get fontFamily => _pick('.AppleSystemUIFont', 'Segoe UI Variable Text', adwaitaFont);

  TextStyle _text(double size, FontWeight weight, Color color, [double height = 1.25]) => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: _pick(null, const ['Segoe UI'], adwaitaFontFallback),
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: 0,
  );

  FontWeight get _strong => _pick(FontWeight.w600, FontWeight.w600, FontWeight.w700);
  TextStyle get title => _text(_pick(15, 16, 16), _strong, label);
  TextStyle get body => _text(_pick(13, 14, 15), FontWeight.w400, label);
  TextStyle get caption => _text(_pick(11, 12, 12), FontWeight.w400, secondary, 1.3);
  TextStyle get header => _pick(
    _text(11, FontWeight.w600, secondary),
    _text(14, FontWeight.w600, label),
    _text(15, FontWeight.w700, label),
  );
}

/// A heading above a [Group].
class GroupHeader extends StatelessWidget {
  const GroupHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(desktopLook == DesktopLook.mac ? title.toUpperCase() : title, style: Look.of(context).header),
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
      decoration: look.group,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                height: look.hairlineWidth,
                margin: EdgeInsets.only(left: look.hairlineInset),
                color: look.hairline,
              ),
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
      padding: look.rowPadding,
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
  Widget build(BuildContext context) => switch (desktopLook) {
    DesktopLook.mac => MacosSwitch(value: value, onChanged: onChanged),
    DesktopLook.windows => fluent.ToggleSwitch(checked: value, onChanged: onChanged),
    DesktopLook.linux => AdwSwitch(value: value, onChanged: onChanged),
  };
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
  Widget build(BuildContext context) {
    final keyboard = number ? TextInputType.number : null;
    return SizedBox(
      width: width,
      child: switch (desktopLook) {
        DesktopLook.mac => MacosTextField(
          controller: controller,
          placeholder: hint,
          obscureText: obscure,
          maxLines: 1,
          keyboardType: keyboard,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
        ),
        DesktopLook.windows => fluent.TextBox(
          controller: controller,
          placeholder: hint,
          obscureText: obscure,
          maxLines: 1,
          keyboardType: keyboard,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
        ),
        DesktopLook.linux => TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          style: Look.of(context).body,
          decoration: InputDecoration(hintText: hint),
          onChanged: onChanged,
          onSubmitted: onSubmitted,
        ),
      },
    );
  }
}

class ActionButton extends StatelessWidget {
  const ActionButton(this.label, {super.key, required this.onPressed, this.primary = false});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    switch (desktopLook) {
      case DesktopLook.mac:
        return PushButton(
          controlSize: ControlSize.regular,
          secondary: !primary,
          onPressed: onPressed,
          child: Text(label),
        );
      case DesktopLook.windows:
        return primary
            ? fluent.FilledButton(onPressed: onPressed, child: Text(label))
            : fluent.Button(onPressed: onPressed, child: Text(label));
      case DesktopLook.linux:
        return primary
            ? FilledButton(onPressed: onPressed, child: Text(label))
            : OutlinedButton(onPressed: onPressed, child: Text(label));
    }
  }
}

/// A drop-down list.
class Choice<T> extends StatelessWidget {
  const Choice({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => switch (desktopLook) {
    DesktopLook.mac => MacosPopupButton<T>(
      value: value,
      onChanged: (v) => onChanged(v as T),
      items: [for (final e in options.entries) MacosPopupMenuItem(value: e.key, child: Text(e.value))],
    ),
    DesktopLook.windows => fluent.ComboBox<T>(
      value: value,
      onChanged: (v) => onChanged(v as T),
      items: [for (final e in options.entries) fluent.ComboBoxItem(value: e.key, child: Text(e.value))],
    ),
    DesktopLook.linux => AdwDropDown<T>(value: value, options: options, onChanged: onChanged),
  };
}
