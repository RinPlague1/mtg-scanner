/// App-wide settings. Rename the app by changing [appName] (and
/// `android:label` in android/app/src/main/AndroidManifest.xml).
class AppConfig {
  static const appName = 'MTG Binder';

  /// Supabase project settings, passed at build time:
  ///   flutter build apk --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  ///                     --dart-define=SUPABASE_ANON_KEY=eyJ...
  /// Without them the app runs fully offline (scanner, collection, decks, imports)
  /// and the Friends / Trades tabs explain how to connect.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Where web/showcase.html is hosted (optional). When set, "Share Showcase"
  /// sends a link anyone can open; otherwise it shares a text list.
  static const showcaseUrl = String.fromEnvironment('SHOWCASE_URL');

  static bool get onlineEnabled => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
