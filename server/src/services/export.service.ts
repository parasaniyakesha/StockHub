import { Response } from 'express';
import ExcelJS from 'exceljs';
import PDFDocument from 'pdfkit';

export type ExportFormat = 'csv' | 'xlsx' | 'pdf';

export interface ExportColumn<T> {
  header: string;
  value: (row: T) => string | number | null | undefined | Date;
  width?: number;
  numeric?: boolean;
}

const formatCell = (v: unknown) => {
  if (v === null || v === undefined) return '';
  if (v instanceof Date) return v.toISOString().replace('T', ' ').slice(0, 19);
  return String(v);
};

function csvEscape(v: string) {
  // Neutralise spreadsheet formula injection (=, +, -, @ at the start of a cell).
  const safe = /^[=+\-@\t\r]/.test(v) && !/^-?\d+(\.\d+)?$/.test(v) ? `'${v}` : v;
  return /[",\n\r]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
}

export async function sendExport<T>(
  res: Response,
  format: ExportFormat,
  fileBase: string,
  title: string,
  columns: ExportColumn<T>[],
  rows: T[],
) {
  const stamp = new Date().toISOString().slice(0, 10);
  const fileName = `${fileBase}-${stamp}.${format}`;
  res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
  res.setHeader('Access-Control-Expose-Headers', 'Content-Disposition');

  if (format === 'csv') {
    const lines = [columns.map((c) => csvEscape(c.header)).join(',')];
    for (const row of rows) lines.push(columns.map((c) => csvEscape(formatCell(c.value(row)))).join(','));
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    // BOM so Excel opens UTF-8 (₹ etc.) correctly.
    res.send('﻿' + lines.join('\r\n'));
    return;
  }

  if (format === 'xlsx') {
    const wb = new ExcelJS.Workbook();
    wb.creator = 'StockHub';
    const ws = wb.addWorksheet(title.slice(0, 31));
    ws.columns = columns.map((c) => ({ header: c.header, width: c.width ?? Math.max(12, c.header.length + 4) }));
    ws.getRow(1).font = { bold: true };
    ws.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFE8EEF9' } };
    ws.views = [{ state: 'frozen', ySplit: 1 }];
    for (const row of rows) {
      ws.addRow(columns.map((c) => {
        const v = c.value(row);
        return c.numeric && v !== null && v !== undefined && v !== '' ? Number(v) : v instanceof Date ? v : formatCell(v);
      }));
    }
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    const buffer = await wb.xlsx.writeBuffer();
    res.send(Buffer.from(buffer));
    return;
  }

  // PDF - simple paginated table, landscape A4.
  const doc = new PDFDocument({ size: 'A4', layout: 'landscape', margin: 32 });
  res.setHeader('Content-Type', 'application/pdf');
  doc.pipe(res);

  const pageWidth = doc.page.width - 64;
  const weights = columns.map((c) => c.width ?? 14);
  const totalWeight = weights.reduce((a, b) => a + b, 0);
  const widths = weights.map((w) => (w / totalWeight) * pageWidth);

  const drawHeader = () => {
    doc.font('Helvetica-Bold').fontSize(14).fillColor('#111827').text(title, 32, 32);
    doc.font('Helvetica').fontSize(8).fillColor('#6B7280').text(`Generated ${formatCell(new Date())} UTC · ${rows.length} rows`, 32, 52);
    let x = 32;
    const y = 72;
    doc.rect(32, y - 4, pageWidth, 18).fill('#E8EEF9');
    doc.font('Helvetica-Bold').fontSize(8).fillColor('#111827');
    columns.forEach((c, i) => {
      doc.text(c.header, x + 3, y, { width: widths[i] - 6, align: c.numeric ? 'right' : 'left', lineBreak: false, ellipsis: true });
      x += widths[i];
    });
    return y + 20;
  };

  let y = drawHeader();
  doc.font('Helvetica').fontSize(8).fillColor('#1F2937');
  rows.forEach((row, index) => {
    if (y > doc.page.height - 48) {
      doc.addPage();
      y = drawHeader();
      doc.font('Helvetica').fontSize(8).fillColor('#1F2937');
    }
    if (index % 2 === 1) {
      doc.rect(32, y - 3, pageWidth, 15).fill('#F9FAFB');
      doc.fillColor('#1F2937');
    }
    let x = 32;
    columns.forEach((c, i) => {
      doc.text(formatCell(c.value(row)), x + 3, y, { width: widths[i] - 6, align: c.numeric ? 'right' : 'left', lineBreak: false, ellipsis: true });
      x += widths[i];
    });
    y += 15;
  });
  doc.end();
}

/** Hard cap on rows exported in one file to protect the server. */
export const EXPORT_LIMIT = 10_000;
