## Findings format (all gates)

Read only the lines around each place you want to cite, not whole
files: use `sed -n 'A,Bp' path` for at most 40 lines per call. Never
print a file's contents in your reply. The diff is the scope; a large
read costs more than it tells.

Write one finding per line, at most 10 lines, each in this exact shape
(path relative to this directory, then the line number, then one
sentence):

    - path/to/file.py:LINE: one sentence

No headings, no bold, no prose before or after the lines. A line that
does not start with path:LINE is discarded by the driver.

If there is nothing to report, write exactly "no findings" plus a
one-line reason.
