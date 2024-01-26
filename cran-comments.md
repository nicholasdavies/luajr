## Resubmission
This is a resubmission. In this version I have:

* Resolved an R CMD check warning about initializers of const uint32_t 
variables not being constant expressions by replacing them with #defines in
lj_target_x86.h.

This is in addition to the previous resubmission, in which I:

* Resolved an R CMD check warning about values of the enum x86Op in LuaJIT 
defining values outside the int (but within the uint32_t) range, which was 
identified by the flag -Wpedantic.

* Resolved an R CMD check warning about a non-void* argument to lj_strfmt_pushf,
which was identified by the flag -Wformat.

## R CMD check results

0 errors | 0 warnings | 2 notes

* Note 1

  checking for GNU extensions in Makefiles ... NOTE
  
  GNU make is a SystemRequirements.
  
  *Justification*: This package wraps the LuaJIT compiler, which requires GNU
  make to build. The build system for LuaJIT is very complex, so it would be 
  prohibitively difficult to get around this requirement.

* Note 2 (Windows only)

  checking line endings in C/C++/Fortran sources/headers ... NOTE
  
  Found the following sources/headers with CR or CRLF line endings:
  
  ```
    src/luajit/src/host/buildvm_arch.h
    src/luajit/src/lj_bcdef.h
    src/luajit/src/lj_ffdef.h
    src/luajit/src/lj_folddef.h
    src/luajit/src/lj_libdef.h
    src/luajit/src/lj_recdef.h
  ```
 
  Some Unix compilers require LF line endings.
  
  *Justification*: These headers are generated during the build process, and 
  only have CRLF endings if the package is built on Windows. If the package is 
  built on Unix (or macOS), the headers are generated with LF line endings, as 
  is common on those platforms. Therefore, this is not an issue in practice.
