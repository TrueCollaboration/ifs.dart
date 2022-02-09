import 'package:ifs/src/internal/ESectionResult.dart';
import 'package:true_core/library.dart';

abstract class SectionState {
  String get name;

  Future<ESectionResult> onCreate(BufferPointer bufferPointer);
  Future<ESectionResult> onRead(BufferPointer bufferPointer);

  void setState() {
    
  }
}