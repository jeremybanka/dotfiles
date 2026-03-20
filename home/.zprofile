# deal with the intractable issue of my option-key being stuck down ############
  if [[ "$(scutil --get ComputerName)" == "Eris" ]]; then
    hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x7000000E2,"HIDKeyboardModifierMappingDst":0x700000000}]}'
  fi

# use homebrew
  eval $(/opt/homebrew/bin/brew shellenv)
