$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$importPsbuild = (Join-Path -Path $here -ChildPath 'import-psbuild.ps1')
. $importPsbuild
$global:PSBuildSettings.BuildMessageEnabled = $false
function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDir = ((Get-ScriptDirectory) + "\")

set-msbuild
Describe "get and set msbuild test cases" {

    Setup -File 'sayedha\fakemsbuildfile01.txt' 
    Setup -File 'sayedha\fakemsbuildfile02.txt' 
    Add-Type -AssemblyName Microsoft.Build
    It "validate msbuild returns a file that exists" {
        $msbuildPath = Get-MSBuild
        $msbuildPath | Should Exist $msbuildPath
    }

    It "validate set-msbuild works" {
        
        $fakePath = ($msbuildDefaultPath = ("{0}\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe" -f $env:windir))
        $fakePath = "$TestDrive\sayedha\fakemsbuildfile01.txt"
        Set-MSBuild -msbuildPath $fakePath
        $retPath = (Get-MSBuild)
        $retPath | Should Be $fakePath
    }

    It "validate set-msbuild to null resets" {
        # call set-msbuild with a value and then call it with null and ensure the default value is used
        Set-MSBuild -msbuildPath "$TestDrive\sayedha\fakemsbuildfile02.txt"
        $valueBeforeSet = Get-MSBuild

        Set-MSBuild

        $valueAfterSet = Get-MSBuild

        $valueBeforeSet | Should Not Be $valueAfterSet
    }

    It "validate Get-MSBuildEscapeCharacters returns 10 values" {
        $msbEscape = Get-MSBuildEscapeCharacters
        $msbEscape.Length | Should Be 10
    }
}
set-msbuild


Describe "Open-PSBuildLog test cases" {
    $script:tempProj = 'Open-PSBuildLog\temp.proj'
    $script:tempProjContent = @"
        <?xml version="1.0" encoding="utf-8"?>
        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Demo" ToolsVersion="4.0">

          <Target Name="Demo">
            <Message Text="Hello World" Importance="high"/>
          </Target>

        </Project>
"@
    Setup -File -Path $script:tempProj -Content $script:tempProjContent
    $tempProjFilePath = Join-Path $TestDrive $script:tempProj

    It "validate Open-PSBuildLog returns a file path-default" {
        Invoke-MSBuild $tempProjFilePath
        $logFilePath = Open-PSBuildLog -returnFilePathInsteadOfOpening
        $logFilePath | Should Exist
    }

    It "validate Open-PSBuildLog returns a file path-diagnostic" {
        Invoke-MSBuild $tempProjFilePath
        $logFilePath = Open-PSBuildLog diagnostic -returnFilePathInsteadOfOpening
        $logFilePath | Should Exist
    }

    It "validate Open-PSBuildLog returns a file path-detailed" {
        Invoke-MSBuild $tempProjFilePath
        $logFilePath = Open-PSBuildLog detailed -returnFilePathInsteadOfOpening
        $logFilePath | Should Exist
    }

    It "validate Open-PSBuildLog returns a file path-markdown" {
        Invoke-MSBuild $tempProjFilePath
        $logFilePath = Open-PSBuildLog markdown -returnFilePathInsteadOfOpening
        $logFilePath | Should Exist
    }
}

Describe "Get-MSBuildEscapeCharacters tests" {
    It "returns a non-empty array" {
        $escapeChars = Get-MSBuildEscapeCharacters
        $escapeChars -is [array] | Should Be $true
        $escapeChars | %{
            $_ | Should Not BeNullOrEmpty
        }
    }
}

Describe "Get-MSBuildReservedProperties tests" {
    It "returns non-empty and contains reserved props" {
        $reservedProps = Get-MSBuildReservedProperties

        $allText = ($foo -join "`n")
        $allText | Should NOt BeNullOrEmpty
        $allText | Should Match 'MSBuildBinPath:'
        $allText | Should Match 'MSBuildProjectDirectory:'
        $allText | Should Match 'MSBuildThisFileDirectory:'
        $allText | Should Match 'MSBuildThisFileExtension:'
    }
}

Describe "New-MSBuildProject tests" {
    It "creates a file at specified location" {
        $tempProjFilePath = Join-Path $TestDrive 'New-MSBuildProject\create01.proj'
        $newFile = New-MSBuildProject -filePath ($tempProjFilePath)
        $newFile | Should Not Be $null
        $tempProjFilePath | Should Exist
    }
}