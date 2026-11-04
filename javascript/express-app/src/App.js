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
  }, []);

  // Shows an overall score and highlights the sentences flagged as AI-generated
  const checkAI = () => {
    Sapling.checkOnce(document.getElementById('editor'), { aiDetect: true });
  };

  return (
    <>
      <div id="editor" sapling-ignore="true" contentEditable="true">
        Lets get started! Phone chargers are essential accessories that have become an integral part of modern life. These devices are designed to replenish the battery life of our smartphones and other electronic gadgets, enabling us to stay connected and productive throughout the day. With advancements in technology, phone chargers have evolved significantly, offering various types such as wired, wireless, fast-charging, and portable chargers. The convenience and versatility of phone chargers have revolutionized the way we use our devices, ensuring we can always stay powered up and connected in our fast-paced, digital world.
      </div>
      <button onClick={checkAI}>Check AI</button>
    </>
  );
}

export default App;
