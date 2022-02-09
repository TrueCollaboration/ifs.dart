import 'dart:async';

import 'package:ifs/src/external/exceptions.dart';
import 'package:ifs/src/internal/util.dart';
import 'package:true_core/library.dart';

import 'ESectionResult.dart';
import 'SectionController.dart';

abstract class Section {
  late final SectionController controller;

  // INotifier<bool> editedState = new Notifier(value: false);

  /// Absolute offset
  late final int offset;

  /// Section size
  int get size;

  /// Next section offset (absolute)
  int get nextSectionOffset;
  set nextSectionOffset(int v);

  /// Must return [ESectionResult.ENOUGH]
  Future<ESectionResult> onCreate(BufferPointer buffer);
  
  Future<ESectionResult> onRead(BufferPointer buffer);

  
  Future<void> save() async {
    debug("Section.save()");
    final buffer = new BufferPointer.empty();

    final written = await controller.synchronized(() async {
      final result = await onCreate(buffer);
      if(result != ESectionResult.OK)
        throw(CorruptedSectionException(name: ""));
      return await controller.write(buffer.buffer, offset);
    });

    if(written != buffer.length)
      throw(InputWriteReadException(proced: written, expected: buffer.length));
  }
}