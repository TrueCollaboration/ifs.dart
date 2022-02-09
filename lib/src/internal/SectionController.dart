import 'dart:async';
import 'dart:typed_data';

abstract class SectionController {
  int get length;
  int get clusterSize;

  FutureOr<T> synchronized<T>(FutureOr<T> Function() computation, {Duration? timeout});
  Future<int> read(Uint8List buffer, int dstOffset, [int offset = 0, int length = 0]);
  Future<int> append(Uint8List buffer, [int offset = 0, int length = 0]);
  Future<int> write(Uint8List buffer, int dstOffset, [int offset = 0, int length = 0]);
}