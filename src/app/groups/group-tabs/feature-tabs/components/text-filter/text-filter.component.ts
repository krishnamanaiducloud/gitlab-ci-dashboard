import { Component, Input, Output, EventEmitter, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { NzInputModule } from 'ng-zorro-antd/input';
import { NzIconModule } from 'ng-zorro-antd/icon';
import { NzTooltipModule } from 'ng-zorro-antd/tooltip';

@Component({
  selector: 'gcd-text-filter',
  standalone: true,
  imports: [CommonModule, FormsModule, NzInputModule, NzIconModule, NzTooltipModule],
  templateUrl: './text-filter.component.html',
  styleUrls: ['./text-filter.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class TextFilterComponent {
  @Input() placeholder = '';
  @Input() filterText = '';
  @Output() filterTextChange = new EventEmitter<string>();

  update(value: string): void {
    this.filterText = value;
    this.filterTextChange.emit(value);
  }

  clear(): void {
    this.update('');
  }
}

