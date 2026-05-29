import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version  = '...';
  String _fcmToken = 'Cargando...';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then(
        (i) => setState(() => _version = '${i.version} (build ${i.buildNumber})'));
    SharedPreferences.getInstance().then((prefs) {
      final token = prefs.getString('fcm_token');
      setState(() => _fcmToken = token ??
          'No disponible — abre la app una vez con Firebase configurado');
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final bgColor      = isDark ? kBg      : const Color(0xFFf1f5f9);
    final textColor    = isDark ? kText    : const Color(0xFF0f172a);
    final subtextColor = isDark ? kSubtext : const Color(0xFF64748b);
    final surfaceColor = isDark ? kSurface : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: subtextColor, size: 20),
            onPressed: () => Navigator.pop(context)),
        title: Text('Acerca de',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
            width: 110, height: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(
                  color: kBlue.withOpacity(0.2), blurRadius: 24, spreadRadius: 2)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Image.asset('assets/icon.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 20),
          Text('Alarma Casa HA',
              style: TextStyle(
                  color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Versión $_version',
              style: TextStyle(color: subtextColor, fontSize: 14)),
          const SizedBox(height: 32),

          _AboutCard(surfaceColor: surfaceColor, items: [
            _AboutItem(icon: Icons.person_rounded,         label: 'Desarrollador', value: 'Alfredo Fernández Badía'),
            _AboutItem(icon: Icons.home_work_rounded,      label: 'Proyecto',      value: 'Control de alarma para Home Assistant'),
            _AboutItem(icon: Icons.location_city_rounded,  label: 'Ubicación',     value: 'Bargas, Toledo'),
            _AboutItem(icon: Icons.calendar_today_rounded, label: 'Año',           value: '2025'),
          ]),
          const SizedBox(height: 16),
          _AboutCard(surfaceColor: surfaceColor, items: [
            _AboutItem(icon: Icons.code_rounded,         label: 'Tecnología', value: 'Flutter'),
            _AboutItem(icon: Icons.hub_rounded,          label: 'Plataforma', value: 'Home Assistant + Alarmo'),
            _AboutItem(icon: Icons.build_circle_rounded, label: 'CI/CD',      value: 'GitHub Actions'),
          ]),
          const SizedBox(height: 16),

          // Token FCM
          Container(
            decoration: BoxDecoration(
                color: surfaceColor, borderRadius: BorderRadius.circular(18)),
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.notifications_rounded, color: kBlue, size: 20),
                const SizedBox(width: 10),
                Text('Token FCM',
                    style: TextStyle(color: subtextColor, fontSize: 11)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.copy_rounded, color: subtextColor, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Copiar token',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _fcmToken));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Token copiado'),
                        duration: Duration(seconds: 2)));
                  },
                ),
              ]),
              const SizedBox(height: 8),
              Text(_fcmToken,
                  style: TextStyle(
                      color: textColor, fontSize: 11, fontFamily: 'monospace'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text('Úsalo en Home Assistant para enviar notificaciones push',
                  style: TextStyle(color: subtextColor, fontSize: 10)),
            ]),
          ),
          const SizedBox(height: 32),
          Text('Uso personal — Todos los derechos reservados',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtextColor, fontSize: 11)),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  final List<_AboutItem> items;
  final Color            surfaceColor;
  const _AboutCard({required this.items, required this.surfaceColor});

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final textColor    = isDark ? kText    : const Color(0xFF0f172a);
    final subtextColor = isDark ? kSubtext : const Color(0xFF64748b);
    final divColor     = isDark ? kBg      : const Color(0xFFe2e8f0);

    return Container(
      decoration: BoxDecoration(
          color: surfaceColor, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: items.asMap().entries.map((e) {
          final isLast = e.key == items.length - 1;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(children: [
                Icon(e.value.icon, color: kBlue, size: 20),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.value.label,
                        style: TextStyle(color: subtextColor, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(e.value.value,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ],
                )),
              ]),
            ),
            if (!isLast) Divider(height: 1, color: divColor, indent: 52),
          ]);
        }).toList(),
      ),
    );
  }
}

class _AboutItem {
  final IconData icon;
  final String   label, value;
  const _AboutItem(
      {required this.icon, required this.label, required this.value});
}
