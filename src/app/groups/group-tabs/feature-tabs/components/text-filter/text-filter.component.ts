import { ChangeDetectionStrategy, Component, model } from '@angular/core'
import { FormsModule } from '@angular/forms'
import { NzButtonModule } from 'ng-zorro-antd/button'
import { NzIconModule } from 'ng-zorro-antd/icon'
import { NzInputModule } from 'ng-zorro-antd/input'
import { NzToolTipModule } from 'ng-zorro-antd/tooltip'

@Component({
  selector: 'gcd-text-filter',
  imports: [FormsModule, NzInputModule, NzIconModule, NzToolTipModule, NzButtonModule],
  templateUrl: './text-filter.component.html',
  styleUrl: './text-filter.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class TextFilterComponent {
  placeholder = model('')
  filterText = model.required<string>()

  clear(): void {
    this.filterText.set('')
  }
}
