import 'dart:typed_data';

import 'package:ifs/src/external/exceptions.dart';
import 'package:ifs/src/internal/ESectionResult.dart';
import 'package:ifs/src/internal/Section.dart';
import 'package:ifs/src/internal/util.dart';
import 'package:true_core/core/library.dart';

// SECTION STRUCTURE
//------------------------------------------------------------------------------
// [N] IDENTIFIER
// [8] version
// [4] length of sub identifier
// [8] next section (relative offset)
// [N] identifier
//------------------------------------------------------------------------------

class HeadSection extends Section {
  HeadSection();

  @override
  int get size => intraIdentifierLength + 8 + 4 + 8 + identifierLength;



  int intraIdentifierLength = 0;

  late final int version;

  int identifierLength = 0;

  @override
  int nextSectionOffset = -1;
  
  late final String identifier;

  @override
  Future<ESectionResult> onCreate(BufferPointer buffer) async {
    final Uint8List intraIdentifier;
    final int version;
    final int identifierLength;
    final int nextSectionOffset;
    final Uint8List identifier;
    
    intraIdentifier = Global.IDENTIFIER_RAW;
    version = Global.FILE_VERSION;
    nextSectionOffset = this.nextSectionOffset;
    identifier = Uint8List.fromList(this.identifier.codeUnits);
    identifierLength = identifier.length;
    
    buffer.pushBytes(intraIdentifier);
    buffer.pushUInt64(version);
    buffer.pushUInt32(identifierLength);
    buffer.pushUInt64(nextSectionOffset);
    buffer.pushBytes(identifier);

    this.intraIdentifierLength = intraIdentifier.length;
    this.identifierLength = identifierLength;
    
    return ESectionResult.OK;
  }
  
  @override
  Future<ESectionResult> onRead(BufferPointer buffer) async {
    final Uint8List intraIdentifier = Global.IDENTIFIER_RAW;
    final int version;
    final int identifierLength;
    final int nextSectionOffset;
    final Uint8List identifier;
    
    {
      final int length = intraIdentifier.length;
      final temp = buffer.getBytes(length)!;
      for(int i = 0; i < length; i++) {
        if(temp[i] != intraIdentifier[i])
          throw(UnknownIdentifierException());
      }
    }

    version = buffer.getUint64()!;

    identifierLength = buffer.getUint32()!;

    nextSectionOffset = buffer.getUint64()!;

    identifier = buffer.getBytes(identifierLength)!;

    this.intraIdentifierLength = intraIdentifier.length;
    this.version = version;
    this.identifierLength = identifierLength;
    this.nextSectionOffset = nextSectionOffset;
    this.identifier = String.fromCharCodes(identifier);
    
    return ESectionResult.OK;
  }
}