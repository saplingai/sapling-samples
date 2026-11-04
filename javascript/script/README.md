# Sapling JavaScript Example

## Installation

- Register for an account at https://sapling.ai and sign in.
- Generate a development API key in your dashboard.
- Replace `<YOUR_API_KEY>` in `get_edits.mjs` and `get_ai_detection.mjs` with Sapling API key.
- Install the sapling-js package: `npm i @saplingai/sapling-js`


## Running

Run `node get_edits.mjs`

The result should be an array of edits of this form:

```
{
  edits: [
    {
      "id": "aa5ee291-a073-5146-8ebc-c9c899d01278",
      "sentence": "Lets get started!",
      "sentence_start": 0,
      "start": 0
      "end": 4,
      "replacement": "Let's",
      "error_type": "R:OTHER",
      "general_error_type": "Other"
    }
  ]
}
```


## AI detection

Run `node get_ai_detection.mjs`

This prints the overall score, the share of the text that reads as AI-generated, a verdict of
`human`, `mixed` or `ai`, and each sentence flagged as AI-generated. The API response has this form:

```
{
  score: 0.97,
  ai_fraction: 1,
  verdict: 'ai',
  segments: [ { start: 0, end: 90, score: 0.98 } ],
  low_confidence: false,
  low_confidence_reasons: [],
  sentence_scores: [
    {
      sentence: 'Phone chargers are essential accessories that have become an integral part of modern life.',
      score: 0.98,
      start: 0,
      end: 90
    }
  ],
  text: '...',
  version: '...'
}
```

See the [AI Detector API reference](https://sapling.ai/docs/api/detector) for all of the fields and options.


## CommonJS

The Sapling JavaScript SDK is a ES6 (ECMAScript 6) module, standard for web JavaScript and supported by Node.js since v13.


ES modules use `import` to including libraries and cannot use `require`.
CommonJS modules use `require` to include libraries and cannot use `import`.


If you want to use Sapling in a CommonJS module or file, you can use a dynamic import. An example of this is provided in `commonjs_get_edits.cjs`.
