
import 'dart:ffi';

void main() {
  final dllPath = r'C:\Program Files (x86)\Microsoft\Edge\Application\155.0.4283.62\onnxruntime.dll';
  print('Attempting to load: $dllPath');
  try {
    final dylib = DynamicLibrary.open(dllPath);
    print('Successfully loaded DLL!');

    try {
        final symbol = dylib.lookup('OrtGetApiBase');
        print('Found OrtGetApiBase at ${symbol.address}');
    } catch (e) {
        print('Could not find OrtGetApiBase: $e');
    }
  } catch (e) {
    print('Failed to load DLL: $e');
  }
}
