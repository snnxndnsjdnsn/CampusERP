import type { CellDef, RowInput, Styles, UserOptions } from 'jspdf-autotable';
import {
  MUTED_FILL,
  WEEKDAYS,
  type CalendarExport,
  type ExportDay,
  type ExportGrid,
  type ExportTermTable,
} from './calendar-export';

/** Module 3 · the Word and the PDF rendering of the calendar export model.
 *
 * Both builders import their library lazily (`await import(...)`), so the
 * roughly a megabyte of `docx` and `jspdf` is fetched only when a button is
 * pressed and never lands in the calendar page's first bundle.
 *
 * The layout mirrors the printed grid: landscape pages, the eleven columns of
 * the on-screen table, every day cell shaded with its category colour, the
 * totals row along the bottom and the legend under the header.
 */

/* ------------------------------------------------------------ measurements */

/** Word works in twips (twentieths of a point): 1440 to the inch. */
const MARGIN = 720; // 0.5"
const PAGE_WIDTH = 16838; // A4 landscape: 297mm
const PAGE_HEIGHT = 11906; // A4 landscape: 210mm
const CONTENT_WIDTH = PAGE_WIDTH - 2 * MARGIN; // 15398

const WEEK_NO_WIDTH = 780;
const MONTH_WIDTH = 1180;
const DAY_WIDTH = 1030;
const WORKING_WIDTH = 980;
const EVENTS_WIDTH =
  CONTENT_WIDTH - (WEEK_NO_WIDTH + MONTH_WIDTH + WEEKDAYS.length * DAY_WIDTH + WORKING_WIDTH);

const GRID_COLUMNS: { label: string; width: number }[] = [
  { label: 'Week No.', width: WEEK_NO_WIDTH },
  { label: 'Month', width: MONTH_WIDTH },
  ...WEEKDAYS.map((d) => ({ label: d, width: DAY_WIDTH })),
  { label: 'No of Working days', width: WORKING_WIDTH },
  { label: 'Events', width: EVENTS_WIDTH },
];

const TERM_WIDTHS = [3000, 3100, 3100, 3100, CONTENT_WIDTH - 12300];
const TERM_COLUMNS: { label: string; width: number }[] = [
  { label: 'Courses', width: TERM_WIDTHS[0] ?? 3000 },
  { label: 'Term Commencement', width: TERM_WIDTHS[1] ?? 3100 },
  { label: 'End of term', width: TERM_WIDTHS[2] ?? 3100 },
  { label: 'Practical Exams', width: TERM_WIDTHS[3] ?? 3100 },
  { label: 'Theory Exams', width: TERM_WIDTHS[4] ?? 3100 },
];

/** Word's shading carries no text colour, and these are light `*-100` fills. */
function docxFill(hex: string | null): string | undefined {
  return hex ? hex.slice(1) : undefined;
}

/** The same colour as an `[r, g, b]` triple, which is how jsPDF paints. */
function rgb(hex: string): [number, number, number] {
  return [
    Number.parseInt(hex.slice(1, 3), 16),
    Number.parseInt(hex.slice(3, 5), 16),
    Number.parseInt(hex.slice(5, 7), 16),
  ];
}

/* -------------------------------------------------------------------- Word */

/** Build the landscape `.docx`: the grids, the term schedules and the legend. */
export async function wordBlob(model: CalendarExport): Promise<Blob> {
  const {
    AlignmentType,
    BorderStyle,
    Document,
    Packer,
    PageOrientation,
    Paragraph,
    ShadingType,
    Table,
    TableCell,
    TableLayoutType,
    TableRow,
    TextRun,
    VerticalAlignTable,
    WidthType,
  } = await import('docx');

  const hairline = { style: BorderStyle.SINGLE, size: 4, color: 'BFBFBF' };
  const borders = {
    top: hairline,
    bottom: hairline,
    left: hairline,
    right: hairline,
    insideHorizontal: hairline,
    insideVertical: hairline,
  };

  function para(
    text: string,
    opts: { bold?: boolean; center?: boolean; size?: number; color?: string } = {},
  ) {
    return new Paragraph({
      alignment: opts.center ? AlignmentType.CENTER : AlignmentType.LEFT,
      spacing: { before: 10, after: 10 },
      children: [
        new TextRun({
          text,
          bold: opts.bold ?? false,
          size: opts.size ?? 16,
          ...(opts.color ? { color: opts.color } : {}),
        }),
      ],
    });
  }

  /** One bordered cell: optional width, span and shading around a paragraph. */
  function shaded(
    text: string,
    opts: {
      fill?: string | null;
      width?: number;
      columnSpan?: number;
      bold?: boolean;
      center?: boolean;
      size?: number;
      color?: string;
    } = {},
  ) {
    const fill = docxFill(opts.fill ?? null);
    return new TableCell({
      ...(opts.width !== undefined ? { width: { size: opts.width, type: WidthType.DXA } } : {}),
      ...(opts.columnSpan !== undefined ? { columnSpan: opts.columnSpan } : {}),
      verticalAlign: VerticalAlignTable.CENTER,
      ...(fill ? { shading: { type: ShadingType.CLEAR, color: 'auto', fill } } : {}),
      children: [para(text, opts)],
    });
  }

  const headerRow = (columns: { label: string; width: number }[]) =>
    new TableRow({
      tableHeader: true,
      children: columns.map((column) =>
        shaded(column.label, { width: column.width, bold: true, center: true, fill: '#E5E7EB' }),
      ),
    });

  function dayCell(cell: ExportDay | null) {
    if (!cell) {
      // The printed grid shows an em dash in a muted cell.
      return shaded('—', { width: DAY_WIDTH, center: true, fill: MUTED_FILL });
    }
    if (!cell.holidayName) {
      return shaded(String(cell.dayNumber), {
        width: DAY_WIDTH,
        center: true,
        bold: true,
        size: 18,
        fill: cell.fill,
      });
    }
    // A holiday cell needs two lines: the day number, then the name.
    const fill = docxFill(cell.fill);
    return new TableCell({
      width: { size: DAY_WIDTH, type: WidthType.DXA },
      verticalAlign: VerticalAlignTable.CENTER,
      ...(fill ? { shading: { type: ShadingType.CLEAR, color: 'auto', fill } } : {}),
      children: [
        para(String(cell.dayNumber), { bold: true, center: true, size: 18 }),
        para(cell.holidayName, { center: true, size: 13 }),
      ],
    });
  }

  function gridTable(grid: ExportGrid) {
    const rows = [
      headerRow(GRID_COLUMNS),
      ...grid.weeks.map(
        (week) =>
          new TableRow({
            children: [
              shaded(String(week.weekNo), { width: WEEK_NO_WIDTH, bold: true, center: true }),
              shaded(week.monthLabel, { width: MONTH_WIDTH, center: true }),
              ...week.cells.map((cell) => dayCell(cell)),
              shaded(String(week.workingDays), { width: WORKING_WIDTH, center: true }),
              // One paragraph per event, like the block lines on the screen.
              new TableCell({
                width: { size: EVENTS_WIDTH, type: WidthType.DXA },
                children: week.events.length
                  ? week.events.map((event) => para(event))
                  : [para('—', { color: '6B7280' })],
              }),
            ],
          }),
      ),
      new TableRow({
        children: [
          shaded('No of working days', {
            width: WEEK_NO_WIDTH + MONTH_WIDTH,
            columnSpan: 2,
            bold: true,
            center: true,
            fill: MUTED_FILL,
          }),
          ...grid.columnTotals.map((total) =>
            shaded(String(total), { width: DAY_WIDTH, bold: true, center: true, fill: MUTED_FILL }),
          ),
          shaded(String(grid.grandTotal), {
            width: WORKING_WIDTH,
            bold: true,
            center: true,
            fill: MUTED_FILL,
          }),
          shaded('', { width: EVENTS_WIDTH, fill: MUTED_FILL }),
        ],
      }),
    ];

    return new Table({
      rows,
      width: { size: CONTENT_WIDTH, type: WidthType.DXA },
      columnWidths: GRID_COLUMNS.map((column) => column.width),
      layout: TableLayoutType.FIXED,
      borders,
    });
  }

  const legendCount = Math.max(model.legend.length, 1);
  const legendCellWidth = Math.floor(CONTENT_WIDTH / legendCount);
  const legendTable = new Table({
    columnWidths: Array.from({ length: legendCount }, () => legendCellWidth),
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    layout: TableLayoutType.FIXED,
    borders,
    rows: [
      new TableRow({
        children: model.legend.map((item) =>
          shaded(item.label, { width: legendCellWidth, center: true, size: 14, fill: item.fill }),
        ),
      }),
    ],
  });

  function termTable(table: ExportTermTable) {
    return new Table({
      width: { size: CONTENT_WIDTH, type: WidthType.DXA },
      columnWidths: TERM_COLUMNS.map((column) => column.width),
      layout: TableLayoutType.FIXED,
      borders,
      rows: [
        headerRow(TERM_COLUMNS),
        ...table.rows.map(
          (row) =>
            new TableRow({
              children: [
                shaded(row.courseLabel, { width: TERM_WIDTHS[0], bold: true }),
                shaded(row.commencement, { width: TERM_WIDTHS[1] ?? 0, center: true }),
                shaded(row.endOfTerm, { width: TERM_WIDTHS[2] ?? 0, center: true }),
                shaded(row.practical, { width: TERM_WIDTHS[3] ?? 0, center: true }),
                shaded(row.theory, { width: TERM_WIDTHS[4] ?? 0, center: true }),
              ],
            }),
        ),
      ],
    });
  }

  const children = [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: model.title, bold: true, size: 32 })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { after: 240 },
      children: [new TextRun({ text: `Generated on ${model.generatedOn}`, size: 14, color: '6B7280' })],
    }),
    para('Legend', { bold: true, size: 18 }),
    legendTable,
    ...model.grids.flatMap((grid) => [
      new Paragraph({
        spacing: { before: 240, after: 60 },
        children: [new TextRun({ text: grid.title, bold: true, size: 24 })],
      }),
      new Paragraph({
        spacing: { after: 120 },
        children: [new TextRun({ text: grid.subtitle, size: 14, color: '6B7280' })],
      }),
      gridTable(grid),
    ]),
    ...model.termTables.flatMap((table) => [
      new Paragraph({
        spacing: { before: 240, after: 120 },
        children: [new TextRun({ text: table.title, bold: true, size: 24 })],
      }),
      termTable(table),
    ]),
  ];

  const doc = new Document({
    title: model.title,
    creator: 'SIMS',
    description: 'The calendar of events, exported from SIMS.',
    sections: [
      {
        properties: {
          page: {
            size: { width: PAGE_WIDTH, height: PAGE_HEIGHT, orientation: PageOrientation.LANDSCAPE },
            margin: { top: MARGIN, right: MARGIN, bottom: MARGIN, left: MARGIN },
          },
        },
        children,
      },
    ],
  });

  return Packer.toBlob(doc);
}

/* -------------------------------------------------------------------- PDF */

/** Build the landscape `.pdf`: the grids, the term schedules and the legend. */
export async function pdfBlob(model: CalendarExport): Promise<Blob> {
  const [{ jsPDF }, { default: autoTable }] = await Promise.all([
    import('jspdf'),
    import('jspdf-autotable'),
  ]);

  const doc = new jsPDF({ orientation: 'landscape', unit: 'pt', format: 'a4' });

  // A4 landscape in points, minus a 36pt margin on every side.
  const left = 36;
  const top = 36;
  const bottom = 36;
  const pageWidth = doc.internal.pageSize.getWidth() - 2 * left;
  const pageHeight = doc.internal.pageSize.getHeight();

  let y = top;

  /** `doc.lastAutoTable.finalY` is where the table just drawn ended. */
  const afterTable = () =>
    (doc as unknown as { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y;

  /** Start a new page when the next block would fall off this one. */
  const ensureRoom = (needed: number) => {
    if (y + needed > pageHeight - bottom) {
      doc.addPage();
      y = top;
    }
  };

  const heading = (text: string) => {
    ensureRoom(40);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(11);
    doc.setTextColor(17, 24, 39);
    doc.text(text, left, y + 12);
    y += 20;
  };

  const subheading = (text: string) => {
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(107, 114, 128);
    const lines: string[] = doc.splitTextToSize(text, pageWidth);
    doc.text(lines, left, y + 8);
    y += lines.length * 10 + 4;
  };

  const lineColor: [number, number, number] = [191, 191, 191];
  const muted = rgb(MUTED_FILL);
  const shared: UserOptions = {
    theme: 'grid',
    margin: { left, right: left, top, bottom },
    styles: {
      fontSize: 7,
      cellPadding: 2.5,
      lineWidth: 0.5,
      lineColor,
      overflow: 'linebreak',
      valign: 'middle',
    },
    headStyles: {
      fillColor: [229, 231, 235],
      textColor: [17, 24, 39],
      fontStyle: 'bold',
      halign: 'center',
    },
  };

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(16);
  doc.setTextColor(17, 24, 39);
  doc.text(model.title, left, y + 16);
  y += 26;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(107, 114, 128);
  doc.text(`Generated on ${model.generatedOn}`, left, y + 6);
  y += 18;

  /* --------------------------------------------------------------- legend */

  const legendWidth = Math.floor(pageWidth / Math.max(model.legend.length, 1));
  const legendStyles: Record<string, Partial<Styles>> = {};
  model.legend.forEach((_, index) => {
    legendStyles[String(index)] = { cellWidth: legendWidth };
  });
  autoTable(doc, {
    ...shared,
    startY: y,
    tableWidth: pageWidth,
    body: [
      model.legend.map((item) => ({
        content: item.label,
        styles: {
          fillColor: item.fill ? rgb(item.fill) : [255, 255, 255],
          halign: 'center' as const,
        },
      })),
    ],
    columnStyles: legendStyles,
  });
  y = afterTable() + 18;

  /* ---------------------------------------------------------------- grids */

  const gridStyles: Record<string, Partial<Styles>> = {
    0: { cellWidth: 30, halign: 'center' },
    1: { cellWidth: 44, halign: 'center' },
    9: { cellWidth: 40, halign: 'center' },
  };
  for (let index = 2; index <= 8; index += 1) {
    gridStyles[String(index)] = { cellWidth: 58, halign: 'center' };
  }

  for (const grid of model.grids) {
    heading(grid.title);
    subheading(grid.subtitle);

    const body: RowInput[] = grid.weeks.map((week) => [
      { content: String(week.weekNo), styles: { halign: 'center' } },
      { content: week.monthLabel, styles: { halign: 'center' } },
      ...week.cells.map((cell): CellDef => {
        if (!cell) {
          return { content: '—', styles: { fillColor: muted, halign: 'center' } };
        }
        return {
          content: cell.holidayName
            ? [String(cell.dayNumber), cell.holidayName]
            : String(cell.dayNumber),
          styles: { ...(cell.fill ? { fillColor: rgb(cell.fill) } : {}), halign: 'center' },
        };
      }),
      { content: String(week.workingDays), styles: { halign: 'center' } },
      { content: week.events.join('\n') || '—' },
    ]);
    body.push([
      {
        content: 'No of working days',
        colSpan: 2,
        styles: { fillColor: muted, fontStyle: 'bold', halign: 'center' },
      },
      ...grid.columnTotals.map((total) => ({
        content: String(total),
        styles: { fillColor: muted, fontStyle: 'bold' as const, halign: 'center' as const },
      })),
      {
        content: String(grid.grandTotal),
        styles: { fillColor: muted, fontStyle: 'bold', halign: 'center' },
      },
      { content: '', styles: { fillColor: muted } },
    ]);

    autoTable(doc, {
      ...shared,
      startY: y,
      tableWidth: pageWidth,
      head: [GRID_COLUMNS.map((column) => column.label)],
      body,
      columnStyles: gridStyles,
    });
    y = afterTable() + 18;
  }

  /* --------------------------------------------------------- term tables */

  for (const table of model.termTables) {
    heading(table.title);
    autoTable(doc, {
      ...shared,
      startY: y,
      tableWidth: pageWidth,
      head: [TERM_COLUMNS.map((column) => column.label)],
      body: table.rows.map((row) => [
        { content: row.courseLabel, styles: { fontStyle: 'bold' as const } },
        { content: row.commencement, styles: { halign: 'center' as const } },
        { content: row.endOfTerm, styles: { halign: 'center' as const } },
        { content: row.practical, styles: { halign: 'center' as const } },
        { content: row.theory, styles: { halign: 'center' as const } },
      ]),
      columnStyles: {
        0: { cellWidth: 150 },
        1: { cellWidth: 157, halign: 'center' },
        2: { cellWidth: 157, halign: 'center' },
        3: { cellWidth: 157, halign: 'center' },
        4: { cellWidth: 157, halign: 'center' },
      },
    });
    y = afterTable() + 18;
  }

  return doc.output('blob');
}
