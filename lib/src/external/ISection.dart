import 'dart:typed_data';

import 'IFragment.dart';

abstract class ISection {
  Iterable<IFragment> get fragments;

  int get length;

  void setPosition(int offset);
  
  int getPosition();

  Future<void> resize(int newSize);
  Future<int> read(Uint8List buffer, [int offset = 0, int length = 0]);
  Future<int> append(Uint8List buffer, [int offset = 0, int length = 0]);
  Future<int> write(Uint8List buffer, [int offset = 0, int length = 0]);
}