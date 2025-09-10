#!/usr/bin/env bash

# make sure it's executable with:
# chmod +x ~/.config/sketchybar/plugins/aerospace.sh

source "$HOME/.config/sketchybar/colors.sh" # Loads all defined colors

if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
    sketchybar --set $NAME background.color=$PRIMARY_ACCENT
else
    sketchybar --set $NAME background.color=$TRANSPARENT
fi
