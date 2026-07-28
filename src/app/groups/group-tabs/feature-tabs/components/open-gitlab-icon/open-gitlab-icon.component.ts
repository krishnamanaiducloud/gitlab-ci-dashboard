import { CommonModule } from '@angular/common'
import { ChangeDetectionStrategy, Component, input } from '@angular/core'
import { NzButtonModule } from 'ng-zorro-antd/button'
import { NzIconModule } from 'ng-zorro-antd/icon'
import { NzTooltipModule } from 'ng-zorro-antd/tooltip'
import { openExternalUrl } from '$shared/external-url'

@Component({
  selector: 'gcd-open-gitlab-icon',
  imports: [CommonModule, NzButtonModule, NzIconModule, NzTooltipModule],
  templateUrl: './open-gitlab-icon.component.html',
  styleUrls: ['./open-gitlab-icon.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class OpenGitlabIconComponent {
  url = input.required<string>()

  onClick(e: MouseEvent) {
    e.stopPropagation()
    openExternalUrl(this.url())
  }
}
