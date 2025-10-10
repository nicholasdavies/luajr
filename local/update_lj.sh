#!/bin/sh

# Update LuaJIT, write "relver" number to luajit_relver.txt
cd LuaJIT
git pull
git show -s --format=%ct > src/luajit_relver.txt
cd src
cp luajit_relver.txt ../../../tools
lua host/genversion.lua
cd ../..

# Remove old src/luajit
rm -rf ../src/luajit

# Copy new version to src/luajit; remove doc and .git directories
cp -R LuaJIT ../src/luajit
rm -rf ../src/luajit/doc
rm -rf ../src/luajit/.git

# Move in luajrstdr.h
cp luajrstdr.h ../src/luajit/src

# Modify Makefile to not build executables, modify lj_def.h to include luajrstdr.h, install R/C headers
cd ..
Rscript ./local/headers.R
cd local
