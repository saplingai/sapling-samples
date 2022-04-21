import { useEffect } from 'react';
import { Sapling } from "@saplingai/sapling-js/observer";


function App() {
  useEffect(() => {
    Sapling.init({
      key: '<YOUR_API_KEY>',
      endpointHostname: 'https://api.sapling.ai',
      editPathname: '/api/v1/edits',
      statusBadge: true,
      mode: 'dev',
    });

    const editor = document.getElementById('editor');
    Sapling.observe(editor);
  });

  return (
    <div id="editor" sapling-ignore="true" contentEditable="true">
      Lets get started!
    </div>
  );
}

export default App;
