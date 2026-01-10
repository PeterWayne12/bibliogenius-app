import 'package:flutter/foundation.dart';

/// Initializes the platform-specific dependencies.
/// For web, this is currently a no-op as FFI/Rust is not supported.
Future<bool> initializePlatform() async {
  debugPrint('Web: Skipping native FFI initialization.');
  return false; // useFfi = false
}
