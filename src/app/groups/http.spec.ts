import { HttpErrorResponse } from '@angular/common/http'
import { isTransientHttpError, pollWhenActive } from './http'

describe('HTTP retry policy', () => {
  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
  })

  it.each([0, 408, 429, 500, 503])('retries transient HTTP status %s', (status) => {
    expect(isTransientHttpError(new HttpErrorResponse({ status }))).toBe(true)
  })

  it.each([400, 401, 403, 404, 409, 422])('does not retry non-transient HTTP status %s', (status) => {
    expect(isTransientHttpError(new HttpErrorResponse({ status }))).toBe(false)
  })

  it('does not retry non-HTTP failures', () => {
    expect(isTransientHttpError(new Error('invalid input'))).toBe(false)
  })

  it('pauses while hidden and refreshes immediately when visible again', async () => {
    vi.useFakeTimers()
    const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(false)
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(true)
    const ticks: number[] = []
    const subscription = pollWhenActive(1_000).subscribe((tick) => ticks.push(tick))

    await vi.advanceTimersByTimeAsync(1_000)
    expect(ticks).toHaveLength(1)

    hidden.mockReturnValue(true)
    document.dispatchEvent(new Event('visibilitychange'))
    await vi.advanceTimersByTimeAsync(5_000)
    expect(ticks).toHaveLength(1)

    hidden.mockReturnValue(false)
    document.dispatchEvent(new Event('visibilitychange'))
    await vi.advanceTimersByTimeAsync(0)
    expect(ticks).toHaveLength(2)

    subscription.unsubscribe()
  })
})
