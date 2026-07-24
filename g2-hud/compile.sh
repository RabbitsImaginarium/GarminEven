#!/bin/bash
# Bundle app.js into bundle.js (unminified so it is readable)
npx esbuild app.js --bundle --outfile=bundle.js --format=esm

# Clean old packages and pack the directory
rm -f *.ehpk
evenhub pack app.json . -o g2hud.ehpk
