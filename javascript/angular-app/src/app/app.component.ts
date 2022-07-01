import { Component, OnInit } from '@angular/core';
import { Sapling } from "@saplingai/sapling-js/observer";

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css']
})

export class AppComponent implements OnInit {
  title = 'angular-app';

  ngOnInit() {
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
