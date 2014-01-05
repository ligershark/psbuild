psbuild
=======

This project aims to make using MSBuild easier from powershell. The project has two main purposes

1. To make interacting with MSBuild files in PowerShell much easier
1. To make it easier to manipulate MSBuild files from PowerShell/NuGet

Currently psbuild is still a ***preview*** but should be stable enough for regular usage.

# Getting Started

```
# download and install psbulid
(new-object Net.WebClient).DownloadString("https://raw.github.com/sayedihashimi/psbuild/master/src/GetPSBuild.ps1") | iex

# build an msbuild file
Invoke-MSBuild C:\temp\msbuild\msbuild.proj

# build the file provided with the given parameters
Invoke-MSBuild C:\temp\msbuild\path.proj -properties (@{'Configuration'='Release';'visualstudioversion'='12.0'}) -extraArgs '/nologo'

# to see what commands are available
Get-Command -Module psbuild

```

Most functions have help defined so you can use ```get-help``` on most commands for more details.
