import os
from statistics import mean

import requests
from sapling import SaplingClient

api_key = os.environ.get('SAPLING_API_KEY', '<YOUR_API_KEY>')
if api_key == '<YOUR_API_KEY>':
    print('Error: SAPLING_API_KEY environment variable is not set.')
    exit(1)

text = '''PASTE YOUR TEXT HERE'''

# First chunk into manageable sizes.
# The limit is higher for premium users, but smaller chunk sizes when parallelized
# should result in lower latency.
CHUNK_SIZE = 8000
# Use the free chunking API to split the text
# https://sapling.ai/docs/api/chunk/
# There is also a corresponding HTML endpoint
CHUNKING_ENDPOINT = 'https://api.sapling.ai/api/v1/ingest/chunk_text'

response = requests.post(CHUNKING_ENDPOINT, json={
    'key': api_key,
    'text': text,
    'max_length': CHUNK_SIZE,
    'step_size': 10,  # Optional, see docs for explanation
})
response.raise_for_status()
chunks = response.json().get('chunks', [])
if not chunks:
    print('No chunks returned for analysis.')
    exit(0)

# Score each chunk with the AI detection endpoint
client = SaplingClient(api_key=api_key)
scores = [client.aidetect(chunk)['score'] for chunk in chunks]

print('Detection score: %f' % mean(scores))
