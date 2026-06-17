import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Thin wrapper around the Supabase client.
///
/// The client is created with the public anon key only. All privileged work
/// (AI calls, Places lookups, menu fetching) happens server-side in Edge
/// Functions that hold the secret keys — never here.
class SupabaseService {
  const SupabaseService._();

  /// Initialize Supabase once, at app startup. No-op if not configured, so the
  /// app still boots (and shows a "not configured" state) before credentials
  /// are wired in.
  static Future<void> init() async {
    if (!AppConfig.isConfigured) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // Works for both the legacy "anon" key and the newer "publishable" key —
      // both are public and safe to ship in the client.
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
