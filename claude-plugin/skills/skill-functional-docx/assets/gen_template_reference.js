const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  ImageRun, Header, Footer, AlignmentType, HeadingLevel, BorderStyle,
  WidthType, ShadingType, VerticalAlign, PageNumber, PageBreak,
  LevelFormat, TableOfContents, ExternalHyperlink, PageOrientation,
  Tab, TabStopType, TabStopPosition
} = require('docx');
const fs = require('fs');
const path = require('path');

// DSC palette (from Orthoservice doc)
const BLUE_H1        = '365F91';
const BLUE_H2        = '4F81BD';
const BLUE_H3        = '95B3D7'; // lighter
const TABLE_DARK_ROW = 'A7BFDE'; // odd rows (Supervisore, Data)
const TABLE_LITE_ROW = 'D3DFEE'; // even rows (Autore, Versione, Note)
const TABLE_COL1_W   = 2957;
const TABLE_COL2_W   = 6436;
const TABLE_TOTAL_W  = TABLE_COL1_W + TABLE_COL2_W;

// Page settings (from Orthoservice)
const PAGE_W   = 11906;
const PAGE_H   = 16838;
const MAR_TOP  = 567;
const MAR_R    = 992;
const MAR_B    = 1418;
const MAR_L    = 1418;
const CONTENT_W = PAGE_W - MAR_L - MAR_R; // 9496

// Logo dimensions (from original EMU)
const LOGO_CX = 1195214;
const LOGO_CY = 409575;

const logoData = fs.readFileSync('/home/claude/dsc_logo.png');

// ── Helper: bold label run ──────────────────────────────────────────────────
function labelRun(text) {
  return new TextRun({ text, bold: true, font: 'Verdana', size: 20 });
}
function valueRun(text) {
  return new TextRun({ text, font: 'Verdana', size: 20 });
}
function placeholderRun(text) {
  return new TextRun({ text, font: 'Verdana', size: 20, color: '999999', italics: true });
}

// ── Cover table ─────────────────────────────────────────────────────────────
function coverRow(label, valueText, isPlaceholder, darkRow) {
  const fill = darkRow ? TABLE_DARK_ROW : TABLE_LITE_ROW;
  const border = { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' };
  const borders = { top: border, bottom: border, left: border, right: border };
  const cellMargins = { top: 80, bottom: 80, left: 120, right: 120 };

  return new TableRow({
    children: [
      new TableCell({
        borders,
        width: { size: TABLE_COL1_W, type: WidthType.DXA },
        shading: { fill, type: ShadingType.CLEAR },
        margins: cellMargins,
        children: [new Paragraph({ children: [labelRun(label)] })]
      }),
      new TableCell({
        borders,
        width: { size: TABLE_COL2_W, type: WidthType.DXA },
        shading: { fill, type: ShadingType.CLEAR },
        margins: cellMargins,
        children: [new Paragraph({
          children: [isPlaceholder ? placeholderRun(valueText) : valueRun(valueText)]
        })]
      })
    ]
  });
}

function noteRow(darkRow) {
  const fill = darkRow ? TABLE_DARK_ROW : TABLE_LITE_ROW;
  const border = { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' };
  const borders = { top: border, bottom: border, left: border, right: border };
  const cellMargins = { top: 80, bottom: 80, left: 120, right: 120 };
  return new TableRow({
    children: [
      new TableCell({
        borders,
        width: { size: TABLE_COL1_W, type: WidthType.DXA },
        shading: { fill, type: ShadingType.CLEAR },
        margins: cellMargins,
        children: [new Paragraph({ children: [labelRun('Note e commenti:')] })]
      }),
      new TableCell({
        borders,
        width: { size: TABLE_COL2_W, type: WidthType.DXA },
        shading: { fill, type: ShadingType.CLEAR },
        margins: cellMargins,
        // Tall cell with empty lines
        children: [
          new Paragraph({ children: [placeholderRun('')] }),
          new Paragraph({ children: [] }),
          new Paragraph({ children: [] }),
          new Paragraph({ children: [] }),
        ]
      })
    ]
  });
}

// ── Header: logo + title + page ─────────────────────────────────────────────
function makeHeader(clientName, docTitle) {
  return new Header({
    children: [
      // Row 1: logo left
      new Paragraph({
        alignment: AlignmentType.LEFT,
        spacing: { before: 0, after: 60 },
        children: [
          new ImageRun({
            data: logoData,
            transformation: { width: Math.round(LOGO_CX / 9144), height: Math.round(LOGO_CY / 9144) },
            type: 'png'
          })
        ]
      }),
      // Row 2: "Cliente – Titolo     pag. X/Y" — centered
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { before: 0, after: 60 },
        children: [
          new TextRun({ text: `${clientName} \u2013 ${docTitle}`, bold: true, font: 'Verdana', size: 18 }),
          new TextRun({ text: '      ', font: 'Verdana', size: 18 }),
          new TextRun({ text: 'pag. ', italics: true, font: 'Verdana', size: 18 }),
          new TextRun({
            children: [PageNumber.CURRENT],
            italics: true, font: 'Verdana', size: 18
          }),
          new TextRun({ text: '/', italics: true, font: 'Verdana', size: 18 }),
          new TextRun({
            children: [PageNumber.TOTAL_PAGES],
            italics: true, font: 'Verdana', size: 18
          }),
        ]
      }),
    ]
  });
}

// ── Footer ───────────────────────────────────────────────────────────────────
function makeFooter() {
  const sep = { style: BorderStyle.SINGLE, size: 6, color: '000000', space: 1 };
  return new Footer({
    children: [
      new Paragraph({
        border: { top: sep },
        alignment: AlignmentType.CENTER,
        spacing: { before: 120, after: 40 },
        children: [new TextRun({ text: 'DSC Group Srl', bold: true, font: 'Verdana', size: 18 })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { before: 0, after: 0 },
        children: [new TextRun({
          text: 'Sede legale: Via N.Bixio, 2 21052 Busto Arsizio (VA) - Sede operativa: Via del Gregge, 100 21015 Lonate Pozzolo (VA)',
          font: 'Verdana', size: 14
        })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { before: 0, after: 0 },
        children: [new TextRun({ text: 'Tel: +39 0331 726304 \u2013 Fax: +39 0331 728285', font: 'Verdana', size: 14 })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { before: 0, after: 0 },
        children: [
          new TextRun({ text: 'P.I./C.F.: 02319800021  ', font: 'Verdana', size: 14 }),
          new ExternalHyperlink({
            link: 'http://www.dsc-group.net/',
            children: [new TextRun({ text: 'http://www.dsc-group.net/', font: 'Verdana', size: 14, style: 'Hyperlink' })]
          }),
          new TextRun({ text: ' \u2013 email: ', font: 'Verdana', size: 14 }),
          new ExternalHyperlink({
            link: 'mailto:amministrazione@dsc-group.net',
            children: [new TextRun({ text: 'amministrazione@dsc-group.net', font: 'Verdana', size: 14, style: 'Hyperlink' })]
          }),
        ]
      }),
    ]
  });
}

// ── Heading helpers ──────────────────────────────────────────────────────────
function h1(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    children: [new TextRun({ text, bold: true, font: 'Verdana', size: 22, color: BLUE_H1 })],
    spacing: { before: 600, after: 80 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: BLUE_H1, space: 1 } }
  });
}
function h2(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    children: [new TextRun({ text, font: 'Verdana', size: 22, color: BLUE_H1 })],
    spacing: { before: 200, after: 80 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: BLUE_H2, space: 1 } }
  });
}
function h3(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_3,
    children: [new TextRun({ text, font: 'Verdana', size: 24, color: BLUE_H2 })],
    spacing: { before: 200, after: 80 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: BLUE_H3, space: 1 } }
  });
}
function body(text, indent) {
  return new Paragraph({
    indent: indent ? { left: 357 } : undefined,
    spacing: { line: 360, lineRule: 'auto', before: 0, after: 160 },
    children: [new TextRun({ text, font: 'Verdana', size: 22 })]
  });
}
function emptyPara() {
  return new Paragraph({ children: [new TextRun({ text: '', font: 'Verdana', size: 22 })] });
}

// ── Cover box title text paragraphs ─────────────────────────────────────────
// In the original doc this is a floating textbox — we reproduce it as inline
// large bold centered paragraphs, which is how it visually reads
function coverTitle(text) {
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 600, after: 200 },
    children: [new TextRun({ text, bold: true, font: 'Verdana', size: 52 })]
  });
}
function coverSubtitle(text) {
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 0, after: 600 },
    children: [new TextRun({ text, bold: true, font: 'Verdana', size: 52 })]
  });
}

// ── Placeholder field table (for actual content pages) ───────────────────────
function placeholderFieldTable(label, hint) {
  const border = { style: BorderStyle.SINGLE, size: 4, color: BLUE_H2 };
  const borders = { top: border, bottom: border, left: border, right: border };
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA },
    columnWidths: [TABLE_COL1_W, TABLE_COL2_W],
    rows: [
      new TableRow({
        children: [
          new TableCell({
            borders,
            width: { size: TABLE_COL1_W, type: WidthType.DXA },
            shading: { fill: TABLE_DARK_ROW, type: ShadingType.CLEAR },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [labelRun(label)] })]
          }),
          new TableCell({
            borders,
            width: { size: TABLE_COL2_W, type: WidthType.DXA },
            margins: { top: 80, bottom: 80, left: 120, right: 120 },
            children: [new Paragraph({ children: [placeholderRun(hint)] })]
          })
        ]
      })
    ]
  });
}

// ── Main document ─────────────────────────────────────────────────────────────
const CLIENT_PH    = '[NOME CLIENTE]';
const PROGETTO_PH  = '[NOME PROGETTO / TITOLO DOCUMENTO]';
const AUTORE_PH    = '[Nome Cognome]';
const SUPERV_PH    = '[Nome Cognome]';
const VERS_PH      = '1.0';
const DATA_PH      = '[GG/MM/AA]';

const header = makeHeader(CLIENT_PH, PROGETTO_PH);
const footer = makeFooter();

const doc = new Document({
  styles: {
    default: {
      document: { run: { font: 'Verdana', size: 22 } }
    },
    paragraphStyles: [
      {
        id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 22, bold: true, font: 'Verdana', color: BLUE_H1 },
        paragraph: {
          spacing: { before: 600, after: 80 },
          outlineLevel: 0,
          border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: BLUE_H1, space: 1 } }
        }
      },
      {
        id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 22, font: 'Verdana', color: BLUE_H1 },
        paragraph: {
          spacing: { before: 200, after: 80 },
          outlineLevel: 1,
          border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: BLUE_H2, space: 1 } }
        }
      },
      {
        id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 24, font: 'Verdana', color: BLUE_H2 },
        paragraph: {
          spacing: { before: 200, after: 80 },
          outlineLevel: 2,
          border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: BLUE_H3, space: 1 } }
        }
      },
    ]
  },
  numbering: {
    config: [
      {
        reference: 'bullets',
        levels: [{
          level: 0, format: LevelFormat.BULLET, text: '\u2022', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } }
        }]
      },
      {
        reference: 'numbered',
        levels: [{
          level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } }
        }]
      },
    ]
  },
  sections: [
    {
      // ── COVER PAGE ──────────────────────────────────────────────────────
      properties: {
        page: {
          size: { width: PAGE_W, height: PAGE_H },
          margin: { top: MAR_TOP, right: MAR_R, bottom: MAR_B, left: MAR_L, header: 340, footer: 0 }
        }
      },
      headers: { default: header },
      footers: { default: footer },
      children: [
        // Cover title box (simulated as large bold text)
        coverTitle(CLIENT_PH),
        emptyPara(),
        coverSubtitle(PROGETTO_PH),
        emptyPara(),

        // Metadata table
        new Table({
          width: { size: TABLE_TOTAL_W, type: WidthType.DXA },
          columnWidths: [TABLE_COL1_W, TABLE_COL2_W],
          rows: [
            coverRow('Autore:', AUTORE_PH, true, false),
            coverRow('Supervisore progetto:', SUPERV_PH, true, true),
            coverRow('Versione:', VERS_PH, false, false),
            coverRow('Data:', DATA_PH, true, true),
            noteRow(false),
          ]
        }),

        emptyPara(),
        emptyPara(),

        // ── SOMMARIO ──────────────────────────────────────────────────────
        new Paragraph({
          heading: HeadingLevel.HEADING_1,
          children: [new TextRun({ text: 'Sommario', bold: true, font: 'Verdana', size: 22, color: BLUE_H1 })],
          spacing: { before: 600, after: 80 },
          border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: BLUE_H1, space: 1 } }
        }),

        new TableOfContents('Sommario', {
          hyperlink: true,
          headingStyleRange: '1-9',
        }),

        new Paragraph({ children: [new PageBreak()] }),

        // ── SEZIONE 1 — PLACEHOLDER ────────────────────────────────────────
        h1('1   [Titolo sezione 1]'),
        body('[Testo introduttivo della sezione. Descrivere il contesto, la premessa o il processo in esame.]', true),

        h2('1.1   [Titolo sottosezione]'),
        body('[Descrizione dettagliata. Usare grassetto per nomi di campi BC e azioni: es. il campo **Codice Articolo** oppure l\'azione **Registra**.', true),

        h3('1.1.1   [Titolo sotto-sottosezione]'),
        body('[Testo. Strutturare in elenchi numerati per le procedure, elenchi puntati per gli elenchi di elementi.]', true),

        emptyPara(),

        // Example fields table
        new Paragraph({
          spacing: { before: 0, after: 120 },
          children: [new TextRun({ text: 'Campi previsti:', font: 'Verdana', size: 22 })]
        }),
        new Table({
          width: { size: CONTENT_W, type: WidthType.DXA },
          columnWidths: [TABLE_COL1_W, TABLE_COL2_W],
          rows: [
            new TableRow({
              children: [
                new TableCell({
                  width: { size: TABLE_COL1_W, type: WidthType.DXA },
                  shading: { fill: TABLE_DARK_ROW, type: ShadingType.CLEAR },
                  margins: { top: 80, bottom: 80, left: 120, right: 120 },
                  borders: {
                    top: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    bottom: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    left: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    right: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                  },
                  children: [new Paragraph({ children: [new TextRun({ text: 'Campo', font: 'Verdana', size: 20, color: 'FFFFFF', bold: true })] })]
                }),
                new TableCell({
                  width: { size: TABLE_COL2_W, type: WidthType.DXA },
                  shading: { fill: TABLE_DARK_ROW, type: ShadingType.CLEAR },
                  margins: { top: 80, bottom: 80, left: 120, right: 120 },
                  borders: {
                    top: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    bottom: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    left: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    right: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                  },
                  children: [new Paragraph({ children: [new TextRun({ text: 'Descrizione / Note', font: 'Verdana', size: 20, color: 'FFFFFF', bold: true })] })]
                }),
              ]
            }),
            new TableRow({
              children: [
                new TableCell({
                  width: { size: TABLE_COL1_W, type: WidthType.DXA },
                  shading: { fill: TABLE_LITE_ROW, type: ShadingType.CLEAR },
                  margins: { top: 80, bottom: 80, left: 120, right: 120 },
                  borders: {
                    top: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    bottom: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    left: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    right: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                  },
                  children: [new Paragraph({ children: [labelRun('[Nome campo BC]')] })]
                }),
                new TableCell({
                  width: { size: TABLE_COL2_W, type: WidthType.DXA },
                  margins: { top: 80, bottom: 80, left: 120, right: 120 },
                  borders: {
                    top: { style: BorderStyle.SINGLE, size: 1, color: 'DDDDDD' },
                    bottom: { style: BorderStyle.SINGLE, size: 1, color: 'DDDDDD' },
                    left: { style: BorderStyle.SINGLE, size: 1, color: 'DDDDDD' },
                    right: { style: BorderStyle.SINGLE, size: 1, color: 'DDDDDD' },
                  },
                  children: [new Paragraph({ children: [placeholderRun('[Descrizione funzionale del campo]')] })]
                }),
              ]
            }),
          ]
        }),

        emptyPara(),

        // ── SEZIONE 2 — PLACEHOLDER ────────────────────────────────────────
        h1('2   [Titolo sezione 2]'),
        body('[Corpo della sezione 2.]', true),

        emptyPara(),

        // ── STIMA ATTIVITÀ ─────────────────────────────────────────────────
        h1('N   Stima Attività'),
        body('[Il presente capitolo sintetizza le stime economiche e le tempistiche indicative di realizzazione, calcolate a partire dalla data di accettazione dell\'offerta.]', true),

        emptyPara(),

        new Table({
          width: { size: CONTENT_W, type: WidthType.DXA },
          columnWidths: [1000, 3000, 2000, 1500, 1996],
          rows: [
            new TableRow({
              children: ['Rif.', 'Voce', 'Tipo', 'Costo', 'Tempo di delivery'].map((h, i) => {
                const widths = [1000, 3000, 2000, 1500, 1996];
                return new TableCell({
                  width: { size: widths[i], type: WidthType.DXA },
                  shading: { fill: BLUE_H2, type: ShadingType.CLEAR },
                  margins: { top: 80, bottom: 80, left: 120, right: 120 },
                  borders: {
                    top: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    bottom: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    left: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    right: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                  },
                  children: [new Paragraph({ children: [new TextRun({ text: h, bold: true, font: 'Verdana', size: 20, color: 'FFFFFF' })] })]
                });
              })
            }),
            new TableRow({
              children: ['A', '[Voce 1]', '[Tipo]', '[€ 0.000]', '[N Settimane]'].map((t, i) => {
                const widths = [1000, 3000, 2000, 1500, 1996];
                return new TableCell({
                  width: { size: widths[i], type: WidthType.DXA },
                  shading: { fill: TABLE_LITE_ROW, type: ShadingType.CLEAR },
                  margins: { top: 80, bottom: 80, left: 120, right: 120 },
                  borders: {
                    top: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    bottom: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    left: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                    right: { style: BorderStyle.SINGLE, size: 1, color: 'FFFFFF' },
                  },
                  children: [new Paragraph({ children: [placeholderRun(t)] })]
                });
              })
            }),
          ]
        }),

      ]
    }
  ]
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync('/home/claude/DSC_Template_DAF.docx', buf);
  console.log('Written:', buf.length, 'bytes');
});
