## How a gate works

The diff under review is at the end of this prompt, with the latest
mechanical test run after it. You cannot read files: `write` is your
only tool. Judge the diff as given.

Answer by calling the `write` tool once, with the findings file, and
then stop. Only that file is read; the text of your reply is discarded,
so a verdict stated in your reply alone counts as no answer at all.
Never print the diff or any file's contents back in your reply.

## Findings format (all gates)


Write one finding per line, at most 10 lines, each in this exact shape
(path relative to this directory, then the line number, then one
sentence):

    - path/to/file.py:LINE: one sentence

No headings, no bold, no prose before or after the lines. A line that
does not start with path:LINE is discarded by the driver.

If there is nothing to report, write exactly "no findings" plus a
one-line reason.
