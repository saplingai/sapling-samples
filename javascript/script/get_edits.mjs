import { Client } from "@saplingai/sapling-js/client";

const apiKey = '<YOUR_API_KEY>';
const client = new Client(apiKey);
client
  .edits('Lets get started!')
  .then(function (response) {
    console.log(response.data);
  })
