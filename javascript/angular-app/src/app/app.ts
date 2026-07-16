import { AfterViewInit, Component } from '@angular/core';
import { Sapling } from "@saplingai/sapling-js/observer";

@Component({
  selector: 'app-root',
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App implements AfterViewInit {
  title = 'angular-app';

  ngAfterViewInit() {
    Sapling.init({
      key: '<YOUR_API_KEY>',
      endpointHostname: 'https://api.sapling.ai',
      editPathname: '/api/v1/edits',
      statusBadge: true,
      mode: 'dev',
    });

    const editor = document.getElementById('editor');
    if (editor) {
      Sapling.observe(editor);
    }
  }
}
