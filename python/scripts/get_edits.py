from sapling import SaplingClient

API_KEY = '<YOUR_API_KEY>'
client = SaplingClient(api_key=API_KEY)
edits = client.edits('Lets get started!', session_id='test_session')
print(edits)
