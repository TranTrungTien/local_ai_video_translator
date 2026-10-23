
import 'dart:typed_data';

class Blob {
  Blob(List<dynamic> blobParts, [dynamic options]);
}

class BlobPropertyBag {
  BlobPropertyBag({String? type});
}

class URL {
  static String createObjectURL(dynamic object) => '';
  static void revokeObjectURL(String url) {}
}

class Response {
  Response(dynamic body, [dynamic init]);
  Future<dynamic> arrayBuffer() async => null;
}

class ResponseInit {
  ResponseInit({dynamic headers});
}

class Window {
  CacheStorage get caches => CacheStorage();
}

class CacheStorage {
  Future<Cache> open(String cacheName) async => Cache();
  Future<dynamic> match(dynamic request) async => null;
  Future<bool> delete(dynamic request) async => true;
}

class Cache {
  Future<void> put(dynamic request, dynamic response) async {}
  Future<dynamic> match(dynamic request) async => null;
}

typedef HeadersInit = dynamic;

final Window window = Window();

extension JSArrayBufferViewExtension on TypedData {
  dynamic get toJS => null;
}

extension JSObjectArrayExtension on List<dynamic> {
  dynamic get toJS => null;
}

extension Uint8ListToJS on Uint8List {
  dynamic get toJS => null;
}

extension StringToJS on String {
  dynamic get toJS => null;
}

extension JSArrayBufferToDart on dynamic {
  dynamic get toDart => this;
  Uint8List asUint8List() => Uint8List(0);
}

extension ObjectToJS on Object? {
  dynamic jsify() => null;
}
