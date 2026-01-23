/// This is copied from Cargokit (which is the official way to use it currently)
/// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:toml/toml.dart';

class ManifestException {
  ManifestException(this.message, {required this.fileName});

  final String? fileName;
  final String message;

  @override
  String toString() {
    if (fileName != null) {
      return 'Failed to parse package manifest at $fileName: $message';
    } else {
      return 'Failed to parse package manifest: $message';
    }
  }
}

class CrateInfo {
  CrateInfo({required this.packageName, this.libName});

  final String packageName;
  final String? libName;

  /// Returns the library name to use for artifact naming.
  /// Uses [lib].name if specified, otherwise falls back to package name.
  String get effectiveLibName => libName ?? packageName;

  static CrateInfo parseManifest(String manifest, {final String? fileName}) {
    final toml = TomlDocument.parse(manifest);
    final package = toml.toMap()['package'];
    if (package == null) {
      throw ManifestException('Missing package section', fileName: fileName);
    }
    final name = package['name'];
    if (name == null) {
      throw ManifestException('Missing package name', fileName: fileName);
    }
    // Check for custom library name in [lib] section
    final lib = toml.toMap()['lib'];
    final libName = lib != null ? lib['name'] as String? : null;
    return CrateInfo(packageName: name, libName: libName);
  }

  static CrateInfo load(String manifestDir) {
    final manifestFile = File(path.join(manifestDir, 'Cargo.toml'));
    final manifest = manifestFile.readAsStringSync();
    return parseManifest(manifest, fileName: manifestFile.path);
  }
}
