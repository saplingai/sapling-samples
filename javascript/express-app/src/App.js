import { useEffect } from 'react';
import { Sapling } from "@saplingai/sapling-js/observer";

function App() {
  useEffect(() => {
    Sapling.init({
      endpointHostname: 'http://127.0.0.1:3000',
      saplingPathPrefix: '/sapling',
      statusBadge: true,
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
