set iconsFolderPath to POSIX path of (path to home folder) & "dotfiles/icons/"

-- Get a list of .icns files in the ~/icons directory, accounting for spaces in filenames
set appNames to do shell script "ls " & quoted form of iconsFolderPath & "*.icns | xargs -n 1 basename | sed 's/\\.icns$//'"

-- Convert the list to AppleScript list format
set AppleScript's text item delimiters to linefeed
set appNamesList to paragraphs of appNames

-- Loop through the application names and set their icons
repeat with appName in appNamesList
    set appPath to "/Applications/" & appName & ".app"
    set iconPath to iconsFolderPath & appName & ".icns"
    
    -- Debugging: Check if the application exists
    set appExists to do shell script "if [ -d " & quoted form of appPath & " ]; then echo 'yes'; else echo 'no'; fi"
    
    if appExists is "yes" then
        try
            -- Copy the icon file to the application bundle
            do shell script "cp " & quoted form of iconPath & " " & quoted form of appPath & "/Contents/Resources/applet.icns"
            -- Touch the application bundle to refresh the icon cache
            do shell script "touch " & quoted form of appPath
            
            display dialog "Icon for " & appName & " changed successfully." buttons {"OK"} default button "OK"
        on error errMsg number errNum
            -- Debugging: Show the error message
            display dialog "Failed to change icon for " & appName & ". Error: " & errMsg & " (" & errNum & ")" buttons {"OK"} default button "OK"
        end try
    else
        display dialog "Application " & appName & " not found at " & appPath buttons {"OK"} default button "OK"
    end if
end repeat