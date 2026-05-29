import 'package:flutter/material.dart';
import 'constants.dart';
import 'models.dart';

// ─── Barra de cuenta atrás ────────────────────────────────────
class CountdownBar extends StatelessWidget {
  final AlarmStateData data;
  final Color          color;
  const CountdownBar({super.key, required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final remaining = data.remaining;
    final total     = data.delay ?? 1;
    final progress  = remaining / total;
    final mins      = remaining ~/ 60;
    final secs      = remaining % 60;
    final timeStr   = mins > 0
        ? '${mins}m ${secs.toString().padLeft(2, '0')}s'
        : '${secs}s';

    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(
          data.state == AlarmState.arming
              ? 'Tiempo para armarse'
              : 'Tiempo para disparar',
          style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
        Text(timeStr,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: color.withOpacity(0.15),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
        ),
      ),
    ]);
  }
}

// ─── Advertencia sensores abiertos ───────────────────────────
class OpenSensorsWarning extends StatelessWidget {
  final List<String> sensors;
  const OpenSensorsWarning({super.key, required this.sensors});

  String _friendlyName(String entityId) {
    return entityId
        .split('.')
        .last
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kRed.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.sensor_door_rounded, color: kRed, size: 16),
          SizedBox(width: 6),
          Text('Sensores abiertos',
              style: TextStyle(
                  color: kRed, fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        const SizedBox(height: 6),
        ...sensors.map((s) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(children: [
            const Icon(Icons.circle, color: kRed, size: 6),
            const SizedBox(width: 8),
            Text(_friendlyName(s),
                style: const TextStyle(color: kText, fontSize: 13)),
          ]),
        )),
      ]),
    );
  }
}

// ─── Botón de acción ──────────────────────────────────────────
class ActionButton extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final Color        color;
  final bool         active, busy;
  final VoidCallback onTap;

  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.active,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? kSurface : Colors.white;

    return GestureDetector(
      onTap: (busy || active) ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.18) : bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? color : color.withOpacity(0.4),
              width: active ? 2 : 1.5),
          boxShadow: active
              ? [BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: 18,
                  spreadRadius: 1)]
              : [],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? color : color.withOpacity(0.65), size: 38),
          const SizedBox(height: 10),
          Text(label,
              style: TextStyle(
                  color: active ? color : kSubtext,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
        ]),
      ),
    );
  }
}

// ─── Sin configuración ────────────────────────────────────────
class NoConfigWidget extends StatelessWidget {
  final VoidCallback onConfig;
  const NoConfigWidget({super.key, required this.onConfig});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.settings_suggest_outlined, color: kSubtext, size: 72),
          const SizedBox(height: 20),
          const Text('Configura la conexión primero',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSubtext, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Ir a configuración'),
            onPressed: onConfig,
            style: ElevatedButton.styleFrom(
                backgroundColor: kBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
          ),
        ]),
      ),
    );
  }
}

// ─── Selector de tema ─────────────────────────────────────────
class ThemeOption extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final bool         selected;
  final VoidCallback onTap;

  const ThemeOption({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? kBlue.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? kBlue : kSubtext.withOpacity(0.3),
                width: selected ? 1.5 : 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: selected ? kBlue : kSubtext, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: selected ? kBlue : kSubtext,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }
}

// ─── Tarjeta de sección (configuración) ──────────────────────
class SectionCard extends StatelessWidget {
  final String       title;
  final List<Widget> children;
  final Color        surfaceColor;
  final Color        textColor;

  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    required this.surfaceColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(title,
            style: TextStyle(
                color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: surfaceColor, borderRadius: BorderRadius.circular(18)),
        child: Column(children: children),
      ),
    ]);
  }
}

// ─── Campo de texto ───────────────────────────────────────────
class InputField extends StatelessWidget {
  final TextEditingController ctrl;
  final String        label, hint;
  final IconData      icon;
  final bool          obscure;
  final VoidCallback? onToggle;
  final TextInputType? keyboardType;
  final Color         fieldBg, subtextColor, textColor;

  const InputField({
    super.key,
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    required this.fieldBg,
    required this.subtextColor,
    required this.textColor,
    this.obscure      = false,
    this.onToggle,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: textColor, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subtextColor, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: subtextColor.withOpacity(0.45), fontSize: 12),
        prefixIcon: Icon(icon, color: subtextColor, size: 20),
        suffixIcon: onToggle != null
            ? IconButton(
                icon: Icon(
                    obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    color: subtextColor,
                    size: 20),
                onPressed: onToggle)
            : null,
        filled: true,
        fillColor: fieldBg,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBlue, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
    );
  }
}
