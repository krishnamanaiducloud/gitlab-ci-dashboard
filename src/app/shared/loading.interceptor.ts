import { HttpInterceptorFn } from '@angular/common/http'
import { inject } from '@angular/core'
import { finalize } from 'rxjs'

import { LoadingService } from './loading.service'

/**
 * Signals the global loading bar for the duration of every HTTP request.
 * Concurrent requests are counted, so the bar stays visible until all settle.
 */
export const loadingInterceptor: HttpInterceptorFn = (request, next) => {
  const loading = inject(LoadingService)
  loading.begin()
  return next(request).pipe(finalize(() => loading.end()))
}
