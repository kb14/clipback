---
name: Bug report
about: Something doesn't work as it should
labels: bug
---

**What happened**


**What you expected**


**Steps to reproduce**
1.
2.

**Where you captured from** (the app, and the browser or file type if it matters)


**Your Mac**
- macOS version:
- Clipback version (menu bar → About Clipback):
- Apple Silicon or Intel:

If capture failed, the log helps. Run this in Terminal right after it happens and paste the output (check it first for anything private):

```
log show --last 5m --predicate 'subsystem == "io.github.kb14.clipback"' --info
```
