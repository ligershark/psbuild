[cmdletbinding()]
param(
    $versionToInstall = '0.2.6-beta',
    $toolsDir = ("$env:LOCALAPPDATA\LigerShark\nuget-ps\tools\"),
    $nugetDownloadUrl = 'http://nuget.org/nuget.exe'
)

Set-StrictMode -Version Latest

function Get-PsModulesPath{
    [cmdletbinding()]
    param()
    process{
        $ModulePaths = @($Env:PSModulePath -split ';')

        $ExpectedUserModulePath = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath WindowsPowerShell\Modules
        $Destination = ($ModulePaths | Where-Object { $_ -eq $ExpectedUserModulePath} | Select-Object -First 1)
        if (-not $Destination) {
            $Destination = $ModulePaths | Select-Object -Index 0
        }

        $Destination
    }
}


# see if the particular version is installed under localappdata
function Get-NuGetPsPsm1{
    [cmdletbinding()]
    param(
        $toolsDir = $toolsDir,
        $nugetDownloadUrl = $nugetDownloadUrl
    )
    process{
        if(!(Test-Path $toolsDir)){
            New-Item -Path $toolsDir -ItemType Directory | out-null
        }

        [System.IO.FileInfo]$nugetPsPsm1 = (Get-ChildItem -Path "$toolsDir\nuget-powershell.$versionToInstall" -Include 'nuget-powershell.psm1' -Recurse -ErrorAction SilentlyContinue | Sort-Object -Descending -ErrorAction SilentlyContinue | Select-Object -First 1 -ErrorAction SilentlyContinue)

        if(!$nugetPsPsm1){
            Push-Location | Out-Null
            Set-Location $toolsDir | Out-Null
            'Downloading nuget-powershell to the toolsDir' | Write-Verbose
            # nuget install nuget-powershell -Version 0.0.1-beta1 -Prerelease
            $cmdArgs = @('install','nuget-powershell','-Version',$versionToInstall,'-Prerelease')

            $nugetPath = (Get-Nuget -toolsDir $toolsDir -nugetDownloadUrl $nugetDownloadUrl)
            'Calling nuget to install nuget-powershell with the following args. [{0} {1}]' -f $nugetPath, ($cmdArgs -join ' ') | Write-Verbose

            $command = (('"{0}" {1}') -f $nugetPath,($cmdArgs -join ' ' ))
            Execute-CommandString -command $command | Out-Null

            [System.IO.FileInfo]$nugetPsPsm1 = (Get-ChildItem -Path "$toolsDir\nuget-powershell.$versionToInstall" -Include 'nuget-powershell.psm1' -Recurse -ErrorAction SilentlyContinue | Sort-Object -Descending -ErrorAction SilentlyContinue | Select-Object -First 1 -ErrorAction SilentlyContinue)
            Pop-Location | Out-Null
        }

        if(!$nugetPsPsm1){
            throw ("nuget-powershell not found, and was not downloaded successfully. sorry.`n`tCheck your nuget.config (default path={0}) file to ensure that nuget.org is enabled.`n`tYou can also try changing the versionToInstall value.`n`tYou can file an issue at https://github.com/ligershark/nuget-powershell/issues." -f ("$env:APPDATA\NuGet\NuGet.config"))
        }

        $nugetPsPsm1
    }
}

<#
.SYNOPSIS
    This will return nuget from the $toolsDir. If it is not there then it
    will automatically be downloaded before the call completes.
#>
function Get-Nuget{
    [cmdletbinding()]
    param(
        $toolsDir = $toolsDir,
        $nugetDownloadUrl = $nugetDownloadUrl
    )
    process{
        if(!(Test-Path $toolsDir)){
            New-Item -Path $toolsDir -ItemType Directory | out-null
        }

        $nugetDestPath = Join-Path -Path $toolsDir -ChildPath nuget.exe

        if(!(Test-Path $nugetDestPath)){
            $nugetDir = ([System.IO.Path]::GetDirectoryName($nugetDestPath))
            if(!(Test-Path $nugetDir)){
                New-Item -Path $nugetDir -ItemType Directory | Out-Null
            }

            'Downloading nuget.exe' | Write-Verbose
            (New-Object System.Net.WebClient).DownloadFile($nugetDownloadUrl, $nugetDestPath) | Out-Null

            # double check that is was written to disk
            if(!(Test-Path $nugetDestPath)){
                throw 'unable to download nuget'
            }
        }

        # return the path of the file
        $nugetDestPath
    }
}

function Execute-CommandString{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [string[]]$command,

        [switch]
        $ignoreExitCode
    )
    process{
        foreach($cmdToExec in $command){
            'Executing command [{0}]' -f $cmdToExec | Write-Verbose
            cmd.exe /D /C $cmdToExec

            if(-not $ignoreExitCode -and ($LASTEXITCODE -ne 0)){
                $msg = ('The command [{0}] exited with code [{1}]' -f $cmdToExec, $LASTEXITCODE)
                throw $msg
            }
        }
    }
}


function Install-NuGetPowerShell {
    [cmdletbinding()]
    param()
    process{
        $modsFolder= Get-PsModulesPath
        $destFolder = (join-path $modsFolder 'nuget-powershell\')
        $destFile = (join-path $destFolder 'nuget-powershell.psm1')

        if(!(test-path $destFolder)){
            new-item -path $destFolder -ItemType Directory -Force | out-null
        }

        # this will download using nuget if its not in localappdata
        [System.IO.FileInfo]$nugetPsPsm1 = Get-NuGetPsPsm1

        # copy the folder to the modules folder
        # no need to recurse there are just a few files in the root
        Get-ChildItem $nugetPsPsm1.Directory | Copy-Item -Destination $destFolder

        if ((Get-ExecutionPolicy) -eq "Restricted"){
            Write-Warning @"
Your execution policy is $executionPolicy, this means you will not be able import or use any scripts including modules.
To fix this change your execution policy to something like RemoteSigned.

        PS> Set-ExecutionPolicy RemoteSigned

For more information execute:

        PS> Get-Help about_execution_policies

"@
        }
        else{
            Import-Module -Name $modsFolder\nuget-powershell\nuget-powershell.psd1 -DisableNameChecking -Force
        }

        "nuget-powershell is installed and ready to use" | Write-Output
    }
}


# begin script
Install-NuGetPowerShell