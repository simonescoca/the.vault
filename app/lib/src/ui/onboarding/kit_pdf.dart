// The printable emergency kit (A4 PDF).
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../l10n/gen/app_localizations.dart';

Future<Uint8List> buildKitPdf({
  required AppLocalizations l,
  required String code,
  required String email,
  required String server,
  required DateTime date,
}) async {
  final sans = pw.Font.ttf(await rootBundle.load('assets/fonts/Geist-400.ttf'));
  final sansBold = pw.Font.ttf(await rootBundle.load('assets/fonts/Geist-600.ttf'));
  final mono = pw.Font.ttf(await rootBundle.load('assets/fonts/GeistMono-500.ttf'));
  final doc = pw.Document(title: l.kitPdfTitle, author: 'The Vault');
  final grey = PdfColor.fromHex('#707070');
  pw.Widget row(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(children: [
          pw.SizedBox(width: 110, child: pw.Text(k, style: pw.TextStyle(font: sans, fontSize: 10, color: grey))),
          pw.Expanded(child: pw.Text(v, style: pw.TextStyle(font: mono, fontSize: 10))),
        ]),
      );
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(56, 64, 56, 56),
    build: (context) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(l.kitPdfTitle, style: pw.TextStyle(font: sansBold, fontSize: 22)),
        pw.SizedBox(height: 28),
        row(l.kitPdfAccount, email),
        row(l.kitPdfServer, server),
        row(l.kitPdfDate, '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'),
        pw.SizedBox(height: 28),
        pw.Text(l.kitPdfCode, style: pw.TextStyle(font: sans, fontSize: 10, color: grey)),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColor.fromHex('#111111'), width: 1.2),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Text(code, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 20, letterSpacing: 1.5)),
        ),
        pw.SizedBox(height: 24),
        pw.Text(l.kitSubtitle, style: pw.TextStyle(font: sans, fontSize: 10.5, lineSpacing: 3)),
        pw.SizedBox(height: 12),
        pw.Text(l.kitPdfHowTo, style: pw.TextStyle(font: sans, fontSize: 10.5, lineSpacing: 3)),
        pw.SizedBox(height: 12),
        pw.Text(l.kitPdfWarning, style: pw.TextStyle(font: sansBold, fontSize: 10.5, lineSpacing: 3)),
      ],
    ),
  ));
  return doc.save();
}
