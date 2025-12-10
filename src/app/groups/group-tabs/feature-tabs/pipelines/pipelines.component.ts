import { FETCH_REFRESH_INTERVAL } from '$groups/http'
import { GroupId } from '$groups/model/group'
import { PipelineId } from '$groups/model/pipeline'
import { ProjectId, ProjectPipeline, ProjectPipelines } from '$groups/model/project'
import { filterArrayNotNull, filterProject } from '$groups/util/filter'
import { forkJoinFlatten } from '$groups/util/fork'
import { CommonModule } from '@angular/common'
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, computed, inject, input, signal } from '@angular/core'
import { takeUntilDestroyed } from '@angular/core/rxjs-interop'
import { NzSpinModule } from 'ng-zorro-antd/spin'
import { finalize, interval, switchMap } from 'rxjs'
import { ProjectFilterComponent } from '../components/project-filter/project-filter.component'
import { TopicFilterComponent } from '../components/topic-filter/topic-filter.component'
import { BranchFilterComponent } from './components/branch-filter/branch-filter.component'
import { TextFilterComponent } from '../components/text-filter/text-filter.component'
import { PipelineTableComponent } from './pipeline-table/pipeline-table.component'
import { PipelinesService } from './service/pipelines.service'

const STORAGE_KEY = 'pinned_pipelines'

@Component({
  selector: 'gcd-pipelines',
  imports: [
    CommonModule,
    NzSpinModule,
    ProjectFilterComponent,
    TopicFilterComponent,
    BranchFilterComponent,
    TextFilterComponent,
    PipelineTableComponent
  ],
  templateUrl: './pipelines.component.html',
  styleUrls: ['./pipelines.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class PipelinesComponent implements OnInit {
  private pipelinesService = inject(PipelinesService)
  private destroyRef = inject(DestroyRef)

  groupMap = input.required<Map<GroupId, Set<ProjectId>>>()

  filterTextProject = signal('')
  filterGroup = signal('')
  filterTextBranch = signal('')
  filterTrigger = signal('')
  filterStatus = signal('')
  filterTopics = signal<string[]>([])

  pinnedPipelines = signal<PipelineId[]>(this.getPinnedPipelines())

  projectPipelines = signal<ProjectPipelines[]>([])
  loading = signal(false)

  filteredProjectPipelines = computed(() => {
    return this.projectPipelines()
      .flatMap(({ project, pipelines, group_id }) =>
        pipelines.map(pipeline => ({ project, pipeline, group_id }))
      )
      .filter(({ project }) =>
        project.name.toLowerCase().includes(this.filterTextProject().toLowerCase())
      )
      .filter(({ project }) =>
        project.namespace.name.toLowerCase().includes(this.filterGroup().toLowerCase())
      )
      .filter(({ pipeline }) =>
        pipeline.ref.toLowerCase().includes(this.filterTextBranch().toLowerCase())
      )
      .filter(({ pipeline }) =>
        pipeline.source.toLowerCase().includes(this.filterTrigger().toLowerCase())
      )
      .filter(({ pipeline }) =>
        pipeline.status.toLowerCase().includes(this.filterStatus().toLowerCase())
      )
      .sort((a, b) => this.sortByUpdatedAt(a, b))
      .sort((a, b) => this.sortPinned(a, b, this.pinnedPipelines()))
  })

  projects = computed(() =>
    this.projectPipelines()
      .filter(x => x.pipelines.length > 0)
      .map(x => x.project)
  )

  branches = computed(() =>
    filterArrayNotNull(
      this.projectPipelines().flatMap(({ pipelines }) =>
        pipelines.map(p => p.ref)
      )
    )
  )

  ngOnInit(): void {
    this.loading.set(true)

    forkJoinFlatten(
      this.groupMap(),
      this.pipelinesService.getProjectsWithPipelines.bind(this.pipelinesService)
    )
      .pipe(finalize(() => this.loading.set(false)))
      .subscribe(p => this.projectPipelines.set(p))

    interval(FETCH_REFRESH_INTERVAL)
      .pipe(
        takeUntilDestroyed(this.destroyRef),
        switchMap(() =>
          forkJoinFlatten(
            this.groupMap(),
            this.pipelinesService.getProjectsWithPipelines.bind(this.pipelinesService)
          )
        )
      )
      .subscribe(p => this.projectPipelines.set(p))
  }

  onFilterTopicsChanged(v: string[]) { this.filterTopics.set(v) }
  onFilterTextProjectsChanged(v: string) { this.filterTextProject.set(v) }
  onFilterGroupChanged(v: string) { this.filterGroup.set(v) }
  onFilterTextBranchesChanged(v: string) { this.filterTextBranch.set(v) }
  onFilterTriggerChanged(v: string) { this.filterTrigger.set(v) }
  onFilterStatusChanged(v: string) { this.filterStatus.set(v) }

  onPinnedPipelinesChanged(pinned: PipelineId[]) {
    this.pinnedPipelines.set(pinned)
    this.savePinnedPipelines(pinned)
  }

  exportCsv() {
    const rows = this.filteredProjectPipelines().map(p => ({
      project: p.project.name,
      group: p.project.namespace.name,
      branch: p.pipeline.ref,
      trigger: p.pipeline.source,
      status: p.pipeline.status,
      last_run: p.pipeline.updated_at
    }))

    const csv = [
      'Project,Group,Branch,Trigger,Status,Last Run',
      ...rows.map(r =>
        `${r.project},${r.group},${r.branch},${r.trigger},${r.status},${r.last_run}`
      )
    ].join('\n')

    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)

    const a = document.createElement('a')
    a.href = url
    a.download = 'pipelines.csv'
    a.click()

    URL.revokeObjectURL(url)
  }

  private savePinnedPipelines(v: PipelineId[]) {
    try { sessionStorage.setItem(STORAGE_KEY, JSON.stringify(v)) } catch {}
  }

  private getPinnedPipelines(): PipelineId[] {
    try {
      const item = sessionStorage.getItem(STORAGE_KEY)
      return item ? JSON.parse(item) : []
    } catch {
      return []
    }
  }

  private sortByUpdatedAt(a: ProjectPipeline, b: ProjectPipeline) {
    const aTime = a.pipeline ? new Date(a.pipeline.updated_at).getTime() : 0;
    const bTime = b.pipeline ? new Date(b.pipeline.updated_at).getTime() : 0;
    return bTime - aTime;
  }

  private sortPinned(a: ProjectPipeline, b: ProjectPipeline, pinned: number[]) {
    const aPinned = pinned.includes(Number(a.pipeline?.id))
    const bPinned = pinned.includes(Number(b.pipeline?.id))
    return aPinned === bPinned ? 0 : aPinned ? -1 : 1
  }
}

