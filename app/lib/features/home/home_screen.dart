import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../services/supabase_service.dart';

/// Placeholder home screen for Session 0.
///
/// Its only real job right now is to prove the Session 0 plumbing works:
/// the app boots in Hebrew/RTL, and (once credentials are wired) the anon
/// client can round-trip a row to Supabase via the "connectivity test".
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _status;
  bool _busy = false;

  Future<void> _runConnectivityTest() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      if (!AppConfig.isConfigured) {
        throw StateError(
          'Supabase לא מוגדר. הריצו עם --dart-define-from-file=dart_define.json',
        );
      }
      // Insert a ping and read it back — exercises anon read + write.
      final inserted = await SupabaseService.client
          .from('pings')
          .insert({'note': 'session-0 connectivity test'})
          .select()
          .single();
      setState(() => _status = 'הצליח ✓  (id: ${inserted['id']})');
    } catch (e) {
      setState(() => _status = 'נכשל: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = AppConfig.isConfigured;
    return Scaffold(
      appBar: AppBar(title: const Text('הערכת תזונה במסעדות')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ברוכים הבאים 👋',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'הקלידו שם של מסעדה, בחרו מנות, וקבלו הערכת תזונה מבוססת בינה מלאכותית. '
              'כל הנתונים הם הערכות — לא ייעוץ רפואי.',
            ),
            const SizedBox(height: 24),
            _ConfigBanner(configured: configured),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _runConnectivityTest,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_done_outlined),
              label: const Text('בדיקת חיבור ל-Supabase'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Text(_status!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConfigBanner extends StatelessWidget {
  const _ConfigBanner({required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: configured
            ? scheme.secondaryContainer
            : scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(configured ? Icons.check_circle_outline : Icons.warning_amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              configured
                  ? 'Supabase מוגדר.'
                  : 'Supabase לא מוגדר — העתיקו dart_define.example.json ל-dart_define.json והריצו עם --dart-define-from-file.',
            ),
          ),
        ],
      ),
    );
  }
}
