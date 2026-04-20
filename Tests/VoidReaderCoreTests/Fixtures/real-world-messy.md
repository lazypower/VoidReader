<!--
  Shape: real-world-messy
  Approx size: ~4KB
  Why: paste-from-web artifacts: zero-width spaces, smart quotes, non-breaking spaces, odd whitespace, mixed line endings. Tuned to surface normalizer and whitespace-heuristic regressions.
-->

# Real‐World Messy

A paragraph pasted from​the web with​a zero-width space
and a non breaking space mid-sentence.
Mixed line endings live above; “smart quotes” bracket this
sentence, along with ‘single’ variants and an em—dash.

﻿A second paragraph begins with a BOM artifact.
Trailing whitespace lurks here:    
and an ellipsis… closes the thought with an en dash – sometimes.

- Bullet with nbsp
- Bullet with​zwsp
- Bullet with mixed  double  spaces

```
Code block with	tabs	embedded	and a line ending in space    
Second line, same block, no trailing whitespace.
```

| Col A | Col B |
| --- | --- |
| “quoted” | plain |
| – dash | — dash |
