This is a resubmission.

I have updated the copyright statement in LICENSE and LICENSE.md, reordered the
authors in DESCRIPTION in order of the size of the contribution to all source 
code included in the package, and clarified that the copyright holder "Lua.org,
PUC-Rio" applies to portions of the Lua source code that are included within
LuaJIT. To the best of my knowledge this resolves all issues around copyright
raised by CRAN.

All previous issues raised by CRAN remain fixed in this resubmission, except 
for the NOTE about GNU make which is described below.

## Remaining issues

0 errors \| 0 warnings \| 1 note

-   NOTE: GNU make is a SystemRequirements.

    *Justification*: This package wraps the LuaJIT compiler, which requires GNU 
    make to build. The build system for LuaJIT is very complex, so it would be 
    prohibitively difficult to get around this requirement.
