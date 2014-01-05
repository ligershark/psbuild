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

# build an msbuild file and execute a specific target
Invoke-MSBuild C:\temp\msbuild\proj1.proj -targets Demo

# build an msbuild file and execute multiple targets
Invoke-MSBuild C:\temp\msbuild\proj1.proj -targets @('Demo';'Demo2')

# You can also create a new MSBuild file with the following
New-Project | Save-Project -filePath .\new.proj

# to see what commands are available
Get-Command -Module psbuild

```

Most functions have help defined so you can use ```get-help``` on most commands for more details.

We have not yet developed the NuGet package yet but will be working on it soon.

# Reporting Issues
To report any issues please create an item on the [issues page](https://github.com/sayedihashimi/psbuild/issues/new).

# Contributing
Contributing is pretty simple. The project mostly consists of one .psm1 file located at ```/src/psbuild.psm1```. Just modify that file with the updates and send me a Pull Request. I'll review it and work with you from there.