/// Gerador mínimo de planilha XLSX (Office Open XML) em Dart puro, sem
/// dependência nova: o app não tem pacote de Excel e o web gera o relatório
/// de fichas no navegador (`xlsx`/SheetJS), sem endpoint no back.
///
/// Suporta só o que o relatório precisa: várias abas, texto (inline string),
/// números, cabeçalho em negrito, largura de coluna e quebra de linha.
library;

import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// Uma aba: nome (≤ 31, sem `[]:*?/\`), linhas e larguras (em caracteres).
class XlsxSheet {
  XlsxSheet({
    required this.name,
    required this.rows,
    this.columnWidths = const [],
    this.headerRow = true,
  });

  final String name;

  /// Cada célula: `String`, `num` ou `null` (vazia).
  final List<List<Object?>> rows;
  final List<double> columnWidths;

  /// Primeira linha em negrito.
  final bool headerRow;
}

/// Monta o `.xlsx` e devolve os bytes.
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  if (sheets.isEmpty) {
    throw ArgumentError('A planilha precisa de ao menos uma aba.');
  }
  final names = <String>[];
  for (final s in sheets) {
    var n = xlsxSafeSheetName(s.name);
    var i = 2;
    final base = n;
    while (names.contains(n)) {
      final suf = ' ($i)';
      n = '${base.substring(0, (31 - suf.length).clamp(0, base.length))}$suf';
      i++;
    }
    names.add(n);
  }

  final files = <String, List<int>>{
    '[Content_Types].xml': utf8.encode(_contentTypes(sheets.length)),
    '_rels/.rels': utf8.encode(_rootRels),
    'xl/workbook.xml': utf8.encode(_workbook(names)),
    'xl/_rels/workbook.xml.rels': utf8.encode(_workbookRels(sheets.length)),
    'xl/styles.xml': utf8.encode(_styles),
    for (var i = 0; i < sheets.length; i++)
      'xl/worksheets/sheet${i + 1}.xml': utf8.encode(_sheetXml(sheets[i])),
  };
  return zipFiles(files);
}

/// Nome de aba válido para o Excel.
String xlsxSafeSheetName(String raw) {
  var s = raw.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (s.isEmpty) s = 'Planilha';
  if (s.length > 31) s = s.substring(0, 31);
  return s;
}

/// Letra(s) da coluna: 0 → A, 25 → Z, 26 → AA.
String xlsxColumnName(int index) {
  var n = index + 1;
  final sb = StringBuffer();
  while (n > 0) {
    final r = (n - 1) % 26;
    sb.write(String.fromCharCode(65 + r));
    n = (n - 1) ~/ 26;
  }
  return sb.toString().split('').reversed.join();
}

/// Escapa para XML e remove caracteres de controle que o Excel recusa.
String xlsxEscape(String s) {
  final clean = s.replaceAll(
    RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]'),
    '',
  );
  return clean
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// Limite de texto por célula no Excel.
const int _kMaxCell = 32767;

String _sheetXml(XlsxSheet sheet) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main">');
  if (sheet.headerRow && sheet.rows.isNotEmpty) {
    // Cabeçalho congelado.
    sb.write('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" '
        'topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>');
  }
  if (sheet.columnWidths.isNotEmpty) {
    sb.write('<cols>');
    for (var i = 0; i < sheet.columnWidths.length; i++) {
      sb.write('<col min="${i + 1}" max="${i + 1}" '
          'width="${sheet.columnWidths[i]}" customWidth="1"/>');
    }
    sb.write('</cols>');
  }
  sb.write('<sheetData>');
  for (var r = 0; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    final header = sheet.headerRow && r == 0;
    sb.write('<row r="${r + 1}">');
    for (var c = 0; c < row.length; c++) {
      final v = row[c];
      if (v == null) continue;
      final ref = '${xlsxColumnName(c)}${r + 1}';
      final style = header ? ' s="1"' : ' s="2"';
      if (v is num && v.isFinite) {
        sb.write('<c r="$ref"$style><v>$v</v></c>');
      } else {
        var text = v.toString();
        if (text.length > _kMaxCell) text = text.substring(0, _kMaxCell);
        sb.write('<c r="$ref" t="inlineStr"$style><is>'
            '<t xml:space="preserve">${xlsxEscape(text)}</t></is></c>');
      }
    }
    sb.write('</row>');
  }
  sb.write('</sheetData></worksheet>');
  return sb.toString();
}

String _contentTypes(int n) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
        'content-types">')
    ..write('<Default Extension="rels" ContentType="application/'
        'vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
    ..write('<Override PartName="/xl/styles.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
  for (var i = 1; i <= n; i++) {
    sb.write('<Override PartName="/xl/worksheets/sheet$i.xml" '
        'ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
  }
  sb.write('</Types>');
  return sb.toString();
}

const String _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships"><Relationship Id="rId1" Type="http://schemas.'
    'openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="xl/workbook.xml"/></Relationships>';

String _workbook(List<String> names) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<workbook xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships"><sheets>');
  for (var i = 0; i < names.length; i++) {
    sb.write('<sheet name="${xlsxEscape(names[i])}" sheetId="${i + 1}" '
        'r:id="rId${i + 1}"/>');
  }
  sb.write('</sheets></workbook>');
  return sb.toString();
}

String _workbookRels(int n) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/'
        '2006/relationships">');
  for (var i = 1; i <= n; i++) {
    sb.write('<Relationship Id="rId$i" Type="http://schemas.openxmlformats.'
        'org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet$i.xml"/>');
  }
  sb.write('<Relationship Id="rId${n + 1}" Type="http://schemas.'
      'openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/>');
  sb.write('</Relationships>');
  return sb.toString();
}

/// 0 = normal, 1 = cabeçalho em negrito, 2 = texto com quebra, topo.
const String _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
    '2006/main">'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
    '</border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
    'borderId="0"/></cellStyleXfs>'
    '<cellXfs count="3">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/>'
    '</cellStyles></styleSheet>';

// ─── ZIP (deflate, sem dependência) ─────────────────────────────────────────

final List<int> _crcTable = () {
  final t = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

/// CRC-32 (IEEE), o do ZIP.
int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Empacota os arquivos num ZIP (método deflate), na ordem do mapa.
Uint8List zipFiles(Map<String, List<int>> files) {
  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var offset = 0;
  // Data fixa (01/01/2026 00:00) — o conteúdo não depende do relógio.
  const dosTime = 0;
  const dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1;

  for (final e in files.entries) {
    final name = utf8.encode(e.key);
    final data = e.value;
    final crc = crc32(data);
    final comp = ZLibEncoder(raw: true, level: 6).convert(data);

    final local = ByteData(30);
    local.setUint32(0, 0x04034b50, Endian.little);
    local.setUint16(4, 20, Endian.little); // versão necessária
    local.setUint16(6, 0x0800, Endian.little); // nomes em UTF-8
    local.setUint16(8, 8, Endian.little); // deflate
    local.setUint16(10, dosTime, Endian.little);
    local.setUint16(12, dosDate, Endian.little);
    local.setUint32(14, crc, Endian.little);
    local.setUint32(18, comp.length, Endian.little);
    local.setUint32(22, data.length, Endian.little);
    local.setUint16(26, name.length, Endian.little);
    local.setUint16(28, 0, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(comp);

    final cd = ByteData(46);
    cd.setUint32(0, 0x02014b50, Endian.little);
    cd.setUint16(4, 20, Endian.little); // feito por
    cd.setUint16(6, 20, Endian.little); // versão necessária
    cd.setUint16(8, 0x0800, Endian.little);
    cd.setUint16(10, 8, Endian.little);
    cd.setUint16(12, dosTime, Endian.little);
    cd.setUint16(14, dosDate, Endian.little);
    cd.setUint32(16, crc, Endian.little);
    cd.setUint32(20, comp.length, Endian.little);
    cd.setUint32(24, data.length, Endian.little);
    cd.setUint16(28, name.length, Endian.little);
    // extra, comentário, disco, atributos internos/externos = 0
    cd.setUint32(42, offset, Endian.little);
    central
      ..add(cd.buffer.asUint8List())
      ..add(name);

    offset += 30 + name.length + comp.length;
  }

  final cdBytes = central.takeBytes();
  final end = ByteData(22);
  end.setUint32(0, 0x06054b50, Endian.little);
  end.setUint16(8, files.length, Endian.little);
  end.setUint16(10, files.length, Endian.little);
  end.setUint32(12, cdBytes.length, Endian.little);
  end.setUint32(16, offset, Endian.little);
  out
    ..add(cdBytes)
    ..add(end.buffer.asUint8List());
  return out.takeBytes();
}
