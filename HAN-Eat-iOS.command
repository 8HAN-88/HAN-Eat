#!/bin/bash
# Двойной клик в Finder: открывает единственно верный iOS-проект Flutter (не SwiftUI-шаблон).
cd "$(dirname "$0")" || exit 1
if [ ! -f "ios/Runner.xcworkspace/contents.xcworkspacedata" ]; then
  osascript -e 'display dialog "Положите этот файл в КОРЕНЬ репозитория HAN-Eat (рядом с pubspec.yaml)." buttons {"OK"} default button 1 with icon stop'
  exit 1
fi
open "ios/Runner.xcworkspace"
