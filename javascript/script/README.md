# Sapling JavaScript Example

## Installation

- Register for an account at https://sapling.ai and sign in.
- Generate a development API key in your dashboard.
- Replace `<YOUR_API_KEY>` in `get_edits.mjs` with Sapling API key.
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


## CommonJS

The Sapling JavaScript SDK is a ES6 (ECMAScript 6) module, standard for web JavaScript and supported by Node.js since v13.


ES modules use `import` to including libraries and cannot use `require`.
CommonJS modules use `require` to include libraries and cannot use `import`.


If you want to use Sapling in a CommonJS module or file, you can use a dynamic import. An example of this is provided in `commonjs_get_edits.cjs`.
