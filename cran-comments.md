This is a resubmission.

## Corrected problems

I fixed two problems identified by CRAN:

-   Added all copyright holders to LICENSE. This was an accidental oversight; all copyright holders have always been included in DESCRIPTION and LICENSE.note.

-   Fixed 'Additional issues' resulting from the UBsan build.

## Remaining issues

0 errors \| 0 warnings \| 1 note

-   NOTE: GNU make is a SystemRequirements.

    *Justification*: This package wraps the LuaJIT compiler, which requires GNU make to build. The build system for LuaJIT is very complex, so it would be prohibitively difficult to get around this requirement.
