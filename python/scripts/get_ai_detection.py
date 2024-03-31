import os
import requests
from statistics import mean

key = os.environ.get('SAPLING_API_KEY', '<PUT YOUR KEY HERE>')
text = '''PASTE YOUR TEXT HERE'''

# First chunk into manageable sizes
# This is higher for premium users but smaller chunk sizes when parallelized
# should result in lower latency
CHUNK_SIZE = 8000
# Use the free chunking API to split the text
# https://sapling.ai/docs/api/chunk/
# There is also a corresponding HTML endpoint
CHUNKING_ENDPOINT = 'https://api.sapling.ai/api/v1/ingest/chunk_text'
AIDETECT_ENDPOINT = 'https://api.sapling.ai/api/v1/aidetect'

try:
    response = requests.post(CHUNKING_ENDPOINT, json={
        'key': key,
        'text': text,
        'max_length': CHUNK_SIZE,
        'step_size': 10  # Optional, see docs for explanation
    })
    result = response.json()
    assert 'chunks' in result
except Exception as e:
    print('Error: ', e)
# print(result)

detection_results = list()
for chunk in result['chunks']:
    # Submit the chunk to the API endpoint
    try:
        response = requests.post(AIDETECT_ENDPOINT, json={
            'key': key,
            'text': chunk,
            'sent_scores': False
        })
        # print(response)
        result = response.json()
        detection_results.append(result)
    except Exception as e:
        print('Error: ', e)

mean_score = mean([result['score'] for result in detection_results])
print('Detection score: %f' % mean_score)
