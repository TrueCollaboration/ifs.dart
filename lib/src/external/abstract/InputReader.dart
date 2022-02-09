abstract class InputReader<T extends List> {
  /// Read into buffer with [offset] and [length] if present
  /// 
  /// Returns read length
  Future<int> read(T buffer, [int offset = 0, int length = 0]);

  /// Read into buffer with [offset] and [length]
  /// from [dstOffset]
  /// 
  /// Returns read length
  Future<int> readFrom(T buffer, int dstOffset, [int offset = 0, int length = 0]);
}