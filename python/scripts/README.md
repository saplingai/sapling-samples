# Sapling Python 3 Example

This uues Sapling's [PyPI package](https://pypi.org/project/sapling-py/).

Documentation for the client is available at [Read the Docs](https://sapling.readthedocs.io/) and documentation for the HTTP API is available on [Sapling.ai](https://sapling.ai/docs).

## Installation

Install the `sapling-py` package with [pip](https://pip.pypa.io/en/stable/installation/):
```
python -m pip install sapling-py
```

## Running

Replace `<YOUR_API_KEY>` with Sapling API key, then run:
```
python3 get_edits.py
```

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
