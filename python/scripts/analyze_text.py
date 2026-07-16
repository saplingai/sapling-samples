'''Run several of Sapling's text analysis endpoints over a piece of text.

Requires sapling-py >= 4.1.0 for the rephrase, tone, sentiment and
langdetect client methods.
'''
import json
import os

from sapling import SaplingClient

api_key = os.environ.get('SAPLING_API_KEY', '<YOUR_API_KEY>')
client = SaplingClient(api_key=api_key)

text = 'hey, any updates on the contract? we should finalize by friday.'

print('Rephrase (informal to formal):')
print(json.dumps(client.rephrase(text, mapping='informal_to_formal'), indent=2))

print('Tone:')
print(json.dumps(client.tone(text), indent=2))

print('Sentiment:')
print(json.dumps(client.sentiment(text), indent=2))

print('Language detection:')
print(json.dumps(client.langdetect(text), indent=2))
