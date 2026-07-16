import { provideHttpClient, withInterceptors } from '@angular/common/http'
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing'
import { TestBed } from '@angular/core/testing'
import { HttpClient } from '@angular/common/http'
import { apiBaseInterceptor } from './api-base.interceptor'

describe('apiBaseInterceptor', () => {
  let http: HttpClient
  let controller: HttpTestingController

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(withInterceptors([apiBaseInterceptor])), provideHttpClientTesting()]
    })
    http = TestBed.inject(HttpClient)
    controller = TestBed.inject(HttpTestingController)
  })

  afterEach(() => controller.verify())

  it('makes application API URLs relative to the document base', () => {
    http.get('/api/config').subscribe()
    controller.expectOne('api/config').flush({})
  })

  it('does not change external URLs', () => {
    http.get('https://example.com/data').subscribe()
    controller.expectOne('https://example.com/data').flush({})
  })
})
