#!/bin/sh
# Launch script for UltraStar Community Edition
# Set $DEBUGGER to launch the app with a debugger.

# Change to game directory
GAMEPATH="`readlink -f "$0"`"
cd "`dirname "$GAMEPATH"`"

BIN=./usce

# Run the game, (optionally) with the debugger
exec $DEBUGGER $BIN "$@"
