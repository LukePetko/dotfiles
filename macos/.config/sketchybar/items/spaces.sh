#!/usr/bin/env bash

sketchybar --add event aerospace_workspace_change

# SPACE_ICONS=$(aerospace list-workspaces --all)
SPACE_ICONS=("1" "2" "3" "4" "5" "6")

sid=0
for i in "${SPACE_ICONS[@]}"; do
    sid=$(($i))
    sketchybar --add item space.$sid left                \
       --subscribe space.$sid aerospace_workspace_change \
       --set space.$sid                                  \
       icon=${SPACE_ICONS[i-1]}                          \
       icon.padding_left=22                              \
       icon.padding_right=22                             \
       background.height=25                              \
       background.corner_radius=9                        \
       background.color=$TRANSPARENT                     \
       background.drawing=on                             \
       label.font="sketchybar-app-font:Regular:16.0"     \
       label.background.height=25                        \
       label.background.drawing=on                       \
       label.background.color=0xff494d64                 \
       label.background.corner_radius=9                  \
       label.drawing=off                                 \
       script="$CONFIG_DIR/plugins/aerospace.sh $sid"    \
       click_script="aerospace workspace $sid"
done
