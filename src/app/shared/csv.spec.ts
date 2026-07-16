import { createCsv, escapeCsvField } from './csv'

describe('CSV utilities', () => {
  it('uses RFC 4180 quoting and CRLF records', () => {
    expect(createCsv(['name', 'description'], [['alpha', 'comma, quote " and\nnewline']])).toBe(
      'name,description\r\nalpha,"comma, quote "" and\nnewline"\r\n'
    )
  })

  it.each(['=1+1', '+cmd', '-2+3', '@SUM(A1:A2)', '  =1+1', '\t=1+1'])(
    'neutralizes spreadsheet formula value %s',
    (value) => expect(escapeCsvField(value).startsWith("'")).toBe(true)
  )

  it('renders nullish fields as empty strings', () => {
    expect(createCsv(['a', 'b'], [[null, undefined]])).toBe('a,b\r\n,\r\n')
  })
})
