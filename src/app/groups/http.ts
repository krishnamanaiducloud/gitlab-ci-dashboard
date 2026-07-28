import { HttpErrorResponse } from '@angular/common/http'
import {
  NEVER,
  Observable,
  RetryConfig,
  defer,
  distinctUntilChanged,
  fromEvent,
  map,
  merge,
  startWith,
  switchMap,
  throwError,
  timer
} from 'rxjs'
import { GroupId } from './model/group'
import { ProjectId } from './model/project'

export const retryConfig: RetryConfig = {
  count: 3,
  delay: (error, retryCount) =>
    isTransientHttpError(error)
      ? timer(Math.min(500 * 2 ** (retryCount - 1), 4_000))
      : throwError(() => error),
  resetOnSuccess: true
}

export const FETCH_REFRESH_INTERVAL = 2000

export function isTransientHttpError(error: unknown): boolean {
  if (!(error instanceof HttpErrorResponse)) return false

  return error.status === 0 || error.status === 408 || error.status === 429 || error.status >= 500
}

/**
 * Poll only while the page is visible and the browser is online. The first
 * poll follows the normal interval; resuming from hidden/offline refreshes
 * immediately.
 */
export function pollWhenActive(periodMs = FETCH_REFRESH_INTERVAL): Observable<number> {
  return defer(() => {
    let activityInitialized = false
    const activityChanges = merge(
      fromEvent(document, 'visibilitychange'),
      fromEvent(window, 'online'),
      fromEvent(window, 'offline')
    ).pipe(
      startWith(null),
      map(() => !document.hidden && navigator.onLine),
      distinctUntilChanged()
    )

    return activityChanges.pipe(
      switchMap((active) => {
        const dueTime = activityInitialized ? 0 : periodMs
        activityInitialized = true
        return active ? timer(dueTime, periodMs) : NEVER
      })
    )
  })
}

export function createParams(groupId: GroupId, projectIds?: Set<ProjectId>): { [key: string]: string } {
  const params = Object({ group_id: groupId })
  if (projectIds && projectIds.size > 0) {
    return { ...params, project_ids: Array.from(projectIds).join(',') }
  }
  return params
}
