// Conditionally import the correct implementation
// ignore: unused_import
import 'platform_init_native.dart'
    if (dart.library.html) 'platform_init_web.dart';

export 'platform_init_native.dart'
    if (dart.library.html) 'platform_init_web.dart';
