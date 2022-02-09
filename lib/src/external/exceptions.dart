

// Internal exceptions
//------------------------------------------------------------------------------
class NeedMoreFragmentsException extends IntraFileException {
  final int needle;
  NeedMoreFragmentsException(this.needle);
}

class NeedMoreTablesException extends IntraFileException {
  final int tables;
  final int fragment;
  NeedMoreTablesException(this.tables, [this.fragment = 0]);
}
//------------------------------------------------------------------------------

// class CorruptedInputException extends IntraFileException {
//   final int offset;
//   final int needle;
//   final int remaining;

//   CorruptedInputException({
//     required this.offset,
//     required this.needle,
//     required this.remaining,
//   });

//   @override
//   String toString() => "Input is corrupted. Expected $needle bytes, but remained $remaining. Absolute offset = $offset";
// }

class InputNotConnectedException extends IntraFileException {
  InputNotConnectedException();

  @override
  String toString() => "Input is not connected";
}

class SectionExistsException extends IntraFileException {
  final String name;

  SectionExistsException(this.name);

  @override
  String toString() => "Section [$name] already exists";
}

class HeadSectionNotFoundException extends IntraFileException {
  HeadSectionNotFoundException();
}

class UnknownIdentifierException extends IntraFileException {
  UnknownIdentifierException();
}

class CorruptedInputException extends IntraFileException {
  final int offset;

  CorruptedInputException({
    required this.offset,
  });

  @override
  String toString() => "Input is corrupted. Expected absolute offset $offset, but remained 0 bytes";
}

class InputWriteReadException extends IntraFileException {
  final int proced;
  final int expected;
  InputWriteReadException({
    required this.proced,
    required this.expected,
  });

  @override
  String toString() => "Input proced $proced bytes, but expected $expected";
}

class CorruptedSectionException extends IntraFileException {
  final String name;
  final String msg;
  CorruptedSectionException({
    required this.name,
    this.msg = "",
  });

  @override
  String toString() => "Section $name corrupted" + (msg.isNotEmpty ? ". $msg" : "");
}

abstract class IntraFileException implements Exception {}