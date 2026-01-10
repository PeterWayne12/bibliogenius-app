import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:path_provider/path_provider.dart';
import '../src/rust/frb_generated.dart';
import '../src/rust/api/frb.dart' as frb;

/// Initializes the platform-specific dependencies.
/// For native platforms, this sets up the Rust FFI connection.
Future<bool> initializePlatform() async {
  try {
    debugPrint('FFI: Starting RustLib.init()...');
    // Initialize Flutter-Rust bridge
    // On iOS/macOS, the library is statically linked, so use DynamicLibrary.process()
    // On Android/Linux/Windows, load the dynamic library from the bundle
    if (Platform.isIOS || Platform.isMacOS) {
      debugPrint('FFI: Using DynamicLibrary.process() for iOS/macOS...');
      await RustLib.init(
        externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
      );
    } else {
      await RustLib.init();
    }
    debugPrint('FFI: RustLib.init() succeeded');

    // Get database path
    debugPrint('FFI: Getting application documents directory...');
    final appDocDir = await getApplicationDocumentsDirectory();
    final dbPath = '${appDocDir.path}/bibliogenius.db';
    debugPrint('FFI: Database path: $dbPath');

    // Initialize Rust backend with database
    debugPrint('FFI: Calling initBackend...');
    final result = await frb.initBackend(dbPath: dbPath);
    debugPrint('FFI Backend initialized: $result');
    debugPrint('FFI: useFfi set to TRUE');

    return true; // useFfi = true
  } catch (e) {
    debugPrint('FFI Initialization Error: $e');
    return false;
  }
}
