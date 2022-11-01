/// The applyEdits function takes in the 2 parameters namely text and edit.
/// The text parameter denotes the text that you would want to edit and the edits parameter denotes the JSON response
/// that must be parsed into a list.
/// The function returns a text with the replacement of the words at the required places

String applyEdits(String text, List edits) {
  edits.sort((a, b) =>
      b['sentence_start'] +
      b['start'] -
      a['sentence_start'] -
      a['start']); // sorting the JSON response in the list in reverse order to apply the edits
  for (dynamic edit in edits) {
    var start = edit['sentence_start'] +
        edit[
            'start']; // assigning the start index of the sentence based on the response using a for loop
    var end = edit['sentence_start'] +
        edit[
            'end']; // assigning the end index of the sentence based on the response using a for loop
    if (start > text.length || end > text.length) {
      print(
          'Edit start:$start/$end:$end outside of bounds of text:$text'); // ensuring that the start index is greater than the length of the text
    }
    text = (text.substring(0, start) +
            edit['replacement'] +
            text.substring(end))
        .toString(); // replacing the words with errors in the text that was passed into the function to apply the edits
  }
  return text;
}
