// Versión 2026.11.12
import 'package:flutter/material.dart';
import 'constants.dart';
import 'models.dart';

// ─── Tarjeta informativa de zonas de Alarmo ───────────────────
// Solo lectura: el único control es "Armar" en una zona que el robot
// desarmó y no se rearmó automáticamente.
class ZonesSection extends StatelessWidget {
  final List<ZoneData> zones;
  final bool busy;
  final Map<String, String> names; // nombres legibles de sensores
  final String? highlight;         // zona resaltada al abrir desde una notificación
  final void Function(ZoneData zone) onArm;

  const ZonesSection({
    super.key, required this.zones, required this.busy, required this.onArm,
    this.names = const {}, this.highlight,
  });

  String _name(String id) {
    final n = names[id];
    if (n != null && n.isNotEmpty) return n;
    return id.split('.').last.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final text    = isDark ? kText : const Color(0xFF0f172a);
    final subtext = isDark ? kSubtext : const Color(0xFF64748b);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? kSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: [
        for (final z in zones) _row(z, text, subtext),
      ]),
    );
  }

  Widget _row(ZoneData z, Color text, Color subtext) {
    final info  = stateInfo[z.state]!;
    final color = info['color'] as Color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: highlight == z.def.label ? kBlue.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: highlight == z.def.label ? kBlue : Colors.transparent, width: 1.5),
      ),
      child: Row(children: [
        Icon(z.def.icon, color: subtext, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(z.def.label, style: TextStyle(color: text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(info['label'] as String, style: TextStyle(color: color, fontSize: 12)),
          if (z.autoDisarmed)
            Text('🤖 Desarmada por robot',
                style: TextStyle(color: subtext, fontSize: 11)),
          if (z.openSensors.isNotEmpty)
            Text('⚠️ Abiertos: ${z.openSensors.map(_name).join(', ')}',
                style: const TextStyle(color: kRed, fontSize: 11)),
          if (z.bypassedSensors.isNotEmpty)
            Text('Anulados: ${z.bypassedSensors.map(_name).join(', ')}',
                style: TextStyle(color: subtext, fontSize: 11)),
        ])),
        if (z.canArm)
          OutlinedButton(
            onPressed: busy ? null : () => onArm(z),
            style: OutlinedButton.styleFrom(
                foregroundColor: kRed, side: const BorderSide(color: kRed)),
            child: const Text('Armar'),
          )
        else
          Icon(info['icon'] as IconData, color: color, size: 22),
      ]),
    );
  }
}
