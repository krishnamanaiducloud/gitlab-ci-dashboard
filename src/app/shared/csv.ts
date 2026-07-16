import { downloadBlob } from './download'

export type CsvValue = string | number | boolean | null | undefined

const FORMULA_PREFIX = /^\s*[=+@-]/

/** Escape one field according to RFC 4180 and neutralize spreadsheet formulas. */
export function escapeCsvField(value: CsvValue): string {
  let text = value == null ? '' : String(value)

  if (FORMULA_PREFIX.test(text) || /^[\t\r\n]/.test(text)) {
    text = `'${text}`
  }

  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

export function createCsv(headers: readonly CsvValue[], rows: ReadonlyArray<ReadonlyArray<CsvValue>>): string {
  return [headers, ...rows]
    .map((row) => row.map(escapeCsvField).join(','))
    .join('\r\n') + '\r\n'
}

export function downloadCsv(
  filename: string,
  headers: readonly CsvValue[],
  rows: ReadonlyArray<ReadonlyArray<CsvValue>>
): void {
  downloadBlob(new Blob([createCsv(headers, rows)], { type: 'text/csv;charset=utf-8' }), filename)
}
