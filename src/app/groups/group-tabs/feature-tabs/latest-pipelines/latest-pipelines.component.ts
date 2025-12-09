import { FETCH_REFRESH_INTERVAL } from '$groups/http'
import { GroupId } from '$groups/model/group'
import { ProjectId, ProjectPipeline } from '$groups/model/project'
import { forkJoinFlatten } from '$groups/util/fork'
import { CommonModule } from '@angular/common'
import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  OnInit,
  computed,
  inject,
  input,
  signal
} from '@angular/core'
import { takeUntilDestroyed } from '@angular/core/rxjs-interop'
import { NzSpinModule } from 'ng-zorro-antd/spin'
import { finalize, interval, switchMap } from 'rxjs'
import { JobFilterComponent } from '../components/job-filter/job-filter.component'
import { ProjectFilterComponent } from '../components/project-filter/project-filter.component'
import { TopicFilterComponent } from '../components/topic-filter/topic-filter.component'
import { PipelineStatusTabsComponent } from './pipeline-status-tabs/pipeline-status-tabs.component'
import { LatestPipelineService } from './service/latest-pipeline.service'
import { TextFilterComponent } from '../components/text-filter/text-filter.component'

@Component({
  selector: 'gcd-latest-pipelines',
  standalone: true,
  imports: [
    CommonModule,
    NzSpinModule,
    ProjectFilterComponent,
    TopicFilterComponent,
    JobFilterComponent,
    PipelineStatusTabsComponent,
    TextFilterComponent
  ],
  templateUrl: './latest-pipelines.component.html',
  styleUrls: ['./latest-pipelines.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class LatestPipelinesComponent implements OnInit {
  private latestPipelineService = inject(LatestPipelineService)
  private destroyRef = inject(DestroyRef)

  groupMap = input.required<Map<GroupId, Set<ProjectId>>>()

  // NEW FILTER SIGNALS
  filterProject = signal('')
  filterGroup = signal('')
  filterBranch = signal('')
  filterTrigger = signal('')

  // EXISTING FILTERS
  filterTopics = signal<string[]>([])
  filterJobs = signal<string[]>([])

  projectPipelines = signal<ProjectPipeline[]>([])
  loading = signal(false)

  projects = computed(() =>
    this.projectPipelines()
      .filter(({ pipeline }) => pipeline != null)
      .map(({ project }) => project)
  )

  jobs = computed(() =>
    this.projectPipelines().flatMap(({ failed_jobs }) => failed_jobs ?? [])
  )

  ngOnInit(): void {
    this.loading.set(true)

    forkJoinFlatten(
      this.groupMap(),
      this.latestPipelineService.getProjectsWithLatestPipeline.bind(this.latestPipelineService)
    )
      .pipe(finalize(() => this.loading.set(false)))
      .subscribe((p) => this.projectPipelines.set(p))

    interval(FETCH_REFRESH_INTERVAL)
      .pipe(
        takeUntilDestroyed(this.destroyRef),
        switchMap(() =>
          forkJoinFlatten(
            this.groupMap(),
            this.latestPipelineService.getProjectsWithLatestPipeline.bind(this.latestPipelineService)
          )
        )
      )
      .subscribe((p) => this.projectPipelines.set(p))
  }

  // FILTER HANDLERS
  onFilterProjectChanged(v: string) { this.filterProject.set(v) }
  onFilterGroupChanged(v: string) { this.filterGroup.set(v) }
  onFilterBranchChanged(v: string) { this.filterBranch.set(v) }
  onFilterTriggerChanged(v: string) { this.filterTrigger.set(v) }
  onFilterTopicsChanged(v: string[]) { this.filterTopics.set(v) }
  onFilterJobsChanged(v: string[]) { this.filterJobs.set(v) }

  // EXPORT CSV
  exportCsv() {
    const rows = this.projectPipelines().map(p => ({
      project: p.project.name,
      group: p.project.namespace.name,
      branch: p.project.default_branch,
      trigger: p.pipeline?.source ?? '',
      last_run: p.pipeline?.updated_at ?? ''
    }))

    const csv = [
      'Project,Group,Branch,Trigger,Last Run',
      ...rows.map(r =>
        `${r.project},${r.group},${r.branch},${r.trigger},${r.last_run}`
      )
    ].join('\n')

    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)

    const a = document.createElement('a')
    a.href = url
    a.download = 'latest-pipelines.csv'
    a.click()

    URL.revokeObjectURL(url)
  }
}

