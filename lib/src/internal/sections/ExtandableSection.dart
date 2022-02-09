import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:ifs/src/external/IFragment.dart';
import 'package:ifs/src/external/ISection.dart';
import 'package:ifs/src/external/IntrafileSystem.dart';
import 'package:ifs/src/external/exceptions.dart';
import 'package:ifs/src/internal/ESectionResult.dart';
import 'package:ifs/src/internal/Section.dart';
import 'package:ifs/src/internal/util.dart';
import 'package:true_core/core/library.dart';

import 'ExtandableSection/Fragment.dart';
import 'ExtandableSection/FragmentReference.dart';
import 'ExtandableSection/FragmentsManager.dart';
import 'ExtandableSection/FragmentsTable.dart';
import 'ExtandableSection/FragmentsTableReference.dart';

// SECTION STRUCTURE
//------------------------------------------------------------------------------
// [8] checksum
// [8] next section (absolute offset)
// [8] payload size
// [8] total size
// [8] first table (absolute offset)
// [4] first table size
// [8] last table (absolute offset)
// [4] last table size
// [4] name length
// [N] name
//------------------------------------------------------------------------------

// FRAGMENTS TABLE
//------------------------------------------------------------------------------
// [8] checksum
// [4] entries count
// [8] prev table (absolute offset)
// [8] prev table size
// [8] next table (absolute offset)
// [8] next table size
// [N] FRAGMENTS [
//    [8] offset (absolute offset)
//    [8] payload size
//    [8] available size
// ]
//------------------------------------------------------------------------------

// FRAGMENT STRUCTURE
//------------------------------------------------------------------------------
// [128] RESERVED (checksum planned)
// [N] payload
//------------------------------------------------------------------------------

class ExtandableSection extends Section implements ISection {
  final FragmentsManager fragmentsManager = new FragmentsManager();
  ExtandableSection() {
    fragmentsManager.section = this;
  }

  @override
  int get size => 8 + 8 + 8 + 8 + 8 + 4 + 8 + 4 + 4 + nameLength;

  
  @override
  int nextSectionOffset = -1;

  int payloadSize = 0;
  
  int totalSize = 0;

  int firstTableOffset = -1;

  int firstTableSize = 0;

  int lastTableOffset = -1;

  int lastTableSize = 0;

  int nameLength = 0;

  String name = "";

  @override
  Future<ESectionResult> onCreate(BufferPointer buffer) async {
    final int checksum;
    final int nextSectionOffset;
    final int payloadSize;
    final int totalSize;
    final int firstTableOffset;
    final int firstTableSize;
    final int lastTableOffset;
    final int lastTableSize;
    final int nameLength;
    final Uint8List name;
    
    name = Uint8List.fromList(this.name.codeUnits);
    nextSectionOffset = this.nextSectionOffset;
    payloadSize = this.payloadSize;
    totalSize = this.totalSize;
    firstTableOffset = this.firstTableOffset;
    firstTableSize = this.firstTableSize;
    lastTableOffset = this.lastTableOffset;
    lastTableSize = this.lastTableSize;
    nameLength = this.nameLength = name.length;
    
    {
      final BufferPointer temp = BufferPointer.empty();
      temp.pushUInt64(nextSectionOffset);
      temp.pushUInt64(payloadSize);
      temp.pushUInt64(totalSize);
      temp.pushUInt64(firstTableOffset);
      temp.pushUInt32(firstTableSize);
      temp.pushUInt64(lastTableOffset);
      temp.pushUInt32(lastTableSize);
      temp.pushUInt32(nameLength);
      checksum = IntrafileSystem.fastChecksum(temp.buffer);
    }

    buffer.pushUInt64(checksum);
    buffer.pushUInt64(nextSectionOffset);
    buffer.pushUInt64(payloadSize);
    buffer.pushUInt64(totalSize);
    buffer.pushUInt64(firstTableOffset);
    buffer.pushUInt32(firstTableSize);
    buffer.pushUInt64(lastTableOffset);
    buffer.pushUInt32(lastTableSize);
    buffer.pushUInt32(nameLength);
    buffer.pushBytes(name);
        
    return ESectionResult.OK;
  }

  @override
  Future<ESectionResult> onRead(BufferPointer buffer) async {
    final int checksum;
    final int nextSectionOffset;
    final int payloadSize;
    final int totalSize;
    final int firstTableOffset;
    final int firstTableSize;
    final int lastTableOffset;
    final int lastTableSize;
    final int nameLength;
    final Uint8List name;

    checksum = buffer.getUint64()!;

    {
      const length = 8 + 8 + 8 + 8 + 4 + 8 + 4 + 4;
      if(checksum != IntrafileSystem.fastChecksum(buffer.getBytes(length)!)) {
        return ESectionResult.CORRUPTED;
      } buffer.flip(length);
    }

    nextSectionOffset = buffer.getUint64()!;

    payloadSize = buffer.getUint64()!;

    totalSize = buffer.getUint64()!;

    firstTableOffset = buffer.getUint64()!;

    firstTableSize = buffer.getUint32()!;

    lastTableOffset = buffer.getUint64()!;

    lastTableSize = buffer.getUint32()!;

    nameLength = buffer.getUint32()!;

    name = buffer.getBytes(nameLength)!;
    
    this.name = String.fromCharCodes(name);
    this.nextSectionOffset = nextSectionOffset;
    this.payloadSize = payloadSize;
    this.totalSize = totalSize;
    this.firstTableOffset = firstTableOffset;
    this.firstTableSize = firstTableSize;
    this.lastTableOffset = lastTableOffset;
    this.lastTableSize = lastTableSize;
    this.nameLength = nameLength;

    if(firstTableOffset != -1) {
      while((await _loadNextTableIfNotLoaded()) != null) {}
    }

    return ESectionResult.OK;
  }



  @override
  Iterable<IFragment> get fragments {
    final List<IFragment> list = [];
    for(final table in fragmentsManager.tables) {
      list.addAll(table.references.map((e) => new _FragmentImpl(e)));
    } return list;
  }

  @override
  int get length => payloadSize;


  int position = 0;
  
  @override
  int getPosition() => position;

  @override
  void setPosition(int offset) {
    position = offset;
  }
  
  @override
  Future<void> resize(int newSize) async {
    if(newSize == payloadSize)
      return;
    
    await controller.synchronized(() async {
      if(newSize > payloadSize) {
        bool flag = false;
        while(true) {
          final ranges = fragmentsManager.getWriteableRanges(0, newSize);

          int fragmentsLength = 0;
          for(final e in ranges.map((e) => e.key.length))
            fragmentsLength += e;
          
          int needle = newSize - fragmentsLength;
          if(needle == 0)
            break;

          final fragment = ranges.tryLast?.value;
          if(fragment != null) {
            int written = min(fragment.freeSize, needle);
            fragment.setPayloadSize(fragment.payloadSize + written);
            payloadSize += written;
            needle -= written;
            await fragmentsManager.save(true);
          }
          
          if(needle == 0)
            break;
            
          await _immediatelyAllocateFragment(needle, needle);

          if(flag) {
            throw(Exception("Internal error; needle < length; $needle < $newSize"));
          }

          flag = true;
        }
      } else if(newSize < payloadSize) {
        final ranges = fragmentsManager.getWriteableRanges(newSize, payloadSize).reversed;
        int needle = payloadSize - newSize;
        for(final entry in ranges) {
          final fragment = entry.value;
          final deleted = min(fragment.payloadSize, needle);
          fragment.setPayloadSize(fragment.payloadSize - deleted);
          needle -= deleted;
          payloadSize -= deleted;

          if(payloadSize == newSize)
            break;
        } await fragmentsManager.save(true);
        await save();
      }
    });
  }

  @override
  Future<int> read(Uint8List buffer, [int offset = 0, int length = 0]) async {
    if(length == 0)
      length = buffer.length - offset;

    int total = 0;
    await controller.synchronized(() async {
      List<KeyValue<Range, FragmentReference>> ranges;

      bool flag = false;
      while(true) {
        try {
          ranges = fragmentsManager.getReadableRanges(position, length);
        } on NeedMoreFragmentsException catch(e) {
          int needle = e.needle;
          if(flag)
            throw(Exception("position = $position; length = $length; needle = $needle"));
          await _finishLoadData(position + (length - needle), needle);
          flag = true;
          continue;
        } break;
      }

      for(final entry in ranges) {
        final range = entry.key;

        final read = await controller.read(buffer, range.start, offset, range.length);
        debug("Section.read; start = ${range.start}; end = ${range.end}; length = ${range.length}");
        if(read != range.length)
          throw(InputWriteReadException(proced: read, expected: range.length));

        total += read;
        offset += read;

        if(total == length)
          break;
      } position += total;
    });
    return total;
  }

  @override
  Future<int> append(Uint8List buffer, [int offset = 0, int length = 0]) async {
    if(length == 0)
      length = buffer.length - offset;
      
    int total = 0;
    await controller.synchronized(() async {
      await _allocateSpaceIfNotAvailable(length);
      final ranges = fragmentsManager.getAppendableRanges(length);
      
      for(final entry in ranges) {
        final range = entry.key;
        final fragment = entry.value;

        final written = await controller.write(buffer, range.start, offset, range.length);
        debug("Section.append; start = ${range.start}; end = ${range.end}; length = ${range.length}");
        if(written != range.length)
          throw(InputWriteReadException(proced: written, expected: range.length));

        total += written;
        offset += written;

        fragment.setPayloadSize(fragment.payloadSize + written);
        payloadSize += written;
        if(total == length)
          break;
      } await save();
      
      await fragmentsManager.save(true);
    });
    return total;
  }

  @override
  Future<int> write(Uint8List buffer, [int offset = 0, int length = 0]) async {
    if(length == 0)
      length = buffer.length - offset;
    final ranges = fragmentsManager.getWriteableRanges(position, length);

    int total = 0;
    await controller.synchronized(() async {
      for(final entry in ranges) {
        final range = entry.key;

        final start = range.start;
        final end = range.end;
        final written = await controller.write(buffer, start + size, offset, end);
        debug("Section.write; start = ${range.start}; end = ${range.end}; length = ${range.length}");
        if(written != range.length)
          throw(InputWriteReadException(proced: written, expected: range.length));
          
        total += written;
        offset += written;
        
        if(total == length)
          break;
      } position += total;
    });
    return total;
  }

  Future<void> _finishLoadData(int offset, int needle) async {    
    Fragment? next;
    while(needle > 0) {
      next = await _loadNextFragmentIfNotLoaded(offset, needle);
      if(next == null)
        throw(CorruptedSectionException(name: name, msg: "Need $needle bytes, but there are no more fragments"));
      needle -= next.payloadSize;
    }
  }

  Future<Fragment?> _loadNextFragmentIfNotLoaded(int dataOffset, int needle) async {
    bool flag = false;
    while(true) {
      FragmentReference? next;
      try {
        next = fragmentsManager.nextFragmentOffset;
      } on NeedMoreFragmentsException {
        if(flag)
          throw(Exception(""));
        await _loadNextTableIfNotLoaded();
        flag = true;
        continue;
      } if(next == null)
        return null;

      return await _loadConcreteFragment(next);
    }
  }

  Future<FragmentsTable?> _loadNextTableIfNotLoaded() async {
    FragmentsTableReference? next;
    try {
      next = fragmentsManager.nextTableOffset;
    } on NeedMoreTablesException {
      next = FragmentsTableReference(
        offset: firstTableOffset,
        size: firstTableSize,
      );
    } if(next == null)
      return null;
    
    return await _loadConcreteTable(
      offset: next.offset,
      size: next.size,
    );
    
  }

  Future<FragmentsTable> _loadConcreteTable({
    BufferPointer? buffer,
    required int offset,
    required int size,
  }) async {
    if(buffer == null) {
      final temp = IntrafileSystem.createBuffer(size);
      final read = await controller.read(temp, offset);
      
      buffer = new BufferPointer(temp, 0, read);
    }
    
    final table = await fragmentsManager.readTable(
      buffer,
      offset: offset,
    );
    return table;
  }

  Future<Fragment> _loadConcreteFragment(FragmentReference ref) async {
    final Uint8List temp = IntrafileSystem.createBuffer(Global.SECTION_MAX_HEAD_SIZE);
    final read = await controller.read(temp, ref.offset);
    
    final buffer = new BufferPointer(temp, 0, read);
    final fragment = await fragmentsManager.readFragment(
      buffer,
      reference: ref,
    );
    return fragment;
  }

  
  Future<void> _allocateSpaceIfNotAvailable(int length, [bool dontSave = false]) async {
    bool flag = false;
    while(true) {
      final ranges = fragmentsManager.getAppendableRanges(length);

      int fragmentsLength = 0;
      for(final e in ranges.map((e) => e.key.length))
        fragmentsLength += e;
      
      if(fragmentsLength >= length)
        break;
      if(flag) {
        throw(Exception("Internal error; fragmentsLength < length; $fragmentsLength < $length"));
      }
      
      await _immediatelyAllocateFragment(length - fragmentsLength, 0, dontSave);
      
      flag = true;
    }
    
  }

  Future<void> _allocateTable([bool dontSave = false]) async {
    final buffer = new BufferPointer.empty();
    final table = await fragmentsManager.createTable(
      buffer,
      offset: controller.length,
    );
    
    // ALLOCATING HEAD
    //--------------------------------------------------------------------------
    final written = await controller.append(buffer.buffer);
    if(written != buffer.length)
      throw(InputWriteReadException(proced: written, expected: buffer.length));
    //--------------------------------------------------------------------------
    
    // ALLOCATING SPACE
    //--------------------------------------------------------------------------
    await _allocateSpace(table.size);
    //--------------------------------------------------------------------------
    
    if(firstTableOffset == -1)
      firstTableOffset = table.offset;
      firstTableSize = table.size;
    
    lastTableOffset = table.offset;
    lastTableSize = table.size;

    await fragmentsManager.updateNextOffset(table.offset);
    
    if(!dontSave)
      await save();
  }

  Future<void> _immediatelyAllocateFragment(int size, int payloadSize, [bool dontSave = false]) async {
    bool flag = false;
    while(true) {
      try {
        await _allocateFragment(size, payloadSize, dontSave);
        break;
      } on NeedMoreTablesException {
        if(flag)
          throw(Exception("size = $size"));
        flag = true;
        await _allocateTable();
        continue;
      }
    }
  }

  Future<void> _allocateFragment(int size, int payloadSize, [bool dontSave = false]) async {
    final buffer = new BufferPointer.empty();
    final fragment = await fragmentsManager.createFragment(
      buffer,
      offset: controller.length,
      payloadSize: payloadSize,
      totalSize: size,
    );
    
    // ALLOCATING HEAD
    //--------------------------------------------------------------------------
    final written = await controller.append(buffer.buffer);
    if(written != buffer.length)
      throw(InputWriteReadException(proced: written, expected: buffer.length));
    //--------------------------------------------------------------------------
    
    // ALLOCATING SPACE
    //--------------------------------------------------------------------------
    await _allocateSpace(fragment.totalSize);
    //--------------------------------------------------------------------------

    this.payloadSize += fragment.payloadSize;
    this.totalSize += fragment.totalSize;
    
    if(!dontSave)
      await save();
  }

  Future<void> _allocateSpace(int size) async {
    final fillBuffer = IntrafileSystem.createBuffer(Global.FILE_APPEND_STEP);
    for(int i = Global.FILE_APPEND_STEP; true; i += Global.FILE_APPEND_STEP) {
      final toWrite = i > size ? (Global.FILE_APPEND_STEP - (i - size)) : Global.FILE_APPEND_STEP;
      
      final written = await controller.append(fillBuffer, 0, toWrite);
      if(written != toWrite)
        throw(InputWriteReadException(proced: written, expected: toWrite));
      if(i >= size)
        break;
    }
  }

  @override
  Future<void> save() async {
    await fragmentsManager.save(false);
    await super.save();
  }
}

class _FragmentImpl implements IFragment {
  final FragmentReference ref;
  _FragmentImpl(this.ref);

  @override
  int get offset => ref.offset;

  @override
  int get payloadSize => ref.payloadSize;

  @override
  int get totalSize => ref.totalSize;

}