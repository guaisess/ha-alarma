import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../models.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await HistoryService.load();
    if (mounted) setState(() { _entries = entries; _loading = false; });
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Borrar historial', style: TextStyle(color: kText)),
        content: const Text('¿Eliminar todos los registros?',
            style: TextStyle(color: kSubtext)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: kSubtext))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar', style: TextStyle(color: kRed))),
        ],
      ),
    );
    if (confirm == true) {
      await HistoryService.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final bgColor      = isDark ? kBg      : const Color(0xFFf1f5f9);
    final textColor    = isDark ? kText    : const Color(0xFF0f172a);
    final subtextColor = isDark ? kSubtext : const Color(0xFF64748b);
    final surfaceColor = isDark ? kSurface : Colors.white;
    final fmt          = DateFormat('dd/MM/yyyy  HH:mm:ss');

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: subtextColor, size: 20),
            onPressed: () => Navigator.pop(context)),
        title: Text('Historial',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: subtextColor),
                onPressed: _clear),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: kBlue, strokeWidth: 2))
          : _entries.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.history_rounded, color: subtextColor, size: 64),
                    const SizedBox(height: 16),
                    Text('Sin registros aún',
                        style: TextStyle(color: subtextColor, fontSize: 16)),
                  ]),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final e     = _entries[i];
                    final info  = stateInfo[e.state]!;
                    final color = info['color'] as Color;
                    final icon  = info['icon'] as IconData;
                    final label = info['label'] as String;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: color.withOpacity(0.25), width: 1),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              shape: BoxShape.circle),
                          child: Icon(icon, color: color, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(fmt.format(e.timestamp),
                                style: TextStyle(
                                    color: subtextColor, fontSize: 12)),
                          ],
                        )),
                      ]),
                    );
                  },
                ),
    );
  }
}
