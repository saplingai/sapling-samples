import axios from "axios";
import cors from 'cors';
import express from 'express';
import path from 'path';

const __dirname = path.resolve();

const SAPLING_API_URL = 'https://api.sapling.ai/api/v1/edits';
const apiKey = '<API_KEY>';

const app = express();
app.use(cors())
app.use(express.json());

app.get('/', function(req, res) {
  console.log('get root');
  res.sendFile(path.join(path.resolve(), './dist/index.html'));
});

app.get('/main.js', function(req, res) {
  console.log('get root');
  res.sendFile(path.join(path.resolve(), './dist/main.js'));
});

app.post('/api/v1/edits', (req, res, next) => {
  req.body.key = apiKey;
  axios({
    url: SAPLING_API_URL,
    data: req.body,
    method: 'post',
  })
  .then(function (response) {
      res.statusCode = 200;
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify(response.data));
  });
})

app.listen(3000, () => {
  console.log(`Sapling sample app listening on port 3000`);
})
