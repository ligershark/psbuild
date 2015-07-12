[1mdiff --git a/src/psbuild.psm1 b/src/psbuild.psm1[m
[1mindex 87a9d4c..3afbbf5 100644[m
[1m--- a/src/psbuild.psm1[m
[1m+++ b/src/psbuild.psm1[m
[36m@@ -38,10 +38,10 @@[m [m$global:PSBuildSettings = New-Object PSObject -Property @{[m
     BuildMessageStrongBackgroundColor = [ConsoleColor]::DarkGreen[m
 [m
     EnabledLoggers = @('detailed','diagnostic','markdown','appveyor')[m
[1;31m-    LogDirectory = ('{0}\LigerShark\PSBuild\logs\' -f $env:temp)[m
[1;32m+[m[1;32m    LogDirectory = ('{0}\LigerShark\PSBuild\logs\' -f $env:localappdata)[m
     LastLogDirectory = $null[m
 [m
[1;31m-    TempDirectory = ('{0}\LigerShark\PSBuild\temp\' -f $env:temp)[m
[1;32m+[m[1;32m    TempDirectory = ('{0}\LigerShark\PSBuild\temp\' -f $env:localappdata)[m
 [m
     DefaultClp = '/clp:v=m;Summary'[m
     ToolsDir = ''[m
[36m@@ -62,7 +62,7 @@[m [m$global:PSBuildSettings = New-Object PSObject -Property @{[m
 [m
      1. see if tools dir is defined in $env:PSBuildToolsDir[m
      2. see if psbuild.dll exists in the same folder[m
[1;31m-     3. look for the latest version in %temp%[m
[1;32m+[m[1;32m     3. look for the latest version in %localappdata%[m
 #>[m
 function InternalGet-PSBuildToolsDir{[m
     [cmdletbinding()][m
[36m@@ -86,9 +86,9 @@[m [mfunction InternalGet-PSBuildToolsDir{[m
                 'Assigned ToolsDir to the script folder [{0}]' -f ($private:toolsDir) | Write-Verbose[m
             }[m
         }[m
[1;31m-        # 3 look for the latest version in %temp%[m
[1;32m+[m[1;32m        # 3 look for the latest version in %localappdata%[m
         if([string]::IsNullOrWhiteSpace($private:toolsDir)){[m
[1;31m-            $lsToolsPath = ('{0}\LigerShark\tools\' -f $env:temp)[m
[1;32m+[m[1;32m            $lsToolsPath = ('{0}\LigerShark\tools\' -f $env:localappdata)[m
             $psbuildDllUnderAppData = (Get-ChildItem -Path "$lsToolsPath" -Include 'psbuild.dll' -Recurse -ErrorAction SilentlyContinue | Sort-Object -Descending -ErrorAction SilentlyContinue | Select-Object -First 1 -ErrorAction SilentlyContinue)[m
             if($psbuildDllUnderAppData -and (test-path $psbuildDllUnderAppData)){[m
                 $private:toolsDir = ((get-item ($psbuildDllUnderAppData)).Directory.FullName)[m
[36m@@ -1009,7 +1009,7 @@[m [mfunction Set-PSBuildLogDirectory{[m
         }[m
         else{[m
             # reset the log directory[m
[1;31m-            $global:PSBuildSettings.LogDirectory = ('{0}\LigerShark\PSBuild\logs\' -f $env:temp)[m
[1;32m+[m[1;32m            $global:PSBuildSettings.LogDirectory = ('{0}\LigerShark\PSBuild\logs\' -f $env:localappdata)[m
         }[m
     }[m
 }[m
