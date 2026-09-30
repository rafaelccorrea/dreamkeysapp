import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Planilhas geradas no próprio app (exportação de clientes e modelo de
/// importação), no mesmo formato que o web gera com a lib `xlsx`.
///
/// O `.xlsx` é um ZIP de XMLs; aqui o ZIP é montado em modo STORE (sem
/// compressão), o que dispensa dependência nova e é aberto normalmente por
/// Excel, Google Sheets e Numbers.
class ClientSpreadsheet {
  ClientSpreadsheet._();

  /// Monta um `.xlsx` de uma aba. Cada célula é `String` (texto) ou `num`
  /// (número); `null` vira célula vazia.
  static Uint8List buildXlsx({
    required String sheetName,
    required List<List<Object?>> rows,
    List<double>? columnWidths,
  }) {
    final sheet = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
      );
    if (columnWidths != null && columnWidths.isNotEmpty) {
      sheet.write('<cols>');
      for (var i = 0; i < columnWidths.length; i++) {
        sheet.write(
          '<col min="${i + 1}" max="${i + 1}" width="${columnWidths[i]}" customWidth="1"/>',
        );
      }
      sheet.write('</cols>');
    }
    sheet.write('<sheetData>');
    for (var r = 0; r < rows.length; r++) {
      sheet.write('<row r="${r + 1}">');
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        final value = row[c];
        final ref = '${_columnName(c)}${r + 1}';
        if (value == null || (value is String && value.isEmpty)) continue;
        if (value is num) {
          sheet.write('<c r="$ref"><v>$value</v></c>');
        } else {
          sheet.write(
            '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
            '${_escapeXml(value.toString())}</t></is></c>',
          );
        }
      }
      sheet.write('</row>');
    }
    sheet.write('</sheetData></worksheet>');

    final safeSheet = _escapeXml(
      sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName,
    );

    final files = <String, String>{
      '[Content_Types].xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '</Types>',
      '_rels/.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
      'xl/workbook.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="$safeSheet" sheetId="1" r:id="rId1"/></sheets>'
          '</workbook>',
      'xl/_rels/workbook.xml.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
          '</Relationships>',
      'xl/worksheets/sheet1.xml': sheet.toString(),
    };

    return _storeZip(
      files.map((name, content) => MapEntry(name, utf8.encode(content))),
    );
  }

  /// CSV separado por vírgula, com aspas quando a célula pede (mesma regra
  /// do `generateClientTemplate` do web).
  static Uint8List buildCsv(List<List<Object?>> rows) {
    String cell(Object? v) {
      if (v == null) return '';
      final s = v.toString();
      if (s.isEmpty) return '';
      if (s.contains(',') || s.contains('"') || s.contains('\n')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final text = rows.map((r) => r.map(cell).join(',')).join('\n');
    return Uint8List.fromList(utf8.encode(text));
  }

  /// Grava os bytes num arquivo temporário e abre a folha de compartilhar
  /// do sistema (salvar em Arquivos, mandar por WhatsApp, e-mail…).
  static Future<void> shareBytes({
    required List<int> bytes,
    required String fileName,
    String? subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: subject ?? fileName,
      ),
    );
  }

  // ───────────────────────── internos ─────────────────────────

  static String _columnName(int index) {
    var n = index + 1;
    var name = '';
    while (n > 0) {
      final rem = (n - 1) % 26;
      name = String.fromCharCode(65 + rem) + name;
      n = (n - 1) ~/ 26;
    }
    return name;
  }

  static String _escapeXml(String s) {
    final buffer = StringBuffer();
    for (final rune in s.runes) {
      // Caracteres de controle proibidos no XML 1.0 (exceto tab/LF/CR).
      if (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) {
        continue;
      }
      switch (rune) {
        case 0x26:
          buffer.write('&amp;');
          break;
        case 0x3C:
          buffer.write('&lt;');
          break;
        case 0x3E:
          buffer.write('&gt;');
          break;
        case 0x22:
          buffer.write('&quot;');
          break;
        default:
          buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    return c;
  });

  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// ZIP mínimo (método 0 = STORE), suficiente para o pacote OOXML.
  static Uint8List _storeZip(Map<String, List<int>> entries) {
    final out = BytesBuilder();
    final central = BytesBuilder();
    var offset = 0;

    void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
    void u32(BytesBuilder b, int v) => b.add([
          v & 0xFF,
          (v >> 8) & 0xFF,
          (v >> 16) & 0xFF,
          (v >> 24) & 0xFF,
        ]);

    for (final entry in entries.entries) {
      final name = utf8.encode(entry.key);
      final data = entry.value;
      final crc = _crc32(data);

      final local = BytesBuilder();
      u32(local, 0x04034b50);
      u16(local, 20); // versão necessária
      u16(local, 0x0800); // flag: nomes em UTF-8
      u16(local, 0); // STORE
      u16(local, 0); // hora
      u16(local, 0x21); // data (1980-01-01)
      u32(local, crc);
      u32(local, data.length);
      u32(local, data.length);
      u16(local, name.length);
      u16(local, 0);
      local.add(name);
      local.add(data);
      final localBytes = local.takeBytes();
      out.add(localBytes);

      u32(central, 0x02014b50);
      u16(central, 20); // versão que criou
      u16(central, 20); // versão necessária
      u16(central, 0x0800);
      u16(central, 0);
      u16(central, 0);
      u16(central, 0x21);
      u32(central, crc);
      u32(central, data.length);
      u32(central, data.length);
      u16(central, name.length);
      u16(central, 0); // extra
      u16(central, 0); // comentário
      u16(central, 0); // disco
      u16(central, 0); // atributos internos
      u32(central, 0); // atributos externos
      u32(central, offset);
      central.add(name);

      offset += localBytes.length;
    }

    final centralBytes = central.takeBytes();
    out.add(centralBytes);

    final end = BytesBuilder();
    u32(end, 0x06054b50);
    u16(end, 0);
    u16(end, 0);
    u16(end, entries.length);
    u16(end, entries.length);
    u32(end, centralBytes.length);
    u32(end, offset);
    u16(end, 0);
    out.add(end.takeBytes());

    return out.takeBytes();
  }
}
