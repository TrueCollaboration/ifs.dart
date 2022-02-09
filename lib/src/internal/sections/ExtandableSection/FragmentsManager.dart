import 'dart:math';
import 'dart:typed_data';

import 'package:ifs/src/external/IntrafileSystem.dart';
import 'package:ifs/src/external/exceptions.dart';
import 'package:ifs/src/internal/ESectionResult.dart';
import 'package:ifs/src/internal/sections/ExtandableSection.dart';
import 'package:ifs/src/internal/util.dart';
import 'package:true_core/core/library.dart';

import 'Fragment.dart';
import 'FragmentReference.dart';
import 'FragmentsTable.dart';
import 'FragmentsTableReference.dart';

class FragmentsManager {
  final List<_FragmentsTable> _tables = [];
  late final ExtandableSection section;
  FragmentsManager();

  Iterable<FragmentsTable> get tables => _tables;

  FragmentsTableReference? get nextTableOffset {
    final table = _tables.tryLast;
    if(table == null)
      throw(NeedMoreTablesException(1));
    if(table.nextOffset == -1)
      return null;
    return FragmentsTableReference(
      offset: table.nextOffset,
      size: table.nextSize,
    );
  }

  _FragmentReference? get nextFragmentOffset {
    final table = _tables.tryLast;
    if(table == null)
      throw(NeedMoreFragmentsException(1));
    final ref = table.references.tryFirstWhere((e) => e.fragment == null);
    return (ref == null || ref.offset == -1) ? null : ref;
  }

  Future<FragmentsTable> createTable(
    BufferPointer buffer, {
      required int offset,
  }) async {
    final table = new _FragmentsTable();
    table.offset = offset;
    table.size = IntrafileSystem.roundSize(Global.DEFAULT_TABLE_SIZE, section.controller.clusterSize);

    final result = await table.onCreate(buffer);
    if(result == ESectionResult.OK) {
      _tables.add(table);
    } else if(result == ESectionResult.CORRUPTED) {
      throw(CorruptedSectionException(name: section.name, msg: "Cant create fragments table"));
    } return table;
  }

  Future<FragmentsTable> readTable(
    BufferPointer buffer, {
      required int offset,
  }) async {
    final table = new _FragmentsTable();
    table.offset = offset;
    table.size = buffer.length;

    final result = await table.onRead(buffer);
    if(result == ESectionResult.OK) {
      _tables.add(table);
    } else if(result == ESectionResult.CORRUPTED) {
      throw(CorruptedSectionException(name: section.name, msg: "Fragments table absolute offset #$offset"));
    } return table;
  }






  Future<Fragment> createFragment(
    BufferPointer buffer, {
      required int offset,
      int? payloadSize,
      int? totalSize,
  }) async {
    if(!(_tables.tryLast?.hasSpace() ?? false))
      throw(NeedMoreTablesException(1));
    
    final fragment = new _Fragment();
    fragment.offset = offset;

    final result = await fragment.onCreate(buffer);
    if(result == ESectionResult.OK) {
      _tables.last.addFragment(
        fragment,
        payloadSize: payloadSize ?? 0,
        totalSize: IntrafileSystem.roundSize(max(payloadSize ?? 0, totalSize ?? 0), section.controller.clusterSize),
      );
    } else if(result == ESectionResult.CORRUPTED) {
      throw(CorruptedSectionException(name: section.name, msg: "Cant create fragment"));
    } return fragment;
  }

  Future<Fragment> readFragment(BufferPointer buffer, {
    required FragmentReference reference,
  }) async {
    final fragment = new _Fragment();
    fragment.offset = reference.offset;

    final result = await fragment.onRead(buffer);
    if(result == ESectionResult.OK) {
      bool inited = false;
      for(final table in _tables) {
        if(!table.initFragment(fragment))
          continue;
        inited = true;
        break;
      } if(!inited)
        throw(Exception("Unknown fragment has been read"));
    } else if(result == ESectionResult.CORRUPTED) {
      throw(CorruptedSectionException(name: section.name, msg: "Fragment absolute offset #${reference.offset}"));
    } return fragment;
  }

  Future<Fragment> getFragment(int offset) async {
    for(final table in _tables) {
      final ref = table.references.tryFirstWhere((e) => e.offset == offset);
      if(ref == null)
          continue;
      return ref.fragment!;
    } throw(Exception("#$offset"));
  }

  Future<void> updateNextOffset(int offset) async {
    final table = _tables.last;
    // Prevent eternal loop. Table should not refer to itself
    if(table.offset == offset)
      return;
    table.nextOffset = offset;
    await _save();
  }

  List<KeyValue<Range, FragmentReference>> getReadableRanges(int offset, int length) {
    final List<KeyValue<Range, FragmentReference>> map = [];

    final int preferStart = offset;
    final int preferEnd = offset + length;

    if(preferStart >= section.payloadSize)
      return map;

    int total = 0;
    {
      int start = preferStart;
      int end = preferEnd;
      for(final ref in _getFragmentReferences()) {
        final range = ref.getPayloadRange(start, end);
        start -= ref.payloadSize;
        end -= ref.payloadSize;
        if(range == null || range.length == 0)
          continue;
        total += range.length;
        map.add(KeyValue(range, ref));
      }
    }

    
    if(total < length) {
      // TODO не уверен, что все правильно
      // final start = 
      // int size = _getPayloadSizeOfLoadedFragments();
      // int sectionStart = size;
      int sectionEnd = section.payloadSize;
      int available = min(sectionEnd, preferEnd) - min(sectionEnd, preferStart);
      // print(size);
      int needle = available - total;
      if(needle > 0)
        throw(NeedMoreFragmentsException(needle));
    }

    return map;
  }

  // int _getPayloadSizeOfLoadedFragments() {
  //   int total = 0;
  //   for(final fragment in _getFragmentReferences()) {
  //     total += fragment.payloadSize;
  //   } return total;
  // }

  List<KeyValue<Range, FragmentReference>> getAppendableRanges(int length) {
    final List<KeyValue<Range, FragmentReference>> map = [];

    // if(mode == EAppendMode.end) {
      final List<_FragmentReference> tmp = [];
      for(final ref in _getFragmentReferences().reversed) {
        if(ref.freeSize == 0)
          continue;
        tmp.add(ref);
        if(ref.freeSize != ref.totalSize)
          break;
      }

      for(final ref in tmp.reversed) {
        final range = ref.getAppendableRange(length);
        length -= ref.freeSize;
        if(range.length == 0)
          continue;
        map.add(KeyValue(range, ref));
      } return map;
    // } else {
    //   final fragment = fragments.tryLast;
    //   if(fragment != null)
    //     map.add(KeyValue(fragment.getAppendableRange(length), fragment));
    // }
    // return map;
  }

  List<KeyValue<Range, FragmentReference>> getWriteableRanges(int offset, int length) {
    final List<KeyValue<Range, FragmentReference>> map = [];

    final int preferStart = offset;
    final int preferEnd = offset + length;

    // int start = preferStart;
    // int end = preferEnd;
    for(final ref in _getFragmentReferences()) {
      final range = ref.getPayloadRange(preferStart, preferEnd);
      // start -= ref.payloadSize;
      // end -= ref.payloadSize;
      if(range == null || range.length == 0)
        continue;
      map.add(KeyValue(range, ref));
    } return map;
  }

  List<_FragmentReference> _getFragmentReferences() {
    final List<_FragmentReference> list = [];
    for(final table in _tables) {
      for(final ref in table.references) {
        if(list.tryFirstWhere((e) => e.offset == ref.offset) != null)
          continue;
        list.add(ref);
      }
    } return list;
  }

  Future<void> save(bool synced) async {
    if(synced)
      return await _save();
    return await section.controller.synchronized(() async {
      return await _save();
    });
  }

  Future<void> _save() async {
    for(final table in _tables.where((e) => e.modified)) {
      final buffer = new BufferPointer.empty();
      
      final result = await table.onCreate(buffer);
      if(result == ESectionResult.CORRUPTED)
        throw(CorruptedSectionException(name: section.name, msg: "Cant create table"));

      final written = await section.controller.write(buffer.buffer, table.offset);
      if(written != buffer.length)
        throw(InputWriteReadException(proced: written, expected: buffer.length));
    }

    // for(final fragment in _getFragmentReferences().where((e) => e.fragment?.modified ?? false).map((e) => e.fragment!)) {
    //   final buffer = new BufferPointer.empty();
      
    //   final result = await fragment.onCreate(buffer);
    //   if(result == ESectionResult.CORRUPTED)
    //     throw(CorruptedSectionException(name: section.name, msg: "Cant create fragment"));

    //   final written = await section.controller.write(buffer.buffer, fragment.offset);
    //   if(written != buffer.length)
    //     throw(InputWriteReadException(proced: written, expected: buffer.length));
    // }
  }
}





class _FragmentsTable extends FragmentsTable {
  static const int HEAD_SIZE = 8 + 4 + 8 + 4 + 8 + 4;
  _FragmentsTable();

  bool modified = false;



  @override
  late int checksum;

  @override
  int get count => references.length;
  
  @override
  int prevOffset = -1;
  
  @override
  int prevSize = 0;
  
  @override
  int nextOffset = -1;
  
  @override
  int nextSize = 0;

  @override
  final List<_FragmentReference> references = [];

  @override
  Future<ESectionResult> onCreate(BufferPointer buffer) async {
    final int checksum;
    final int count;
    final int prevOffset;
    final int prevSize;
    final int nextOffset;
    final int nextSize;
    
    count = this.count;
    prevOffset = this.prevOffset;
    prevSize = this.prevSize;
    nextOffset = this.nextOffset;
    nextSize = this.nextSize;
    
    {
      final BufferPointer temp = BufferPointer.empty();
      temp.pushUInt32(count);
      temp.pushUInt64(prevOffset);
      temp.pushUInt32(prevSize);
      temp.pushUInt64(nextOffset);
      temp.pushUInt32(nextSize);
      checksum = IntrafileSystem.fastChecksum(temp.buffer);
    }

    buffer.pushUInt64(checksum);
    buffer.pushUInt32(count);
    buffer.pushUInt64(prevOffset);
    buffer.pushUInt32(prevSize);
    buffer.pushUInt64(nextOffset);
    buffer.pushUInt32(nextSize);

    for(int i = 0; i < count; i++) {
      final ref = references[i];
      buffer.pushUInt64(ref.offset);
      buffer.pushUInt64(ref.payloadSize);
      buffer.pushUInt64(ref.totalSize);
    }

    this.checksum = checksum;
    
    return ESectionResult.OK;
  }

  @override
  Future<ESectionResult> onRead(BufferPointer buffer) async {
    final int checksum;
    final int count;
    final int prevOffset;
    final int prevSize;
    final int nextOffset;
    final int nextSize;

    checksum = buffer.getUint64()!;

    {
      const length = 4 + 8 + 4 + 8 + 4;
      if(checksum != IntrafileSystem.fastChecksum(buffer.getBytes(length)!)) {
        return ESectionResult.CORRUPTED;
      } buffer.flip(length);
    }

    count = buffer.getUint32()!;

    prevOffset = buffer.getUint64()!;

    prevSize = buffer.getUint32()!;

    nextOffset = buffer.getUint64()!;

    nextSize = buffer.getUint32()!;

    for(int i = 0; i < count; i++) {
      references.add(_FragmentReference(
        table: this,
        offset: buffer.getUint64()!,
        payloadSize: buffer.getUint64()!,
        totalSize: buffer.getUint64()!,
      ));
    }

    this.checksum = checksum;
    this.prevOffset = prevOffset;
    this.prevSize = prevSize;
    this.nextOffset = nextOffset;
    this.nextSize = nextSize;

    return ESectionResult.OK;
  }

  void addFragment(
    _Fragment fragment, {
      required int payloadSize,
      required int totalSize,
  }) {
    final ref = _FragmentReference(
      table: this,
      offset: fragment.offset,
      payloadSize: payloadSize,
      totalSize: totalSize,
    );
    ref.fragment = fragment;
    references.add(ref);

    fragment.ref = ref;
    modified = true;
  }

  bool initFragment(_Fragment fragment) {
    final ref = references.tryFirstWhere((e) => e.offset == fragment.offset);
    if(ref == null)
      return false;
    ref.fragment = fragment;
    fragment.ref = ref;
    return true;
  }

  bool hasSpace() {
    if(size - HEAD_SIZE - (count * FragmentReference.HEAD_SIZE) > FragmentReference.HEAD_SIZE)
      return true;
    return false;
  }
}



class _FragmentReference extends FragmentReference {
  final _FragmentsTable table;

  @override
  int offset;

  @override
  int payloadSize;

  @override
  int totalSize;

  _Fragment? fragment;

  _FragmentReference({
    required this.table,
    required this.offset,
    required this.payloadSize,
    required this.totalSize,
  });

  int get payloadOffset => offset + _Fragment.HEAD_SIZE;
  
  @override
  int get freeSize => totalSize - payloadSize;
  
  @override
  void setPayloadSize(int value) {
    payloadSize = value;
    table.modified = true;
  }

  @override
  Range getAppendableRange(int length) {
    final appendStart = payloadSize;
    final sectionEnd = totalSize;
    final preferEnd = appendStart + length;
    return Range(appendStart + payloadOffset, min(sectionEnd, preferEnd) + payloadOffset);
  }

  @override
  Range? getPayloadRange(int start, int end) {
    const sectionStart = 0;
    final sectionEnd = payloadSize;
    if(start > sectionEnd)
      return null;
    else if(end < sectionStart)
      return null;
    // Making range (relative) and converting to absolute ( + payloadOffset)
    return Range(max(sectionStart, start) + payloadOffset, min(sectionEnd, end) + payloadOffset);
  }

  @override
  Range? getSectionRange(int start, int end) {
    const sectionStart = 0;
    final sectionEnd = totalSize;
    if(start > sectionEnd)
      return null;
    else if(end < sectionStart)
      return null;
    return Range(max(sectionStart, start) + payloadOffset, min(sectionEnd, end) + payloadOffset);
  }
}







class _Fragment extends Fragment {
  static const int HEAD_SIZE = 128;

  @override
  int get size => HEAD_SIZE;

  late final _FragmentReference ref;

  _Fragment();

  @override
  int get payloadSize => ref.payloadSize;
  
  @override
  int get totalSize => ref.totalSize;


  @override
  late Uint8List RESERVED;

  @override
  Future<ESectionResult> onCreate(BufferPointer buffer) async {
    final Uint8List RESERVED;

    RESERVED = IntrafileSystem.createBuffer(128);

    buffer.pushBytes(RESERVED);

    this.RESERVED = RESERVED;

    return ESectionResult.OK;
  }

  @override
  Future<ESectionResult> onRead(BufferPointer buffer) async {
    final Uint8List RESERVED;

    RESERVED = buffer.getBytes(128)!;

    this.RESERVED = RESERVED;

    return ESectionResult.OK;
  }


  // bool modified = false;
}