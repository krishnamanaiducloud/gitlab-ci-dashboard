const dateMatcher = /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/

export function compareNumber(a: number = 0, b: number = 0): number {
  return a - b
}

export function compareString(a: string | null | undefined = '', b: string | null | undefined = ''): number {
  return (a ?? '').localeCompare(b ?? '')
}

export function compareStringDate(a: string | null | undefined = '', b: string | null | undefined = ''): number {
  const sa = a ?? ''
  const sb = b ?? ''
  const isDateString = dateMatcher.test(sa) && dateMatcher.test(sb)
  return isDateString ? Number(new Date(sa)) - Number(new Date(sb)) : 0
}