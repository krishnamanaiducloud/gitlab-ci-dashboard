import { normalizeExternalUrl, openExternalUrl } from './external-url'

describe('external URL utilities', () => {
  afterEach(() => vi.restoreAllMocks())

  it('allows only absolute HTTP and HTTPS URLs', () => {
    expect(normalizeExternalUrl('https://gitlab.example.com/group/project')).toBe(
      'https://gitlab.example.com/group/project'
    )
    expect(normalizeExternalUrl('javascript:alert(1)')).toBeNull()
    expect(normalizeExternalUrl('/relative')).toBeNull()
    expect(normalizeExternalUrl('https://user:password@gitlab.example.com')).toBeNull()
  })

  it('opens a safe URL without granting access to window.opener', () => {
    const opened = { opener: window } as unknown as Window
    const spy = vi.spyOn(window, 'open').mockReturnValue(opened)

    expect(openExternalUrl('https://gitlab.example.com')).toBe(true)
    expect(spy).toHaveBeenCalledWith('https://gitlab.example.com/', '_blank', 'noopener,noreferrer')
    expect(opened.opener).toBeNull()
  })

  it('does not open an unsafe URL', () => {
    const spy = vi.spyOn(window, 'open')
    expect(openExternalUrl('data:text/html,unsafe')).toBe(false)
    expect(spy).not.toHaveBeenCalled()
  })
})
