import { Client } from "@saplingai/sapling-js/client";

const apiKey = '<YOUR_API_KEY>';
const client = new Client(apiKey);

// Replace with the text you want to check. Results are more reliable on longer
// text: at least 300 characters is recommended.
const text = `Phone chargers are essential accessories that have become an integral part of modern life. These devices are designed to replenish the battery life of our smartphones and other electronic gadgets, enabling us to stay connected and productive throughout the day. With advancements in technology, phone chargers have evolved significantly, offering various types such as wired, wireless, fast-charging, and portable chargers.

The convenience and versatility of phone chargers have revolutionized the way we use our devices, ensuring we can always stay powered up and connected in our fast-paced, digital world.`;

client
  .aidetect(text)
  .then(function ({ data }) {
    // score rates the whole text from 0 to 1, and ai_fraction is the share of
    // the text in sentences scoring 0.5 or above.
    console.log('Score:', data.score);
    console.log('AI fraction:', data.ai_fraction);
    // verdict is human, mixed or ai. It is omitted if the text couldn't be scored.
    console.log('Verdict:', data.verdict);
    // low_confidence is true for inputs with a higher false-positive rate, such
    // as short text. Show those results hedged rather than as a bare score.
    console.log('Low confidence:', data.low_confidence);

    data.sentence_scores
      .filter((sentence) => sentence.score >= 0.5)
      .forEach((sentence) => {
        console.log(`Flagged (${sentence.score.toFixed(2)}): ${sentence.sentence}`);
      });
  })
  .catch(function (error) {
    console.error(error.response ? error.response.data : error.message);
  });

// To score a document or a web page instead of a string:
//
// import { readFileSync } from 'node:fs';
// client.fileAidetect(readFileSync('essay.pdf'), { filename: 'essay.pdf' });
// client.urlAidetect('https://example.com/blog/post');
