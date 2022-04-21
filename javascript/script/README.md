# Sapling JavaScript Example

## Installation

- Register for an account at https://sapling.ai and sign in.
- Generate a development API key in your dashboard.
- Replace `<YOUR_API_KEY>` with Sapling API key.
- Install the sapling-js package: `npm i @saplingai/sapling-js`

## Running

Run `node test.js`

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
