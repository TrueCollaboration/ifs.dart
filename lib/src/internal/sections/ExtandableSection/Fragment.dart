import 'dart:typed_data';

import 'package:ifs/src/internal/ESectionResult.dart';
import 'package:true_core/core/library.dart';

abstract class Fragment {
  late final int offset;

  int get size;

  int get payloadSize;

  int get totalSize;

  Future<ESectionResult> onCreate(BufferPointer buffer);
  Future<ESectionResult> onRead(BufferPointer buffer);
  

  Uint8List get RESERVED;
}