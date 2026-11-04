# Sapling Python 3 Examples

These use Sapling's [PyPI package](https://pypi.org/project/sapling-py/).

Documentation for the client is available at [Read the Docs](https://sapling.readthedocs.io/) and documentation for the HTTP API is available on [Sapling.ai](https://sapling.ai/docs).

## Installation

Install the `sapling-py` package from PyPI with
[pip](https://pip.pypa.io/en/stable/installation/):

```sh
python -m pip install sapling-py
```

Or add it to a [uv](https://docs.astral.sh/uv/) project:

```sh
uv add sapling-py
```

## Running

Set your API key in the `SAPLING_API_KEY` environment variable (or replace
`<YOUR_API_KEY>` in the script), then run one of:

```
python3 get_edits.py           # Grammar and spelling edits
python3 get_ai_detection.py    # AI-generated content detection, with chunking for long text
python3 analyze_text.py        # Rephrase, tone, sentiment and language detection
```

`analyze_text.py` requires `sapling-py` version 4.1.0 or later.

`get_ai_detection.py` prints a verdict and the sentences flagged as AI-generated for each chunk,
followed by the overall score and the share of the text that reads as AI-generated. See the
[AI Detector API reference](https://sapling.ai/docs/api/detector) for all of the fields and options.

The result of `get_edits.py` should be an array of edits of this form:
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
