#!/usr/bin/env nu

def main [] {
  let colors = [
    { name: "Black", code: "\u{1b}[30m" }
    { name: "Red", code: "\u{1b}[31m" }
    { name: "Green", code: "\u{1b}[32m" }
    { name: "Yellow", code: "\u{1b}[33m" }
    { name: "Blue", code: "\u{1b}[34m" }
    { name: "Magenta", code: "\u{1b}[35m" }
    { name: "Cyan", code: "\u{1b}[36m" }
    { name: "White", code: "\u{1b}[37m" }
    { name: "Bright Black", code: "\u{1b}[90m" }
    { name: "Bright Red", code: "\u{1b}[91m" }
    { name: "Bright Green", code: "\u{1b}[92m" }
    { name: "Bright Yellow", code: "\u{1b}[93m" }
    { name: "Bright Blue", code: "\u{1b}[94m" }
    { name: "Bright Magenta", code: "\u{1b}[95m" }
    { name: "Bright Cyan", code: "\u{1b}[96m" }
    { name: "Bright White", code: "\u{1b}[97m" }
  ]

  for color in $colors {
    print $"($color.code)($color.name)(ansi reset)"
  }
}
