import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'app_state.dart';
import 'device_bridge.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

class PdfTableColumn {
  const PdfTableColumn(
    this.header, {
    this.flex = 1.0,
    this.alignRight = false,
  });

  final String header;
  final double flex;
  final bool alignRight;
}

class PdfDocumentSpec {
  const PdfDocumentSpec({
    required this.documentType,
    required this.documentNumber,
    required this.title,
    this.subtitle = '',
    this.status = '',
    this.dateLabel = '',
    this.companyName = '',
    this.entityName = '',
    this.branchName = '',
    this.metaPairs = const [],
    this.columns = const [],
    this.rows = const [],
    this.totals = const [],
    this.notes = const [],
  });

  final String documentType;
  final String documentNumber;
  final String title;
  final String subtitle;
  final String status;
  final String dateLabel;
  final String companyName;
  final String entityName;
  final String branchName;
  final List<(String, String)> metaPairs;
  final List<PdfTableColumn> columns;
  final List<List<String>> rows;
  final List<(String, String)> totals;
  final List<String> notes;
}

String _pdfSafeText(String raw) {
  var s = raw
      .replaceAll('₹', 'Rs. ')
      .replaceAll('·', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('×', 'x')
      .replaceAll('•', '*')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ');
  final buf = StringBuffer();
  for (final code in s.runes) {
    if (code >= 32 && code <= 126) {
      buf.writeCharCode(code);
    } else if (code >= 160 && code <= 255) {
      buf.writeCharCode(code);
    } else {
      buf.write(' ');
    }
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');
}

List<String> _wrapText(String text, int maxChars) {
  final clean = text
      .replaceAll('₹', 'Rs. ')
      .replaceAll('·', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('×', 'x')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.isEmpty) return const ['-'];
  if (clean.length <= maxChars) return [clean];
  final words = clean.split(' ');
  final lines = <String>[];
  var current = '';
  for (final w in words) {
    if (current.isEmpty) {
      if (w.length <= maxChars) {
        current = w;
      } else {
        for (var i = 0; i < w.length; i += maxChars) {
          final part = w.substring(i, i + maxChars > w.length ? w.length : i + maxChars);
          if (part.length == maxChars) {
            lines.add(part);
          } else {
            current = part;
          }
        }
      }
    } else if (current.length + 1 + w.length <= maxChars) {
      current = '$current $w';
    } else {
      lines.add(current);
      current = w.length <= maxChars ? w : w.substring(0, maxChars);
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.take(4).toList();
}

/// Standards-compliant pure-Dart PDF 1.4 A4 vector document generator (`595.28 x 841.89 pt`).
Uint8List buildErpPdfBytes(PdfDocumentSpec spec) {
  const pageW = 595.28;
  const pageH = 841.89;
  const marginX = 36.0;
  const contentW = pageW - marginX * 2;
  const bottomLimit = 62.0;

  final pages = <StringBuffer>[];
  late StringBuffer cur;
  double y = pageH - 36.0;

  void startNewPage({required bool firstPage}) {
    cur = StringBuffer();
    pages.add(cur);

    // Top Royal Gold + Espresso Executive Header Band
    final bandH = firstPage ? 78.0 : 46.0;
    final bandTop = pageH - 28.0;
    final bandBottom = bandTop - bandH;

    // Espresso fill (#1E150B)
    cur.writeln('0.118 0.082 0.043 rg');
    cur.writeln('$marginX ${bandBottom.toStringAsFixed(2)} ${contentW.toStringAsFixed(2)} ${bandH.toStringAsFixed(2)} re f');
    // Royal Gold accent rule (#C69214)
    cur.writeln('0.776 0.573 0.078 rg');
    cur.writeln('$marginX ${bandBottom.toStringAsFixed(2)} ${contentW.toStringAsFixed(2)} 3.2 re f');

    final brand = spec.companyName.trim().isNotEmpty ? spec.companyName.trim() : 'Karvix';
    final subBrand = [
      if (spec.entityName.trim().isNotEmpty) spec.entityName.trim(),
      if (spec.branchName.trim().isNotEmpty) spec.branchName.trim(),
    ].join(' - ');

    // Brand text (left)
    cur.writeln('BT /F2 ${firstPage ? 15 : 11} Tf 0.96 0.87 0.62 rg ${(marginX + 14).toStringAsFixed(2)} ${(bandTop - (firstPage ? 24 : 19)).toStringAsFixed(2)} Td (${_pdfSafeText(brand)}) Tj ET');
    if (firstPage && subBrand.isNotEmpty) {
      cur.writeln('BT /F1 9 Tf 0.88 0.84 0.76 rg ${(marginX + 14).toStringAsFixed(2)} ${(bandTop - 40).toStringAsFixed(2)} Td (${_pdfSafeText(subBrand)}) Tj ET');
    }
    if (firstPage) {
      final titleLine = spec.title.trim().isNotEmpty ? spec.title.trim() : spec.documentType;
      cur.writeln('BT /F1 9.5 Tf 1 1 1 rg ${(marginX + 14).toStringAsFixed(2)} ${(bandTop - 58).toStringAsFixed(2)} Td (${_pdfSafeText(titleLine)}) Tj ET');
    }

    // Document Type + Number (right)
    final docBadge = spec.documentType.toUpperCase();
    final docNum = spec.documentNumber;
    final badgeX = pageW - marginX - 14 - (docBadge.length * 5.6);
    cur.writeln('BT /F2 10 Tf 0.96 0.87 0.62 rg ${badgeX.clamp(marginX + 240, pageW - marginX - 20).toStringAsFixed(2)} ${(bandTop - (firstPage ? 23 : 19)).toStringAsFixed(2)} Td (${_pdfSafeText(docBadge)}) Tj ET');
    if (firstPage && docNum.isNotEmpty) {
      final numX = pageW - marginX - 14 - (docNum.length * 5.4);
      cur.writeln('BT /F3 9.5 Tf 1 1 1 rg ${numX.clamp(marginX + 240, pageW - marginX - 20).toStringAsFixed(2)} ${(bandTop - 40).toStringAsFixed(2)} Td (${_pdfSafeText(docNum)}) Tj ET');
      final statusDate = [
        if (spec.status.trim().isNotEmpty) spec.status.trim(),
        if (spec.dateLabel.trim().isNotEmpty) spec.dateLabel.trim(),
      ].join(' | ');
      if (statusDate.isNotEmpty) {
        final sdX = pageW - marginX - 14 - (statusDate.length * 4.7);
        cur.writeln('BT /F1 8.5 Tf 0.88 0.84 0.76 rg ${sdX.clamp(marginX + 220, pageW - marginX - 20).toStringAsFixed(2)} ${(bandTop - 57).toStringAsFixed(2)} Td (${_pdfSafeText(statusDate)}) Tj ET');
      }
    }

    y = bandBottom - 16.0;
  }

  void ensureSpace(double neededHeight, {VoidCallback? onNewPage}) {
    if (y - neededHeight < bottomLimit) {
      startNewPage(firstPage: false);
      onNewPage?.call();
    }
  }

  startNewPage(firstPage: true);

  if (spec.subtitle.trim().isNotEmpty) {
    ensureSpace(18);
    cur.writeln('BT /F1 9 Tf 0.35 0.31 0.26 rg $marginX ${y.toStringAsFixed(2)} Td (${_pdfSafeText(spec.subtitle)}) Tj ET');
    y -= 14;
  }

  // Metadata 2-column box
  if (spec.metaPairs.isNotEmpty) {
    final rowsCount = (spec.metaPairs.length + 1) ~/ 2;
    final boxH = rowsCount * 22.0 + 12.0;
    ensureSpace(boxH + 10);
    final boxBottom = y - boxH;
    cur.writeln('0.985 0.976 0.955 rg');
    cur.writeln('$marginX ${boxBottom.toStringAsFixed(2)} ${contentW.toStringAsFixed(2)} ${boxH.toStringAsFixed(2)} re f');
    cur.writeln('0.86 0.81 0.70 RG 0.7 w');
    cur.writeln('$marginX ${boxBottom.toStringAsFixed(2)} ${contentW.toStringAsFixed(2)} ${boxH.toStringAsFixed(2)} re S');

    final halfW = contentW / 2;
    for (var i = 0; i < spec.metaPairs.length; i++) {
      final col = i % 2;
      final r = i ~/ 2;
      final cellX = marginX + 10 + col * halfW;
      final rowY = y - 15 - r * 22.0;
      final k = spec.metaPairs[i].$1.toUpperCase();
      final vLines = _wrapText(spec.metaPairs[i].$2, 34);
      cur.writeln('BT /F2 7.5 Tf 0.45 0.38 0.26 rg ${cellX.toStringAsFixed(2)} ${rowY.toStringAsFixed(2)} Td (${_pdfSafeText(k)}) Tj ET');
      cur.writeln('BT /F1 9 Tf 0.10 0.08 0.06 rg ${(cellX + 88).toStringAsFixed(2)} ${rowY.toStringAsFixed(2)} Td (${_pdfSafeText(vLines.first)}) Tj ET');
    }
    y = boxBottom - 16.0;
  }

  // Table Section
  if (spec.columns.isNotEmpty) {
    final totalFlex = spec.columns.fold<double>(0.0, (a, c) => a + c.flex);
    final colWidths = spec.columns.map((c) => contentW * (c.flex / totalFlex)).toList();

    void drawTableHeader() {
      const h = 22.0;
      final bottom = y - h;
      cur.writeln('0.95 0.91 0.80 rg');
      cur.writeln('$marginX ${bottom.toStringAsFixed(2)} ${contentW.toStringAsFixed(2)} $h re f');
      cur.writeln('0.78 0.65 0.35 RG 0.7 w');
      cur.writeln('$marginX ${bottom.toStringAsFixed(2)} ${contentW.toStringAsFixed(2)} $h re S');

      var cx = marginX;
      for (var c = 0; c < spec.columns.length; c++) {
        final col = spec.columns[c];
        final cw = colWidths[c];
        final hdr = col.header.toUpperCase();
        final tx = col.alignRight
            ? (cx + cw - 6 - hdr.length * 4.5).clamp(cx + 4, cx + cw - 4)
            : cx + 6;
        cur.writeln('BT /F2 8 Tf 0.25 0.18 0.06 rg ${tx.toStringAsFixed(2)} ${(bottom + 7).toStringAsFixed(2)} Td (${_pdfSafeText(hdr)}) Tj ET');
        cx += cw;
      }
      y = bottom;
    }

    ensureSpace(44);
    drawTableHeader();

    if (spec.rows.isEmpty) {
      const rh = 26.0;
      final bottom = y - rh;
      cur.writeln('0.88 0.85 0.79 RG 0.5 w');
      cur.writeln('$marginX ${bottom.toStringAsFixed(2)} ${contentW.toStringAsFixed(2)} $rh re S');
      cur.writeln('BT /F1 9 Tf 0.45 0.42 0.38 rg ${(marginX + 10).toStringAsFixed(2)} ${(bottom + 9).toStringAsFixed(2)} Td (No itemized rows recorded.) Tj ET');
      y = bottom - 12;
    } else {
      for (var rIdx = 0; rIdx < spec.rows.length; rIdx++) {
        final row = spec.rows[rIdx];
        final wrappedCells = <List<String>>[];
        var maxLines = 1;
        for (var c = 0; c < spec.columns.length; c++) {
          final txt = c < row.length ? row[c] : '';
          final maxCh = ((colWidths[c] - 10) / 4.8).floor().clamp(8, 64);
          final wl = _wrapText(txt, maxCh);
          wrappedCells.add(wl);
          if (wl.length > maxLines) maxLines = wl.length;
        }
        final rh = maxLines * 12.0 + 8.0;
        ensureSpace(rh + 4, onNewPage: drawTableHeader);

        final bottom = y - rh;
        if (rIdx.isOdd) {
          cur.writeln('0.99 0.985 0.972 rg');
          cur.writeln('$marginX ${bottom.toStringAsFixed(2)} ${contentW.toStringAsFixed(2)} ${rh.toStringAsFixed(2)} re f');
        }
        cur.writeln('0.89 0.86 0.80 RG 0.45 w');
        cur.writeln('$marginX ${bottom.toStringAsFixed(2)} ${contentW.toStringAsFixed(2)} ${rh.toStringAsFixed(2)} re S');

        var cx = marginX;
        for (var c = 0; c < spec.columns.length; c++) {
          final col = spec.columns[c];
          final cw = colWidths[c];
          final lines = wrappedCells[c];
          for (var li = 0; li < lines.length; li++) {
            final lineStr = lines[li];
            final ly = y - 13.0 - li * 12.0;
            final font = col.alignRight ? '/F3' : '/F1';
            final charW = col.alignRight ? 5.0 : 4.6;
            final tx = col.alignRight
                ? (cx + cw - 6 - lineStr.length * charW).clamp(cx + 4, cx + cw - 4)
                : cx + 6;
            cur.writeln('BT $font 8.5 Tf 0.12 0.10 0.08 rg ${tx.toStringAsFixed(2)} ${ly.toStringAsFixed(2)} Td (${_pdfSafeText(lineStr)}) Tj ET');
          }
          cx += cw;
        }
        y = bottom;
      }
      y -= 14;
    }
  }

  // Totals Box (right-aligned)
  if (spec.totals.isNotEmpty) {
    final totBoxW = 250.0;
    final totBoxH = spec.totals.length * 19.0 + 12.0;
    ensureSpace(totBoxH + 14);
    final boxX = pageW - marginX - totBoxW;
    final boxBottom = y - totBoxH;

    cur.writeln('0.985 0.975 0.945 rg');
    cur.writeln('${boxX.toStringAsFixed(2)} ${boxBottom.toStringAsFixed(2)} ${totBoxW.toStringAsFixed(2)} ${totBoxH.toStringAsFixed(2)} re f');
    cur.writeln('0.78 0.65 0.35 RG 0.8 w');
    cur.writeln('${boxX.toStringAsFixed(2)} ${boxBottom.toStringAsFixed(2)} ${totBoxW.toStringAsFixed(2)} ${totBoxH.toStringAsFixed(2)} re S');

    for (var i = 0; i < spec.totals.length; i++) {
      final isLast = i == spec.totals.length - 1;
      final ry = y - 15.0 - i * 19.0;
      final k = spec.totals[i].$1;
      final v = _wrapText(spec.totals[i].$2, 24).first;
      final fKey = isLast ? '/F2 9.5' : '/F1 8.5';
      final fVal = isLast ? '/F2 10' : '/F3 8.8';
      cur.writeln('BT $fKey Tf 0.22 0.17 0.08 rg ${(boxX + 10).toStringAsFixed(2)} ${ry.toStringAsFixed(2)} Td (${_pdfSafeText(k)}) Tj ET');
      final vx = (boxX + totBoxW - 10 - v.length * 5.2).clamp(boxX + 115, boxX + totBoxW - 8);
      cur.writeln('BT $fVal Tf 0.10 0.08 0.05 rg ${vx.toStringAsFixed(2)} ${ry.toStringAsFixed(2)} Td (${_pdfSafeText(v)}) Tj ET');
    }
    y = boxBottom - 16.0;
  }

  // Notes & Authorised Signatory
  if (spec.notes.isNotEmpty) {
    ensureSpace(spec.notes.length * 14.0 + 36.0);
    cur.writeln('BT /F2 8 Tf 0.42 0.35 0.22 rg $marginX ${y.toStringAsFixed(2)} Td (TERMS & AUDIT NOTES) Tj ET');
    y -= 13;
    for (final n in spec.notes) {
      for (final wl in _wrapText(n, 95)) {
        ensureSpace(14);
        cur.writeln('BT /F1 8.2 Tf 0.30 0.27 0.23 rg $marginX ${y.toStringAsFixed(2)} Td (${_pdfSafeText(wl)}) Tj ET');
        y -= 12;
      }
    }
    y -= 8;
  }

  ensureSpace(44);
  cur.writeln('0.82 0.78 0.70 RG 0.5 w');
  cur.writeln('${(pageW - marginX - 160).toStringAsFixed(2)} ${(y - 24).toStringAsFixed(2)} 160 0.5 re S');
  cur.writeln('BT /F2 8.5 Tf 0.25 0.20 0.12 rg ${(pageW - marginX - 132).toStringAsFixed(2)} ${(y - 36).toStringAsFixed(2)} Td (Authorised Signatory) Tj ET');

  // Add page footer to every page
  final generatedAt = DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
  for (var p = 0; p < pages.length; p++) {
    final pb = pages[p];
    pb.writeln('0.85 0.82 0.75 RG 0.5 w');
    pb.writeln('$marginX 42 ${contentW.toStringAsFixed(2)} 0.4 re S');
    pb.writeln('BT /F1 7.5 Tf 0.45 0.42 0.38 rg $marginX 30 Td (Generated by Karvix | $generatedAt) Tj ET');
    pb.writeln('BT /F1 7.5 Tf 0.45 0.42 0.38 rg ${(pageW - marginX - 56).toStringAsFixed(2)} 30 Td (Page ${p + 1} of ${pages.length}) Tj ET');
  }

  // Assemble PDF 1.4 objects + cross-reference table
  // 1: Catalog, 2: Pages, 3: Helvetica, 4: Helvetica-Bold, 5: Courier
  // Then for each page i: contentObj = 6 + i*2, pageObj = 7 + i*2
  final objects = <int, List<int>>{};
  final pageObjIds = <int>[];

  objects[3] = ascii.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  objects[4] = ascii.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
  objects[5] = ascii.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>');

  for (var i = 0; i < pages.length; i++) {
    final contentId = 6 + i * 2;
    final pageId = 7 + i * 2;
    pageObjIds.add(pageId);
    final streamBytes = latin1.encode(pages[i].toString());
    final contentHeader = ascii.encode('<< /Length ${streamBytes.length} >>\nstream\n');
    final contentFooter = ascii.encode('\nendstream');
    objects[contentId] = <int>[...contentHeader, ...streamBytes, ...contentFooter];
    objects[pageId] = ascii.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] '
      '/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> '
      '/Contents $contentId 0 R >>',
    );
  }

  final kids = pageObjIds.map((id) => '$id 0 R').join(' ');
  objects[2] = ascii.encode('<< /Type /Pages /Kids [ $kids ] /Count ${pageObjIds.length} >>');
  objects[1] = ascii.encode('<< /Type /Catalog /Pages 2 0 R >>');

  final maxId = 5 + pages.length * 2;
  final out = <int>[];
  final offsets = List<int>.filled(maxId + 1, 0);

  void writeAscii(String s) => out.addAll(ascii.encode(s));

  writeAscii('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
  for (var id = 1; id <= maxId; id++) {
    offsets[id] = out.length;
    writeAscii('$id 0 obj\n');
    out.addAll(objects[id]!);
    writeAscii('\nendobj\n');
  }

  final xrefOffset = out.length;
  writeAscii('xref\n0 ${maxId + 1}\n');
  writeAscii('0000000000 65535 f \n');
  for (var id = 1; id <= maxId; id++) {
    writeAscii('${offsets[id].toString().padLeft(10, '0')} 00000 n \n');
  }
  writeAscii('trailer\n<< /Size ${maxId + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n');

  return Uint8List.fromList(out);
}

/// High-level helper that generates a real `.pdf` document, saves it directly into
/// `Downloads/JewelleryERP/` on the phone, and surfaces instant `Open PDF` / `Share PDF`
/// / `Print HTML` actions.
class ErpPdfExporter {
  ErpPdfExporter._();

  static Future<void> downloadSpec(
    BuildContext context, {
    required PdfDocumentSpec spec,
    String? fileName,
    String? renderedHtml,
  }) async {
    AppState? app;
    try {
      app = context.read<AppState>();
    } catch (_) {}

    final enriched = PdfDocumentSpec(
      documentType: spec.documentType,
      documentNumber: spec.documentNumber,
      title: spec.title,
      subtitle: spec.subtitle,
      status: spec.status,
      dateLabel: spec.dateLabel.isNotEmpty ? spec.dateLabel : todayIso(),
      companyName: spec.companyName.isNotEmpty
          ? spec.companyName
          : (app?.tenantName ?? 'Karvix'),
      entityName: spec.entityName.isNotEmpty ? spec.entityName : (app?.entityName ?? ''),
      branchName: spec.branchName.isNotEmpty ? spec.branchName : (app?.branchName ?? ''),
      metaPairs: spec.metaPairs,
      columns: spec.columns,
      rows: spec.rows,
      totals: spec.totals,
      notes: spec.notes,
    );

    final cleanCode = enriched.documentNumber
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final targetName = fileName ??
        '${enriched.documentType.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}-${cleanCode.isEmpty ? 'DOC' : cleanCode}.pdf';

    try {
      final bytes = buildErpPdfBytes(enriched);
      final saved = await DeviceBridge.saveToDownloads(
        bytes: bytes,
        fileName: targetName.endsWith('.pdf') ? targetName : '$targetName.pdf',
      );
      if (!context.mounted) return;
      await _showDownloadedSheet(
        context,
        fileName: targetName.endsWith('.pdf') ? targetName : '$targetName.pdf',
        saved: saved,
        spec: enriched,
        renderedHtml: renderedHtml,
      );
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Unable to download PDF.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF download failed: $e')),
      );
    }
  }

  /// Downloads any ERP record card (Payment Receipt, Settlement, Voucher, Order,
  /// Invoice, Transfer, Refining Batch, etc.) as a formatted PDF.
  static Future<void> downloadRecordCard(
    BuildContext context, {
    required String code,
    required String status,
    required List<(String, String)> lines,
    String documentType = 'ERP VOUCHER',
    String? amountLabel,
    String? amountValue,
  }) {
    return downloadSpec(
      context,
      spec: PdfDocumentSpec(
        documentType: documentType,
        documentNumber: code,
        title: '$documentType - $code',
        status: status,
        dateLabel: todayIso(),
        metaPairs: [
          ('Document #', code),
          ('Status', status.isEmpty ? 'RECORDED' : status),
          ...lines,
        ],
        columns: const [
          PdfTableColumn('Field', flex: 1.4),
          PdfTableColumn('Recorded Value', flex: 2.6),
        ],
        rows: [
          for (final l in lines) [l.$1, l.$2],
          if (amountLabel != null && amountValue != null) [amountLabel, amountValue],
        ],
        totals: [
          if (amountLabel != null && amountValue != null) (amountLabel, amountValue),
        ],
        notes: const [
          'Official Karvix record exported from live workspace.',
        ],
      ),
    );
  }

  /// Downloads a full GST Sales Invoice / POS Bill map as a multi-column A4 PDF.
  static Future<void> downloadSalesInvoice(
    BuildContext context,
    Map<String, dynamic> inv, {
    String? renderedHtml,
  }) {
    final docNo = '${inv['documentNumber'] ?? inv['invoiceNumber'] ?? shortId('${inv['id'] ?? 'INV'}')}';
    final invDate = fmtDate('${inv['invoiceDate'] ?? inv['createdAt'] ?? todayIso()}');
    final cust = asMap(inv['customer']);
    final custName = '${cust['displayName'] ?? inv['customerName'] ?? 'Walk-in Customer'}';
    final state = '${inv['state'] ?? inv['status'] ?? 'POSTED'}';
    final lines = asList(inv['lines']);

    final tableRows = <List<String>>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final art = asMap(l['article']);
      final desc = '${art['description'] ?? l['description'] ?? art['tag'] ?? l['articleTag'] ?? 'Tagged Jewellery Piece'}';
      final wt = '${art['netWeightGrams'] ?? art['grossWeightGrams'] ?? l['weightGrams'] ?? '-'}';
      final making = inr(l['makingAmount'] ?? l['makingCharge'] ?? '0.00');
      final tax = inr(l['taxAmount'] ?? l['gstAmount'] ?? '0.00');
      final total = inr(l['lineTotal'] ?? l['totalAmount'] ?? inv['totalAmount'] ?? '0.00');
      tableRows.add(['${i + 1}', desc, wt, making, tax, total]);
    }
    if (tableRows.isEmpty) {
      tableRows.add([
        '1',
        'Showroom Jewellery Bill ($docNo)',
        '-',
        inr(inv['makingSubtotal'] ?? inv['makingAmount'] ?? '0.00'),
        inr(inv['taxAmount'] ?? inv['gstAmount'] ?? '0.00'),
        inr(inv['totalAmount'] ?? '0.00'),
      ]);
    }

    final taxable = inr(inv['taxableAmount'] ?? inv['subtotalAmount'] ?? inv['metalSubtotal'] ?? '0.00');
    final taxAmt = inr(inv['taxAmount'] ?? inv['gstAmount'] ?? '0.00');
    final totalAmt = inr(inv['totalAmount'] ?? '0.00');
    final paidAmt = inv['paidAmount'] != null ? inr(inv['paidAmount']) : null;
    final outstanding = inv['outstandingAmount'] ?? inv['openAmount'] ?? inv['balanceAmount'];

    return downloadSpec(
      context,
      fileName: 'Tax-Invoice-$docNo.pdf',
      renderedHtml: renderedHtml,
      spec: PdfDocumentSpec(
        documentType: 'TAX INVOICE',
        documentNumber: docNo,
        title: 'GST Retail Jewellery Tax Invoice',
        status: state,
        dateLabel: invDate,
        metaPairs: [
          ('Invoice No', docNo),
          ('Invoice Date', invDate),
          ('Customer', custName),
          ('Lifecycle State', state),
          if ('${cust['gstin'] ?? inv['customerGstin'] ?? ''}'.isNotEmpty)
            ('Customer GSTIN', '${cust['gstin'] ?? inv['customerGstin']}'),
          if ('${inv['paymentMode'] ?? ''}'.isNotEmpty)
            ('Settlement Mode', '${inv['paymentMode']}'),
        ],
        columns: const [
          PdfTableColumn('#', flex: 0.4),
          PdfTableColumn('Ornament / Tag', flex: 2.3),
          PdfTableColumn('Weight (g)', flex: 0.9, alignRight: true),
          PdfTableColumn('Making', flex: 1.0, alignRight: true),
          PdfTableColumn('GST', flex: 0.9, alignRight: true),
          PdfTableColumn('Line Total', flex: 1.2, alignRight: true),
        ],
        rows: tableRows,
        totals: [
          ('Taxable Value', taxable),
          ('GST Amount', taxAmt),
          if (inv['oldGoldCredit'] != null)
            ('Old Gold Credit', '- ${inr(inv['oldGoldCredit'])}'),
          if (paidAmt != null) ('Amount Paid', paidAmt),
          if (outstanding != null) ('Outstanding', inr(outstanding)),
          ('Grand Total', totalAmt),
        ],
        notes: const [
          'Goods once sold are subject to showroom exchange & hallmark verification policy.',
          'Posted with double-entry ledger & one-article-one-sale custody integrity.',
        ],
      ),
    );
  }

  static Future<void> _showDownloadedSheet(
    BuildContext context, {
    required String fileName,
    required SavedDownloadResult saved,
    required PdfDocumentSpec spec,
    String? renderedHtml,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Pal.card,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Pal.okWash,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.download_done_rounded,
                    color: Pal.ok,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PDF Downloaded to Device',
                        style: T.body(15.5, w: FontWeight.w800),
                      ),
                      Text(
                        saved.savedPath,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: T.mono(11.5, color: Pal.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!kIsWeb && saved.uri.isNotEmpty) ...[
              RoyalGoldButton(
                icon: Icons.picture_as_pdf_outlined,
                label: 'Open Downloaded PDF',
                onPressed: () {
                  Navigator.pop(ctx);
                  DeviceBridge.openSavedUri(saved.uri);
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  DeviceBridge.shareSavedUri(
                    saved.uri,
                    title: '${spec.documentType} · ${spec.documentNumber}',
                  );
                },
                icon: const Icon(Icons.share_outlined, size: 17),
                label: const Text('Share PDF (WhatsApp / Email / Drive)'),
              ),
            ],
            if (!kIsWeb && renderedHtml != null && renderedHtml.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  DeviceBridge.printHtmlDocument(
                    html: renderedHtml,
                    jobName: fileName.replaceAll('.pdf', ''),
                  );
                },
                icon: const Icon(Icons.print_outlined, size: 17),
                label: const Text('Print / Save Official HTML Layout as PDF'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
