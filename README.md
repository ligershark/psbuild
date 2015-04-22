psbuild
=======

[![Build status](https://ci.appveyor.com/api/projects/status/k7p2m9b6h5m9w2q3/branch/master)](https://ci.appveyor.com/project/sayedihashimi/psbuild/branch/master)

This project aims to make using MSBuild easier from powershell. The project has two main purposes

1. To make interacting with MSBuild files in PowerShell much easier
1. To make it easier to manipulate MSBuild files from PowerShell/NuGet

Currently psbuild is still a ***preview*** but should be stable enough for regular usage.

## Getting Started


##### download and install psbulid
<code style="background-color:grey">(new-object Net.WebClient).DownloadString("https://raw.github.com/ligershark/psbuild/master/src/GetPSBuild.ps1") | iex</code>

##### build an msbuild file
<code>Invoke-MSBuild C:\temp\msbuild\msbuild.proj</code>

##### build the file provided with the given parameters
<code>Invoke-MSBuild C:\temp\msbuild\path.proj -properties @{'Configuration'='Release';'visualstudioversion'='12.0'} -extraArgs '/nologo'</code>

##### build an msbuild file and execute a specific target
<code>Invoke-MSBuild C:\temp\msbuild\proj1.proj -targets Demo</code>

##### build an msbuild file and execute multiple targets
<code>Invoke-MSBuild C:\temp\msbuild\proj1.proj -targets @('Demo';'Demo2')</code>
##### how to get the log file for the last build

<code>Invoke-MSBuild C:\temp\msbuild\proj1.proj</code>
# returns the detailed log in the default editor
Open-PSBuildLog

# returns the log in markdown format
Open-PSBuildLog markdown

# returns the diagnostic
Open-PSBuildLog diagnostic</code>

#### show msbuild reserved properties
<code>Get-MSBuildReservedProperties</code>

#### show common msbuild escape characters
<code>Get-MSBuildEscapeCharacters</code>

##### You can also create a new MSBuild file with the following
<code>New-MSBuildProject | Save-MSBuildProject -filePath .\new.proj</code>

##### to see what commands are available
<code>Get-Command -Module psbuild</code>

Most functions have help defined so you can use ```get-help``` on most commands for more details.

We have not yet developed the NuGet package yet but will be working on it soon.

## Debug mode
In many cases after a build it would be helpful to be able to answer questions like the following.
 
 - What is the value of `x` property?
 - What is the value of `y` property?
 - What would the expression ```'@(Compile->'%(FullPath)')``` be?

But when you call msbuild.exe the project that is built is created in memory and trashed at the end of the process. ```Invoke-MSBuild``` now has a way that you can invoke your build and then have a _"handle"_ to your project that was built. This allows you to ask questions like the following. To enable this you just need to pass in the ```-debugMode``` switch to ```Invoke-MSBuild``` (_Note: this is actively under development so if you run into an problems please open an issue_). Here are some examples of what you can do.

<code>
PS> $bResult = Invoke-MSBuild .\temp.proj -debugMode

PS> $bResult.EvalProperty('someprop')
default

PS> $bResult.EvalItem('someitem')
temp.proj

PS> $bResult.ExpandString('$(someprop)')
default

PS> $bResult.ExpandString('@(someitem->''$(someprop)\%(Filename)%(Extension)'')')
default\temp.proj
</code>

You can get full access to the [ProjectInstance](http://msdn.microsoft.com/en-us/library/microsoft.build.execution.projectinstance(v=vs.121).aspx) object with the ProjectInstance property.

More functionality is available via the ProjectInstance object.

<code>
PS> $bResult.ProjectInstance.GetItems('someitem').EvaluatedInclude
temp.proj
</code>

You can get the [BuildResuilt](http://msdn.microsoft.com/en-us/library/microsoft.build.execution.buildresult(v=vs.121).aspx) via the BuildResult parameter.

<code>
PS> $bResult.BuildResult.OverallResult
Failure
</code>

# Reporting Issues
To report any issues please [create an new item](https://github.com/ligershark/psbuild/issues/new) on the [issues page](https://github.com/ligershark/psbuild/issues/).

# Contributing
Contributing is pretty simple. The project mostly consists of one .psm1 file located at ```/src/psbuild.psm1```. You should send PRs to the ```dev``` branch. If it's a simple bug fix feel free to go ahead and submit the fix as a PR. If you have a feature please propose it in the [issues](https://github.com/ligershark/psbuild/issues) section so that we can dicsuss your idea.

# Credit

This project uses the following open source components.

- [pester](https://github.com/pester/Pester) - Apache v2 ([link](https://github.com/pester/Pester/blob/master/LICENSE)) 
- [MarkdownLog](https://github.com/Wheelies/MarkdownLog) - MIT License ([link](https://github.com/Wheelies/MarkdownLog/blob/master/LICENSE))
