const apiKey = '<YOUR_API_KEY>';

import('@saplingai/sapling-js/client').then((sapling) =>{
  const client = new sapling.Client(apiKey);
  client
    .edits('Lets get started!')
    .then(function (response) {
      console.log(response.data);
    })
});
