/// Audio Module for BiblioGenius
///
/// This module provides audiobook discovery and playback functionality.
/// It is fully decoupled from the rest of the app and can be enabled/disabled
/// via user settings.
///
/// ## Architecture
///
/// ```
/// lib/audio/
/// ├── audio_module.dart      # Main export file (this file)
/// ├── models/
/// │   └── audio_resource.dart
/// ├── services/
/// │   └── audiobook_service.dart
/// ├── providers/
/// │   └── audio_provider.dart
/// └── widgets/
///     ├── audio_player_widget.dart
///     └── audio_section.dart
/// ```
///
/// ## Usage
///
/// 1. Add AudioProvider to your app's providers
/// 2. Use AudioSection widget in book details screen
/// 3. Toggle feature via AudioProvider.setEnabled()

library audio_module;

// Models
export 'models/audio_resource.dart';

// Services
export 'services/audiobook_service.dart';

// Providers
export 'providers/audio_provider.dart';

// Widgets
export 'widgets/audio_player_widget.dart';
export 'widgets/audio_section.dart';
export 'widgets/audio_settings_card.dart';

// Screens
export 'screens/audio_webview_screen.dart';
