/// Compile-time configuration.
///
/// Values are injected at build/run time via `--dart-define` (or
/// `--dart-define-from-file=dart_define.json`). NOTHING secret lives here:
/// the client only ever holds the Supabase **URL** and **anon key**, both of
/// which are safe to ship in a client binary. The service-role key and all AI
/// / Places / search keys live only in Supabase Edge Function secrets.
///
/// See `dart_define.example.json` for the expected keys, and the README for
/// how to run with them.
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// True only when both values were provided at build time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
