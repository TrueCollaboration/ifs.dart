import 'dart:typed_data';

abstract class Global {
  static const String IDENTIFIER = "IFS";
  static final Uint8List IDENTIFIER_RAW = Uint8List.fromList(IDENTIFIER.codeUnits);
  static const int FILE_VERSION = 1;
  static const int SECTION_MAX_HEAD_SIZE = 8192;
  static const int FILE_APPEND_STEP = 8192;
  static const int DEFAULT_CLUSTER_SIZE = 4096;
  static const int DEFAULT_TABLE_SIZE = 2048;
  static const int FILL_BYTE = 72; //H
  static const String DEBUG_HEAD_NAME = "#HEAD";
}

void debug(dynamic v) {
    // print(v);
}