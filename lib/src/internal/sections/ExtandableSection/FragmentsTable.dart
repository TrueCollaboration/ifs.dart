import 'package:ifs/src/internal/ESectionResult.dart';
import 'package:true_core/core/library.dart';

import 'FragmentReference.dart';

abstract class FragmentsTable {
  late final int offset;

  late final int size;

  Future<ESectionResult> onCreate(BufferPointer buffer);
  Future<ESectionResult> onRead(BufferPointer buffer);
  

  int get checksum;
  
  int get count;
  
  int get prevOffset;

  int get prevSize;
  
  int get nextOffset;
  
  int get nextSize;

  Iterable<FragmentReference> get references;
}