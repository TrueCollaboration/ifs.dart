import 'dart:typed_data';

import 'package:ifs/library.dart';

Future<void> main() async {
    final file = IntrafileSystem(
      source: "123.log",
    );
    final connected = await file.connect();
    log("connected = $connected");
    try {
      await file.readSections();

      try {
        await file.pushHeadSection("logger.ex");
      } catch(e,s) {
        print(e);
        print(s);
      }

      try {
        await file.pushSection("test");
      } catch(e,s) {
        print(e);
        print(s);
      }
      
      try {
        await file.pushSection("new");
      } catch(e,s) {
        print(e);
        print(s);
      }
    } catch(e,s) {
      print(e);
      print(s);
    }

    final section = file.getSection("test");

    if(section != null) {
      // debugger();
      await section.resize(555);
      
      final buffer = Uint8List(28660);
      int total = 0;
      int read;
      while((read = await section.read(buffer, 0)) != 0) {
        log("data = " + String.fromCharCodes(buffer.getRange(0, read)));
        total += read;
      }


      section.setPosition(section.length);
      // await section.write(buffer);
        // await section.append(Uint8List.fromList("!testing!".codeUnits), 0, 0);
      // debugger(when: total != 0);
      log("read = $total");
      //String.fromCharCodes(buffer)
      // await section.append(IntrafileSystem.createBuffer(9999, 97), 0, 0);
    }

    log("close");
    await file.close();
    // final a = await file.createSection();
}

void log(Object? v) => print("[main] " + (v?.toString() ?? "null"));