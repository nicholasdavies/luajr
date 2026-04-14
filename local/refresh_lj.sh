#!/bin/sh

# Remove old src/luajit
rm -rf ../src/luajit

# Copy new version to src/luajit; remove doc and .git directories
cp -R LuaJIT ../src/luajit
rm -rf ../src/luajit/doc
rm -rf ../src/luajit/.git

# Move in luajrstdr.h and lj_luajr.c
cp luajrstdr.h ../src/luajit/src
cp lj_luajr.c ../src/luajit/src

# Modify Makefile to not build executables, modify lj_def.h to include luajrstdr.h, install R/C headers, etc
cd ..
Rscript ./local/headers.R
cd local
