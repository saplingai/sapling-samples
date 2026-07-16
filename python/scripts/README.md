# Sapling Python 3 Examples

These use Sapling's [PyPI package](https://pypi.org/project/sapling-py/).

Documentation for the client is available at [Read the Docs](https://sapling.readthedocs.io/) and documentation for the HTTP API is available on [Sapling.ai](https://sapling.ai/docs).

## Installation

Install the `sapling-py` package with [pip](https://pip.pypa.io/en/stable/installation/):
```
python -m pip install sapling-py
```

## Running

Set your API key in the `SAPLING_API_KEY` environment variable (or replace
`<YOUR_API_KEY>` in the script), then run one of:

```
python3 get_edits.py           # Grammar and spelling edits
python3 get_ai_detection.py    # AI-generated content detection, with chunking
python3 analyze_text.py        # Rephrase, tone, sentiment and language detection
```

`analyze_text.py` requires `sapling-py` version 4.1.0 or later.

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
