/// App-wide settings. Rename the app by changing [appName] (and
/// `android:label` in android/app/src/main/AndroidManifest.xml).
class AppConfig {
  static const appName = 'MTG Binder';

  /// Supabase project settings, passed at build time:
  ///   flutter build apk --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  ///                     --dart-define=SUPABASE_ANON_KEY=eyJ...
  /// Without them the app runs fully offline (scanner, collection, decks, imports)
  /// and the Friends / Trades tabs explain how to connect.
  static const _rawUrl = String.fromEnvironment('SUPABASE_URL');
  static const _rawKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Tidied up: GitHub secrets pasted with spaces, quotes, a trailing slash
  /// or without "https://" still work.
  static String get supabaseUrl {
    var u = _clean(_rawUrl);
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (u.endsWith('/rest/v1')) u = u.substring(0, u.length - 8);
    if (u.isNotEmpty && !u.startsWith('http')) u = 'https://$u';
    return u;
  }

  static String get supabaseAnonKey => _clean(_rawKey);

  static String _clean(String s) => s.trim().replaceAll('"', '').replaceAll("'", '').trim();

  /// Where web/showcase.html is hosted (optional). When set, "Share Showcase"
  /// sends a link anyone can open; otherwise it shares a text list.
  static const showcaseUrl = String.fromEnvironment('SHOWCASE_URL');

  static bool get onlineEnabled => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
