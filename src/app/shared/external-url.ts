const ALLOWED_PROTOCOLS = new Set(['http:', 'https:'])

export function normalizeExternalUrl(value: string): string | null {
  try {
    const url = new URL(value)
    return ALLOWED_PROTOCOLS.has(url.protocol) && !url.username && !url.password ? url.href : null
  } catch {
    return null
  }
}

export function openExternalUrl(value: string): boolean {
  const safeUrl = normalizeExternalUrl(value)
  if (!safeUrl) return false

  const opened = window.open(safeUrl, '_blank', 'noopener,noreferrer')
  if (opened) opened.opener = null
  return true
}
