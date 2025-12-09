import { StatusColorPipe } from '$groups/group-tabs/feature-tabs/pipes/status-color.pipe'
import { ProjectPipeline } from '$groups/model/project'
import { Status } from '$groups/model/status'
import { filterFailedJobs, filterProject } from '$groups/util/filter'
import { CommonModule } from '@angular/common'
import { ChangeDetectionStrategy, Component, Signal, computed, input } from '@angular/core'
import { NzBadgeModule } from 'ng-zorro-antd/badge'
import { NzEmptyModule } from 'ng-zorro-antd/empty'
import { NzTabsModule } from 'ng-zorro-antd/tabs'
import { PipelineTableComponent } from './pipeline-table/pipeline-table.component'

interface Tab {
  status: Status
  projects: ProjectPipeline[]
}

@Component({
  selector: 'gcd-pipeline-status-tabs',
  standalone: true,
  imports: [
    CommonModule,
    NzTabsModule,
    NzBadgeModule,
    NzEmptyModule,
    PipelineTableComponent,
    StatusColorPipe
  ],
  templateUrl: './pipeline-status-tabs.component.html',
  styleUrls: ['./pipeline-status-tabs.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class PipelineStatusTabsComponent {

  projectPipelines = input.required<ProjectPipeline[]>()

  // NEW FILTER INPUTS
  filterProject = input.required<string>()
  filterGroup = input.required<string>()
  filterBranch = input.required<string>()
  filterTrigger = input.required<string>()

  // EXISTING REQUIRED INPUTS
  filterTopics = input.required<string[]>()
  filterJobs = input.required<string[]>()
  filterText = input.required<string>()   // keep temporarily for compatibility

  tabs: Signal<Tab[]> = computed(() => {
    return Array.from(
      this.projectPipelines()
        .filter(({ project }) =>
          project.name.toLowerCase().includes(this.filterProject().toLowerCase())
        )
        .filter(({ project }) =>
          project.namespace.name.toLowerCase().includes(this.filterGroup().toLowerCase())
        )
        .filter(({ project }) =>
          project.default_branch.toLowerCase().includes(this.filterBranch().toLowerCase())
        )
        .filter(({ pipeline }) =>
          pipeline?.source?.toLowerCase().includes(this.filterTrigger().toLowerCase())
        )
        .filter(({ project }) =>
          filterProject(project, this.filterText(), this.filterTopics())
        )
        .filter(({ failed_jobs }) =>
          filterFailedJobs(failed_jobs ?? [], this.filterJobs())
        )
        .reduce((map, { group_id, project, pipeline }) => {
          if (!pipeline) return map;
          const entry = map.get(pipeline.status) ?? [];
          map.set(pipeline.status, [...entry, { group_id, project, pipeline }]);
          return map;
        }, new Map<Status, ProjectPipeline[]>())
    )
      .map(([status, projects]) => ({ status, projects }))
      .sort((a, b) => a.status.localeCompare(b.status));
  })

  trackByStatus({ status }: Tab): Status {
    return status
  }
}

