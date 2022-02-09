import 'package:true_core/library.dart';

abstract class FragmentReference {
  static const int HEAD_SIZE = 8 + 8 + 8;

  int get offset;
  int get payloadSize;
  int get totalSize;



  int get freeSize;

  void setPayloadSize(int value);

  Range getAppendableRange(int length);
  Range? getSectionRange(int start, int end);
  Range? getPayloadRange(int start, int end);
}