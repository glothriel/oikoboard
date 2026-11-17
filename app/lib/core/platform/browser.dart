/// Operacje na pasku adresu przeglądarki (no-op poza webem).
library;

export 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart';
