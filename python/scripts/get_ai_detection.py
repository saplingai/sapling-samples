import os
from statistics import mean

import requests
from sapling import SaplingClient

api_key = os.environ.get('SAPLING_API_KEY', '<YOUR_API_KEY>')
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
chunks = response.json()['chunks']

# Score each chunk with the AI detection endpoint
client = SaplingClient(api_key=api_key)
scores = [client.aidetect(chunk)['score'] for chunk in chunks]

print('Detection score: %f' % mean(scores))
