import os

from sapling import SaplingClient

api_key = os.environ.get('SAPLING_API_KEY', '<YOUR_API_KEY>')
if api_key == '<YOUR_API_KEY>':
    print('Error: SAPLING_API_KEY environment variable is not set.')
    exit(1)

client = SaplingClient(api_key=api_key)
edits = client.edits('Lets get started!', session_id='test_session')
print(edits)
