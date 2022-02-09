abstract class InputWriter<T extends List> {
  /// Writes to the end of input from buffer with [offset] and [length] if present
  /// 
  /// Returns writed length
  Future<int> append(T buffer, [int offset = 0, int length = 0]);

  /// Writes from buffer with [offset] and [length] if present
  /// 
  /// Returns writed length
  Future<int> write(T buffer, [int offset = 0, int length = 0]);

  /// Writes from buffer with [offset] and [length]
  /// to [dstOffset]
  /// 
  /// Returns writed length
  Future<int> writeTo(
    T buffer,
    int dstOffset, [
      int offset = 0, int length = 0,
  ]);
}