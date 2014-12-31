[cmdletbinding()]
param(
    [Parameter(ParameterSetName='build',Position=0)]
    [switch]$build,
    
    [Parameter(ParameterSetName='updateversion',Position=0)]
    [switch]$updateversion,

    # build parameters
    [Parameter(ParameterSetName='build',Position=1)]
    [switch]$CleanOutputFolder,

    # updateversion parameters
    [Parameter(ParameterSetName='updateversion',Position=1,Mandatory=$true)]
    [string]$newversion,

    [Parameter(ParameterSetName='updateversion',Position=2)]
    [string]$oldversion
)
 
 function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDir = ((Get-ScriptDirectory) + "\")

<#
.SYNOPSIS  
	This will return the path to msbuild.exe. If the path has not yet been set
	then the highest installed version of msbuild.exe will be returned.
#>
function Get-MSBuild{
    [cmdletbinding()]
        param()
        process{
	    $path = $script:defaultMSBuildPath

	    if(!$path){
	        $path =  Get-ChildItem "hklm:\SOFTWARE\Microsoft\MSBuild\ToolsVersions\" | 
				        Sort-Object {[double]$_.PSChildName} -Descending | 
				        Select-Object -First 1 | 
				        Get-ItemProperty -Name MSBuildToolsPath |
				        Select -ExpandProperty MSBuildToolsPath
        
            $path = (Join-Path -Path $path -ChildPath 'msbuild.exe')
	    }

        return Get-Item $path
    }
}

<#
.SYNOPSIS
    If nuget is in the tools
    folder then it will be downloaded there.
#>
function Get-Nuget(){
    [cmdletbinding()]
    param(
        $toolsDir = ("$env:LOCALAPPDATA\LigerShark\tools\"),

        $nugetDownloadUrl = 'http://nuget.org/nuget.exe'
    )
    process{
        $nugetDestPath = Join-Path -Path $toolsDir -ChildPath nuget.exe
        
        if(!(Test-Path $nugetDestPath)){
            'Downloading nuget.exe' | Write-Verbose
            (New-Object System.Net.WebClient).DownloadFile($nugetDownloadUrl, $nugetDestPath)

            # double check that is was written to disk
            if(!(Test-Path $nugetDestPath)){
                throw 'unable to download nuget'
            }
        }

        # return the path of the file
        $nugetDestPath
    }
}

function Enable-GetNuGet{
    [cmdletbinding()]
    param($toolsDir = "$env:LOCALAPPDATA\LigerShark\tools\getnuget\",
        $getNuGetDownloadUrl = 'https://raw.githubusercontent.com/sayedihashimi/publish-module/master/getnuget.psm1')
    process{
        if(!(get-module 'getnuget')){
            if(!(Test-Path $toolsDir)){ New-Item -Path $toolsDir -ItemType Directory -WhatIf:$false }

            $expectedPath = (Join-Path ($toolsDir) 'getnuget.psm1')
            if(!(Test-Path $expectedPath)){
                'Downloading [{0}] to [{1}]' -f $getNuGetDownloadUrl,$expectedPath | Write-Verbose
                (New-Object System.Net.WebClient).DownloadFile($getNuGetDownloadUrl, $expectedPath)
                if(!$expectedPath){throw ('Unable to download getnuget.psm1')}
            }

            'importing module [{0}]' -f $expectedPath | Write-Verbose
            Import-Module $expectedPath -DisableNameChecking -Force -Scope Global
        }
    }
}

<#
.SYNOPSIS 
This will inspect the publsish nuspec file and return the value for the Version element.
#>
function GetExistingVersion{
    [cmdletbinding()]
    param(
        [ValidateScript({test-path $_ -PathType Leaf})]
        $nuspecFile = (Join-Path $scriptDir 'psbuild.nuspec')
    )
    process{
        ([xml](Get-Content $nuspecFile)).package.metadata.version
    }
}

function UpdateVersion{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$newversion,

        [Parameter(Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$oldversion = (GetExistingVersion),

        [Parameter(Position=2)]
        [string]$filereplacerVersion = '0.2.0-beta'
    )
    process{
        'Updating version from [{0}] to [{1}]' -f $oldversion,$newversion | Write-Verbose
        Enable-GetNuGet
        'trying to load file replacer' | Write-Verbose
        Enable-NuGetModule -name 'file-replacer' -version $filereplacerVersion

        $folder = $scriptDir
        $include = '*.nuspec;*.ps*1'
        # In case the script is in the same folder as the files you are replacing add it to the exclude list
        $exclude = "$($MyInvocation.MyCommand.Name);"
        $replacements = @{
            "$oldversion"="$newversion"
        }
        Replace-TextInFolder -folder $folder -include $include -exclude $exclude -replacements $replacements | Write-Verbose
        'Replacement complete' | Write-Verbose
    }
}

function Clean-OutputFolder{
    [cmdletbinding()]
    param()
    process{
        $outputFolder = (Join-Path $scriptDir '\OutputRoot\')

        if(Test-Path $outputFolder){
            'Deleting output folder [{0}]' -f $outputFolder | Write-Host
            Remove-Item $outputFolder -Recurse -Force
        }

    }
}

function Run-Tests{
    [cmdletbinding()]
    param(
        $testDirectory = (join-path $scriptDir tests)
    )
    process{
        # go to the tests directory and run pester
        push-location
        set-location $testDirectory
        Invoke-Pester
        pop-location
    }
}

function Build{
    [cmdletbinding()]
    param()
    process{
        if($CleanOutputFolder){
            Clean-OutputFolder
        }

        $projFilePath = get-item (Join-Path $scriptDir 'psbuild.proj')

        $msbuildArgs = @()
        $msbuildArgs += $projFilePath.FullName
        $msbuildArgs += '/p:Configuration=Release'
        $msbuildArgs += '/p:VisualStudioVersion=12.0'
        $msbuildArgs += '/flp1:v=d;logfile=build.d.log'
        $msbuildArgs += '/flp2:v=diag;logfile=build.diag.log'
        $msbuildArgs += '/m'

        & ((Get-MSBuild).FullName) $msbuildArgs

        # Run-Tests
    }
}

if(!$build -and !$updateversion){
    $build = $true
}

if($build){ Build }
elseif($updateversion){ UpdateVersion -newversion $newversion }
else{
    $cmds = @('-build','-updateversion')
    'Command not found or empty, please pass in one of the following [{0}]' -f ($cmds -join ' ') | Write-Error
}