# Sapling SDK: Example Express App

This app uses Sapling into an Express application with a public facing React webpage.
Text from the public page is passed to the Express backend, which adds the API key before proxying onto Sapling servers. This way, the private Sapling API key is never exposed. The Express server may also do user authentication.

Sapling is declared as an npm dependancy in `package.json` installed as a dependancy through npm.


## Installation

- `npm install`
- Register for an account at [https://sapling.ai](https://sapling.ai/user/register), then sign in.
- Generate a development API key in your dashboard.
- Replace `<YOUR_API_KEY>` in `src/server.mjs` with your Sapling API key.

## Running

Run `npm run server`


Then visit [http://localhost:3000](http://localhost:3000) to view the app in your browser.
