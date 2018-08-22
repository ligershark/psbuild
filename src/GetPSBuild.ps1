[cmdletbinding()]
param(
    $versionToInstall = '1.2.0-beta',
    $appDataDir = ("$env:LOCALAPPDATA\LigerShark\psbuild\"),
    $nugetDownloadUrl = 'http://nuget.org/nuget.exe',
    $nugetSource = 'https://www.nuget.org/api/v2/'
)

function GetPsModulesPath{
    [cmdletbinding()]
    param()
    process{
        $Destination = $null
        if(Test-Path 'Env:PSModulePath'){
            $ModulePaths = @($Env:PSModulePath -split ';')
    
            $ExpectedUserModulePath = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath WindowsPowerShell\Modules
            $Destination = $ModulePaths | Where-Object { $_ -eq $ExpectedUserModulePath} | Select-Object -First 1
            if (-not $Destination) {
                $Destination = $ModulePaths | Select-Object -Index 0
            }
        }
        $Destination
    }
}

# originally based off of the scrit at http://psget.net/GetPsGet.ps1
function Install-PSBuild {
    # this will download using nuget if its not in %temp%
    [System.IO.FileInfo]$psbPsm1File = GetPsBuildPsm1
    if($psbPsm1File -eq $null){
        throw ('Unable to locate psbuild.psm1 file as expected')
    }
    [System.IO.FileInfo]$modsFolder = $null
    try{
        $modsFolder= GetPsModulesPath
    }
    catch{
        'Error installing psbuld to modules folder: {0}' | Write-Error
    }
    $moduleFile = $null
    if(-not [string]::IsNullOrWhiteSpace($modsFolder)){
        $destFolder = (join-path $modsFolder.FullName 'psbuild\')
        $destFile = (join-path $destFolder 'psbuild.psm1')

        if(!(test-path $destFolder)){
            new-item -path $destFolder -ItemType Directory -Force | out-null
        }
        Copy-Item -Path "$($psbPsm1File.Directory.FullName)\*"  -Destination $destFolder -Recurse
        $moduleFile = $destFile
    }
    else{
        $moduleFile = Join-Path $psbPsm1File.Directory.FullName 'psbuild.psd1'
    }

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
        Import-Module -Name $moduleFile -DisableNameChecking -Force
    }

    Write-Output "psbuild is installed and ready to use"
    Write-Output @"
USAGE:
    PS> Invoke-MSBuild 'C:\temp\msbuild\msbuild.proj'
    PS> Invoke-MSBuild C:\temp\msbuild\path.proj -properties (@{'OutputPath'='c:\ouput\';'visualstudioversion'='12.0'}) -extraArgs '/nologo'

For more details:
    get-help Invoke-MSBuild
Or visit http://msbuildbook.com/psbuild
"@
}

<#
.SYNOPSIS
    If nuget is in the tools
    folder then it will be downloaded there.
#>
function Get-Nuget{
    [cmdletbinding()]
    param(
        $toolsDir = $appDataDir,
        $nugetDownloadUrl = 'http://nuget.org/nuget.exe'
    )
    process{
        $nugetDestPath = Join-Path -Path $toolsDir -ChildPath nuget.exe
        
        if(!(Test-Path $nugetDestPath)){
            $nugetDir = ([System.IO.Path]::GetDirectoryName($nugetDestPath))
            if(!(Test-Path $nugetDir)){
                New-Item -Path $nugetDir -ItemType Directory | Out-Null
            }

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

function Invoke-CommandString{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [string[]]$command,

        [switch]
        $ignoreErrors
    )
    process{
        foreach($cmdToExec in $command){
            'Executing command [{0}]' -f $cmdToExec | Write-Verbose

            cmd.exe /D /C $cmdToExec | Out-Null

            if(-not $ignoreErrors -and ($LASTEXITCODE -ne 0)){
                $msg = ('The command [{0}] exited with code [{1}]' -f $cmdToExec, $LASTEXITCODE)
                throw $msg
            }
        }
    }
}

# see if the particular version is installed under %temp%
function GetPsBuildPsm1{
    [cmdletbinding()]
    param(
        $toolsDir = $appDataDir,
        $nugetDownloadUrl = 'http://nuget.org/nuget.exe'
    )
    process{
        if(!(Test-Path $toolsDir)){
            New-Item -Path $toolsDir -ItemType Directory | out-null
        }

        $psbuildPsm1 = (Get-ChildItem -Path "$toolsDir\psbuild.$versionToInstall" -Include 'psbuild.psm1' -Recurse -ErrorAction SilentlyContinue | Sort-Object -Descending -ErrorAction SilentlyContinue | Select-Object -First 1 -ErrorAction SilentlyContinue)

        if(!$psbuildPsm1){
            try{
                Push-Location | Out-Null
                Set-Location ((Resolve-Path $toolsDir).ToString()) | Out-Null
                'Downloading psbuild to the toolsDir' | Write-Verbose
                # nuget install psbuild -Version 0.0.3-beta -Prerelease -OutputDirectory C:\temp\nuget\out\
                $cmdArgs = @('install','psbuild','-Version',$versionToInstall,'-Prerelease','-source',$nugetSource)

                $nugetPath = (Get-Nuget -toolsDir $toolsDir -nugetDownloadUrl $nugetDownloadUrl)
                'Calling nuget to install psbuild with the following args. [{0} {1}]' -f $nugetPath, ($cmdArgs -join ' ') | Write-Verbose

                $command = '"{0}" {1}' -f $nugetPath,($cmdArgs -join ' ')
                $command | Invoke-CommandString | Out-Null

                $psbuildPsm1 = (Get-ChildItem -Path "$toolsDir\psbuild.$versionToInstall" -Include 'psbuild.psm1' -Recurse | Sort-Object -Descending | Select-Object -First 1)
            }
            finally{
                Pop-Location | Out-Null
            }
        }

        if(!$psbuildPsm1){ 
            throw ("psbuild not found, and was not downloaded successfully. sorry.`n`tCheck your nuget.config (default path={0}) file to ensure that nuget.org is enabled.`n`tYou can also try changing the versionToInstall value.`n`tYou can file an issue at https://github.com/ligershark/psbuild/issues." -f ("$env:APPDATA\NuGet\NuGet.config"))
        }

        $psbuildPsm1
    }
}

function Repair-ToolsDir{
    [CmdletBinding()]
    param($toolsDir = $appDataDir)
    process{
        $systemDir = [Environment]::GetFolderPath('System')
        if ($toolsDir.StartsWith($systemDir) -and ($PSVersionTable.CLRVersion.Major -ge 4))
        {
            $sysWowDir = [Environment]::GetFolderPath('SystemX86')
            $toolsDir = $toolsDir.Replace($systemDir, $sysWowDir)
        }

        $toolsDir
    }
}

$appDataDir = Repair-ToolsDir $appDataDir

Install-PSBuild
