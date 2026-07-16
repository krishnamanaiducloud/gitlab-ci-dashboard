import { HttpInterceptorFn } from '@angular/common/http'

/**
 * Keep API requests relative to the document base URL. This allows the same
 * frontend bundle to run at either `/` or an OpenShift/Istio prefix such as
 * `/gitlab-ci-dashboard/` without rebuilding the image.
 */
export const apiBaseInterceptor: HttpInterceptorFn = (request, next) => {
  if (request.url === '/api' || request.url.startsWith('/api/')) {
    return next(request.clone({ url: request.url.slice(1) }))
  }

  return next(request)
}
