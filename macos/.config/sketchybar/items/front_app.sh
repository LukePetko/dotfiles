#!/usr/bin/env sh

sketchybar --add       event        window_focus_changed          \
           --add       event        spaces_changed                \
           --add       item         system.aerospace left         \
           --set       system.aerospace script="$PLUGIN_DIR/aerospace.sh" \
                                        icon.font="$FONT:Bold:16.0"   \
                                        label.drawing=off             \
                                        icon.width=30                 \
                                        icon=$AEROSPACE_ICON          \
                                        icon.color=$GREEN             \
                                        updates=on                    \
                                        associated_display=active     \
           --subscribe system.aerospace window_focus_changed          \
                                        spaces_changed                \
                                        mouse.clicked                 \
                                                                      \
           --add       item         front_app left                    \
           --set       front_app    mach_helper="$HELPER"             \
                                        icon.drawing=off              \
                                        background.padding_left=0     \
                                        background.padding_right=10   \
                                        label.color=$WHITE            \
                                        label.font="$FONT:Black:10.0" \
                                        associated_display=active     \
           --subscribe front_app    front_app_switched

