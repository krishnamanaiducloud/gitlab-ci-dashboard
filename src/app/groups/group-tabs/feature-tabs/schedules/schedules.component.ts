import { FETCH_REFRESH_INTERVAL } from '$groups/http'
import { GroupId } from '$groups/model/group'
import { ProjectId } from '$groups/model/project'
import { ScheduleProjectPipeline } from '$groups/model/schedule'
import { Status } from '$groups/model/status'
import { filterFailedJobs, filterProject } from '$groups/util/filter'
import { forkJoinFlatten } from '$groups/util/fork'
import { CommonModule } from '@angular/common'
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, input, signal } from '@angular/core'
import { takeUntilDestroyed } from '@angular/core/rxjs-interop'
import { NzSpinModule } from 'ng-zorro-antd/spin'
import { finalize, interval, switchMap } from 'rxjs'
import { JobFilterComponent } from '../components/job-filter/job-filter.component'
import { ProjectFilterComponent } from '../components/project-filter/project-filter.component'
import { TopicFilterComponent } from '../components/topic-filter/topic-filter.component'
import { TextFilterComponent } from '../components/text-filter/text-filter.component'
import { ScheduleTableComponent } from './schedule-table/schedule-table.component'
import { ScheduleService } from './service/schedule.service'

@Component({
  selector: 'gcd-schedules',
  imports: [
    CommonModule,
    NzSpinModule,
    ScheduleTableComponent,
    ProjectFilterComponent,
    TopicFilterComponent,
    TextFilterComponent,
    JobFilterComponent
  ],
  templateUrl: './schedules.component.html',
  styleUrls: ['./schedules.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class SchedulesComponent implements OnInit {
  private scheduleService = inject(ScheduleService)
  private destroyRef = inject(DestroyRef)

  groupMap = input.required<Map<GroupId, Set<ProjectId>>>()

  filterText = signal('')
  filterGroup = signal('')
  filterBranch = signal('')
  filterTrigger = signal('')
  filterStatus = signal('')
  filterTopics = signal<string[]>([])
  filterJobs = signal<string[]>([])

  schedulePipelines = signal<ScheduleProjectPipeline[]>([])
  loading = signal(false)

  jobs = computed(() =>
    this.schedulePipelines().flatMap(({ failed_jobs }) => failed_jobs ?? [])
  )

  filteredSchedulePipelines = computed(() =>
    this.schedulePipelines()
      .filter(({ project }) =>
        project.name.toLowerCase().includes(this.filterText().toLowerCase())
      )
      .filter(({ project }) =>
        project.namespace.name.toLowerCase().includes(this.filterGroup().toLowerCase())
      )
      .filter(({ pipeline }) =>
        pipeline?.ref.toLowerCase().includes(this.filterBranch().toLowerCase())
      )
      .filter(({ pipeline }) =>
        pipeline?.source.toLowerCase().includes(this.filterTrigger().toLowerCase())
      )
      .filter(({ pipeline }) =>
        pipeline?.status.toLowerCase().includes(this.filterStatus().toLowerCase())
      )
      .filter(({ project }) =>
        filterProject(project, this.filterText(), this.filterTopics())
      )
      .filter(({ failed_jobs }) =>
        filterFailedJobs(failed_jobs ?? [], this.filterJobs())
      )
  )

  projects = computed(() => this.schedulePipelines().map(p => p.project))

  ngOnInit(): void {
    this.loading.set(true)

    forkJoinFlatten(
      this.groupMap(),
      this.scheduleService.getSchedules.bind(this.scheduleService)
    )
      .pipe(finalize(() => this.loading.set(false)))
      .subscribe((result) => this.schedulePipelines.set(result))

    interval(FETCH_REFRESH_INTERVAL)
      .pipe(
        takeUntilDestroyed(this.destroyRef),
        switchMap(() =>
          forkJoinFlatten(
            this.groupMap(),
            this.scheduleService.getSchedules.bind(this.scheduleService)
          )
        )
      )
      .subscribe((result) => this.schedulePipelines.set(result))
  }

  onFilterTopicsChanged(v: string[]) { this.filterTopics.set(v) }
  onFilterTextChanged(v: string) { this.filterText.set(v) }
  onFilterGroupChanged(v: string) { this.filterGroup.set(v) }
  onFilterBranchChanged(v: string) { this.filterBranch.set(v) }
  onFilterTriggerChanged(v: string) { this.filterTrigger.set(v) }
  onFilterStatusChanged(v: string) { this.filterStatus.set(v) }
  onFilterJobsChanged(v: string[]) { this.filterJobs.set(v) }

  exportCsv() {
    const rows = this.filteredSchedulePipelines().map(p => ({
      project: p.project.name,
      group: p.project.namespace.name,
      branch: p.pipeline?.ref ?? '',
      trigger: p.pipeline?.source ?? '',
      status: p.pipeline?.status ?? ''
    }))

    const csv = [
      'Project,Group,Branch,Trigger,Status',
      ...rows.map(r =>
        `${r.project},${r.group},${r.branch},${r.trigger},${r.status}`
      )
    ].join('\n')

    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)

    const a = document.createElement('a')
    a.href = url
    a.download = 'schedules.csv'
    a.click()

    URL.revokeObjectURL(url)
  }
}

