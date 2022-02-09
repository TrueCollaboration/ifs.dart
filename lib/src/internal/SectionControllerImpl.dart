import 'dart:async';
import 'dart:typed_data';

import 'package:ifs/src/external/IntrafileSystem.dart';
import 'package:ifs/src/internal/Section.dart';

import 'SectionController.dart';

class SectionControllerImpl extends SectionController {
  final IntrafileSystem intrafile;
  late final Section section;
  SectionControllerImpl({
    required this.intrafile,
  });

  @override
  int get length => intrafile.input.length;

  @override
  int get clusterSize => intrafile.clusterSize;

  bool synced = false;

  @override
  FutureOr<T> synchronized<T>(FutureOr<T> Function() computation, {Duration? timeout}) async {
    if(synced)
      return await computation();
    late final T result;
    await intrafile.input.synchronized(() async {
      synced = true;
      result = await computation();
      synced = false;
    }, timeout: timeout ?? const Duration(seconds: 10));

    return result;
  }
  
  @override
  Future<int> read(Uint8List buffer, int dstOffset, [int offset = 0, int length = 0]) async {
    _throwIfNotSynced();
    return await intrafile.input.readFrom(buffer, dstOffset, offset, length);
  }
  
  @override
  Future<int> append(Uint8List buffer, [int offset = 0, int length = 0]) async {
    _throwIfNotSynced();
    return await intrafile.input.append(buffer, offset, length);
  }
  
  @override
  Future<int> write(Uint8List buffer, int dstOffset, [int offset = 0, int length = 0]) async {
    _throwIfNotSynced();
    return await intrafile.input.writeTo(buffer, dstOffset, offset, length);
  }

  void _throwIfNotSynced() {
    if(!synced)
      throw(Exception("You should sync before do operations"));
  }
}