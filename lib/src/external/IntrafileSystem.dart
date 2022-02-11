import 'dart:async';
import 'dart:typed_data';

import 'package:ifs/src/internal/ESectionResult.dart';
import 'package:ifs/src/internal/Section.dart';
import 'package:ifs/src/internal/SectionControllerImpl.dart';
import 'package:ifs/src/internal/sections/ExtandableSection.dart';
import 'package:ifs/src/internal/sections/HeadSection.dart';
import 'package:ifs/src/internal/util.dart';
import 'package:true_core/library.dart';

import 'ISection.dart';
import 'abstract/EInputType.dart';
import 'exceptions.dart';

/// TODO: defragmentation
class IntrafileSystem {  
  final int clusterSize;
  final InputController<Uint8List> input;
  IntrafileSystem({
    required String source,
    this.clusterSize = Global.DEFAULT_CLUSTER_SIZE,
  }) : input = FileInput(path: source);

  bool get connected    => input.connected;
  bool get connecting   => input.connecting;
  bool get closed       => input.closed;

  String? get identifier  => _identifier;
  int?    get version     => _version;

  Iterable<Section>? get sections => _readSectionsState == null ? null : _sections.where((e) => e is ExtandableSection).toList();

  Future<bool> connect() async {
    return await input.connect();
  }

  Future<bool> close() async {
    return await input.close();
  }

  final List<Section> _sections = [];
  Completer<void>? _readSectionsState;

  String? _identifier;
  int? _version;

  Future<bool> pushHeadSection(String identifier) async {
    if(closed)
      return false;
    if(_sections.isNotEmpty)
      throw(SectionExistsException(Global.DEBUG_HEAD_NAME));
    
    final controller = new SectionControllerImpl(
      intrafile: this,
    );
      
    final section = new HeadSection();
    section.version = Global.FILE_VERSION;
    section.identifier = identifier;

    controller.section = section;
    section.controller = controller;

    await input.synchronized(() async {
      controller.synced = true;
      section.offset = input.offset;
      
      final buffer = BufferPointer.empty();
      final result = await section.onCreate(buffer);
      if(result != ESectionResult.OK)
        throw(CorruptedSectionException(name: Global.DEBUG_HEAD_NAME, msg: "Error during build"));
      
      _debugCheckSection(section, Global.DEBUG_HEAD_NAME, buffer, EInputType.write);
        
      final written = await input.write(buffer.buffer);
      if(written != buffer.length)
        throw(InputWriteReadException(proced: written, expected: buffer.length));
        
      controller.synced = false;
    });
    _sections.add(section);

    _identifier = identifier;
    _version = Global.FILE_VERSION;
    return true;
  }

  Future<bool> pushSection(
    String name, {
      Uint8List? payload,
  }) async {
    if(closed)
      return false;
    if(_sections.isEmpty)
      throw(HeadSectionNotFoundException());
    if(_sections.tryFirstWhere((e) => e is ExtandableSection && e.name == name) != null)
      throw(SectionExistsException(name));
    
    payload ??= IntrafileSystem.createBuffer(0);
    
    final controller = new SectionControllerImpl(
      intrafile: this,
    );
      
    final section = new ExtandableSection();
    section.name = name;

    controller.section = section;
    section.controller = controller;
    
    await input.synchronized(() async {
      controller.synced = true;
      section.offset = input.offset;

      final buffer = BufferPointer.empty();
      final result = await section.onCreate(buffer);
      if(result != ESectionResult.OK)
        throw(CorruptedSectionException(name: name, msg: "Builder error"));
      
      _debugCheckSection(section, name, buffer, EInputType.write);
        
      final written = await input.write(buffer.buffer);
      if(written != buffer.length)
        throw(InputWriteReadException(proced: written, expected: buffer.length));
      
      if(payload != null)
        await section.append(payload);
      controller.synced = false;
    });
    final prevSection = _sections.tryLast;
    if(prevSection != null) {
      prevSection.nextSectionOffset = section.offset;
      await prevSection.save();
    } _sections.add(section);
    return true;
  }

  Future<void> readSections() async {
    if(!connected) {
      throw(InputNotConnectedException());
    } if(_readSectionsState != null)
      return _readSectionsState!.future;
    
    _readSectionsState = new Completer();    
    
    try {
      final exists = input.length != 0;
      if(exists) {
        await input.synchronized(() async {
          for(int i = 0; true; i++) {
            final section = i == 0 ? HeadSection() : ExtandableSection();
            if(!(await _parseSection(section)))
              break;
          }
        });
      }
    } catch(e,s) {
      _readSectionsState!.completeError(e, s);
      _readSectionsState = null;
      rethrow;      
    } _readSectionsState!.complete();
  }

  ISection? getSection(String name) {
    return _sections.tryFirstWhere((e) => e is ExtandableSection && e.name == name) as ExtandableSection?;
  }

  int _nextSectionOffset = 0;

  Future<bool> _parseSection(Section section) async {
    final controller = new SectionControllerImpl(
      intrafile: this,
    );
    controller.section = section;
    section.controller = controller;

    controller.synced = true;
    section.offset = _nextSectionOffset;
    
    
    await input.setPosition(_nextSectionOffset);

    bool ret = true;
    {
      final ESectionResult result;

      
      final Uint8List temp = IntrafileSystem.createBuffer(Global.SECTION_MAX_HEAD_SIZE);
      final read = await input.read(temp);
      final buffer = BufferPointer(temp, 0, read);
      final remaining = buffer.remaining;

      
      if(remaining == 0) {
        throw(CorruptedInputException(
          offset: _nextSectionOffset,
        ));
      }

      
      // PARSING SECTION
      //------------------------------------------------------------------------
      {
        result = await section.onRead(buffer);
      
        _debugCheckSection(section, section is ExtandableSection ? section.name : Global.DEBUG_HEAD_NAME, buffer, EInputType.read);

        if(result == ESectionResult.OK) {
          _nextSectionOffset = section.nextSectionOffset;
          if(section is HeadSection) {
            _identifier = identifier;
            _version = Global.FILE_VERSION;
            debug("Founded [${section.runtimeType}] section");
          } else {
            section as ExtandableSection;
            debug("Founded [${section.name}] section");
          } _sections.add(section);
        } else if(result == ESectionResult.CORRUPTED) {
          throw(CorruptedSectionException(name: "", msg: "Absolute offset ${section.offset}"));
        }
      }
      //------------------------------------------------------------------------
    }
    
    controller.synced = false;
    
    if(_nextSectionOffset == -1)
      ret = false;
    return ret;
  }

  // Future<int> _readToBuffer(BufferPointer bufferPointer, int offset) async {
  //   final Uint8List temp = IntrafileSystem.createBuffer(8192);
  //   final read = await input.readFrom(temp, offset);
  //   bufferPointer.pushBytes(temp, 0, read);
  //   return read;
  // }

  void _debugCheckSection(Section section, String debugName, BufferPointer buffer, EInputType type) {
    if(type == EInputType.write) {
      if(section.size != buffer.length)
        throw(CorruptedSectionException(name: debugName, msg: "section.size = ${section.size}, but written ${buffer.length}"));
    } else {
      if(section.size != buffer.offset)
        throw(CorruptedSectionException(name: debugName, msg: "section.size = ${section.size}, but read ${buffer.length}"));
    }
  }


  static Uint8List createBuffer(int length, [int fillBy = Global.FILL_BYTE]) {
    final buffer = Uint8List(length);
    for(int i = 0; i < length; i++)
      buffer[i] = fillBy;
    return buffer;
  }


  /// https://stackoverflow.com/questions/811195/fast-open-source-checksum-for-small-strings
  static int fastChecksum(Uint8List buffer) {
    int chk = 0x12345678;
    for (int i = 0; i < buffer.length; i++) {
      chk += (buffer[i] * (i + 1));
    } return chk & 0xffffffff;
  }
  
  static int roundSize(int size, int clusterSize) {
    int newSize = (size ~/ clusterSize) * clusterSize;
    if(newSize < size)
      newSize += clusterSize;
    return newSize == 0 ? clusterSize : newSize;
  }
}