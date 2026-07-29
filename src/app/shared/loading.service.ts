import { computed, Injectable, signal } from '@angular/core'

/**
 * Tracks in-flight HTTP requests so the shell can render a global loading bar
 * whenever any API call is in progress.
 */
@Injectable({ providedIn: 'root' })
export class LoadingService {
  private readonly inFlight = signal(0)

  readonly loading = computed(() => this.inFlight() > 0)

  begin(): void {
    this.inFlight.update((count) => count + 1)
  }

  end(): void {
    this.inFlight.update((count) => Math.max(0, count - 1))
  }
}
