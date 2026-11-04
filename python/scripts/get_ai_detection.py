import os

from sapling import SaplingClient

api_key = os.environ.get('SAPLING_API_KEY', '<YOUR_API_KEY>')
if api_key == '<YOUR_API_KEY>':
    print('Error: SAPLING_API_KEY environment variable is not set.')
    exit(1)

# Replace with the text you want to check. Results are more reliable on longer
# text: at least 300 characters is recommended.
text = '''Phone chargers are essential accessories that have become an integral part of modern life. These devices are designed to replenish the battery life of our smartphones and other electronic gadgets, enabling us to stay connected and productive throughout the day. With advancements in technology, phone chargers have evolved significantly, offering various types such as wired, wireless, fast-charging, and portable chargers.

The convenience and versatility of phone chargers have revolutionized the way we use our devices, ensuring we can always stay powered up and connected in our fast-paced, digital world.'''

client = SaplingClient(api_key=api_key)

# A single request can score up to 200,000 characters, but smaller chunks
# should result in lower latency when parallelized. Use the free chunking API to
# split the text: https://sapling.ai/docs/api/chunk/
CHUNK_SIZE = 8000
chunks = client.chunk_text(text, max_length=CHUNK_SIZE, step_size=10)['chunks']
if not chunks:
    print('No chunks returned for analysis.')
    exit(0)

# Score each chunk with the AI detection endpoint
results = [client.aidetect(chunk) for chunk in chunks]

for index, result in enumerate(results, start=1):
    print('Chunk %d of %d' % (index, len(results)))
    # verdict is human, mixed or ai. It is omitted if the text couldn't be scored.
    print('  Verdict: %s' % result.get('verdict'))
    # low_confidence is true for inputs with a higher false-positive rate,
    # such as short text. Show those results hedged rather than as a bare score.
    print('  Low confidence: %s' % result.get('low_confidence'))
    for sentence in result.get('sentence_scores', []):
        if sentence['score'] >= 0.5:
            print('  Flagged (%.2f): %s' % (sentence['score'], sentence['sentence']))

# Combine the chunks, weighting each one by its length
total_length = sum(len(chunk) for chunk in chunks)
score = sum(
    result['score'] * len(chunk) for chunk, result in zip(chunks, results)
) / total_length
# ai_fraction is null when nothing in a chunk could be scored
ai_fraction = sum(
    (result.get('ai_fraction') or 0) * len(chunk) for chunk, result in zip(chunks, results)
) / total_length

print('Detection score: %f' % score)
print('AI fraction: %f' % ai_fraction)
