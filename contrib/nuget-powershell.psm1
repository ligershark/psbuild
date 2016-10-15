<#
.SYNOPSIS
    This module aimes to help similify consuming NuGet packages from PowerShell. To find the commands
    made available you can use.

    Get-Command -module nuget-powershell
#>

function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}
$scriptDir = ((Get-ScriptDirectory) + "\")

$global:NuGetPowerShellSettings = New-Object PSObject -Property @{
    cachePath = "$env:LOCALAPPDATA\LigerShark\nuget-ps\v1.1\"
    nugetDownloadUrl = 'http://nuget.org/nuget.exe'
}

function InternalGet-CachePath{
    [cmdletbinding()]
    param(
        $cachePath = $global:NuGetPowerShellSettings.cachePath
    )
    process{
        if(-not (Test-Path $cachePath) ){
            New-Item -ItemType Directory -Path $cachePath | Out-Null
        }

        Get-Item $cachePath
    }
}

<#
.SYNOPSIS
    This will return nuget from the $cachePath. If it is not there then it
    will automatically be downloaded before the call completes.
#>
function Get-Nuget{
    [cmdletbinding()]
    param(
        $toolsDir = (InternalGet-CachePath),
        $nugetDownloadUrl = $global:NuGetPowerShellSettings.nugetDownloadUrl
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

<#
.SYNOPSIS
    Updates nuget.exe to the latest and then returns the path to nuget.exe.
#>
function Update-NuGet{
    [cmdletbinding()]
    param()
    process{
        $cmdArgs = @('update','-self','-NonInteractive')

        $command = '"{0}" {1}' -f (Get-NuGet),($cmdArgs -join ' ')
        Execute-CommandString -command $command | Write-Verbose

        # return the path to nuget.exe
        Get-NuGet
    }
}

<#
.SYNOPSIS
    Used to execute a command line tool (i.e. nuget.exe) using cmd.exe. This is needed in
    some cases due to hanlding of special characters.

.EXAMPLE
    Execute-CommandString -command ('"{0}" {1}' -f (Get-NuGet),(@('install','psbuild') -join ' '))
    Calls nuget.exe install psbuild using cmd.exe

.EXAMPLE
    '"{0}" {1}' -f (Get-NuGet),(@('install','psbuild') -join ' ') | Execute-CommandString
    Calls nuget.exe install psbuild using cmd.exe

.EXAMPLE
    @('psbuild','packageweb') | % { """$(Get-NuGet)"" install $_ -prerelease"|Execute-CommandString}
    Calls 
        nuget.exe install psbuild -prerelease
        nuget.exe install packageweb -prerelease
#>
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

<#
.SYNOPSIS
    This will return the path to where the given NuGet package is installed. If the package
    is not in the local cache then it will automatically be downloaded. All interaction with
    nuget servers go through nuget.exe.

.PARAMETER name
    Name of the NuGet package to be installed. This is a mandatory argument.

.PARAMETER version
    Version of NuGet package to get. If this is not passed the latst version will be
    returned. That will result in a call to nuget.org (or other nugetUrl as specified).

.PARAMETER prerelease
    Pass this to get the prerelease version of the NuGet package.

.PARAMETER cachePath
    The directory where the package will be downloaded to. This is mostly an internal
    parameter but it can be used to redirect the location of the tools directory. 
    To override this globally you can use $global:NuGetPowerShellSettings.cachePath.

.PARAMETER nugetUrl
    You can use this to download the package from a different nuget feed.

.PARAMETER binpath
    When this is passed the folder where all packages are expanded into will be returned
    instead of the root directory.

.PARAMETER force
    Used to re-download the package from the remote nuget feed.

.EXAMPLE
    Get-NuGetPackage -name psbuild
    Gets the latest version of the psbuild nuget package wich is not a prerelease package

.EXAMPLE
    Get-NuGetPackage -name psbuild -prerelease
    Gets the latest version (including prerelase) of the psbuild nuget package.

.EXAMPLE
    Get-NuGetPackage psbuild -version 0.0.5
    Gets psbuild version 0.0.5

.EXAMPLE
    Get-NuGetPackage psbuild -version 0.0.6-beta5
    Gets psbuild version 0.0.6-beta5. When passing a value for version you don't need
    to pass -prerelease, it will be used by default on all calls when version is present.

.EXAMPLE
    Get-NuGetPackage psbuild -version 0.0.6-beta5 -nugetUrl https://staging.nuget.org
    Downloads psbuild version 0.0.6-beta5 fro staging.nuget.org
#>

function Get-NuGetPackage{
   [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$name,
        [Parameter(Position=1)] # later we can make this optional
        [string]$version,
        [Parameter(Position=2)]
        [switch]$prerelease,
        [Parameter(Position=3)]
        [System.IO.DirectoryInfo]$cachePath = (InternalGet-CachePath),

        [Parameter(Position=4)]
        [string]$nugetUrl = ('https://nuget.org/api/v2/'),

        [Parameter(Position=6)]
        [switch]$binpath,

        [Parameter(Position=7)]
        [switch]$force
    )
    process{
        [string]$foldername = $name
        if(-not ([string]::IsNullOrWhiteSpace($version))){
            $foldername = ('{0}.{1}' -f $name,$version)
        }

        [System.IO.DirectoryInfo]$expectedPath = (Join-Path $cachePath $foldername)

        if( -not (Test-Path $expectedPath) -or 
            ( (Get-ChildItem $expectedPath -Recurse -File).Length -le 0 ) -or 
            $force ) {

            # install to a temp dir
            [System.IO.DirectoryInfo]$tempfolder = (InternalGet-NewTempFolder)
            try{
                Push-Location | Out-Null
                Set-Location ($tempfolder.FullName) | Out-Null
                # install the nuget package here
                $cmdArgs = @('install',$name)

                if($version){
                    $cmdArgs += '-Version'
                    $cmdArgs += "$version"

                    $prerelease = $true
                }

                if($prerelease){
                    $cmdArgs += '-prerelease'
                }

                $cmdArgs += '-NonInteractive'

                if($nugetUrl -and !([string]::IsNullOrWhiteSpace($nugetUrl))){
                    $cmdArgs += "-source"
                    $cmdArgs += $nugetUrl
                }

                $nugetCommand = ('"{0}" {1}' -f (Get-Nuget), ($cmdArgs -join ' ' ))
                'Calling nuget to install a package with the following args. [{0}]' -f $nugetCommand | Write-Verbose
                [string[]]$nugetResult = (Execute-CommandString -command $nugetCommand)
                $nugetResult | Write-Verbose
                
                # combine results into a single __bin folder
                $expbinpath = (Join-Path $tempfolder '__bin')
                New-Item -Path $expbinpath -ItemType Directory | Write-Verbose
                # copy lib folder to bin\
                Get-ChildItem $tempfolder -Directory | InternalGet-LibFolderToUse | Get-ChildItem | Copy-Item -Destination $expbinpath -Recurse -ErrorAction SilentlyContinue | Write-Verbose
                # copy tools folder to __bin\
                Get-ChildItem $tempfolder 'tools' -Directory -Recurse | Get-ChildItem -Exclude *.ps*1 | Copy-Item -Destination $expbinpath -Recurse -ErrorAction SilentlyContinue | Write-Verbose

                # copy files to the dest folder
                if($force -and (Test-Path $expectedPath)){
                    # delete the folder and re-install
                    Remove-Item $expectedPath -Recurse | Write-Verbose
                }

                if(-not (test-path $expectedPath)){
                    New-Item -ItemType Directory -Path $expectedPath | Write-Verbose
                }

                foreach($pathtomove in (Get-ChildItem $tempfolder -Directory)){
                    [System.IO.DirectoryInfo]$dest = (Join-Path $expectedPath $pathtomove.BaseName)
                    if(-not (Test-Path $dest.FullName)){
                        Move-Item $pathtomove.FullName $expectedPath | Write-Verbose
                    }
                }
            }
            finally{
                Pop-Location | Out-Null
                # delete the temp folder
                if( -not ([string]::IsNullOrWhiteSpace($tempfolder) ) -and (Test-Path $tempfolder) ){
                    Remove-Item -Path $tempfolder -Recurse -ErrorAction SilentlyContinue | Write-Verbose
                }
            }
        }

        # return the full path
        if($binpath){
            (Get-Item (Join-Path $expectedPath '__bin')).FullName
        }
        else{
            $expectedPath.FullName
        }
    }
}

function InternalGet-NewTempFolder{
    [cmdletbinding()]
    param(
        [System.IO.DirectoryInfo]$tempFolder = ([System.IO.Path]::GetTempPath())
    )
    process{
        $foldername = [Guid]::NewGuid()
        New-Item -ItemType Directory -Path (Join-Path $tempFolder $foldername) | Write-Verbose
        Get-Item -Path (Join-Path $tempFolder $foldername)
    }
}

function InternalGet-LibFolderToUse{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [System.IO.DirectoryInfo[]]$packageInstallPath
    )
    process{
        $libtocheck = @('lib\net45','lib\45','lib\net40','lib\40','lib\net35','lib\35','lib\net30','lib\30','lib\net20','20','lib\11','11','lib')
        foreach($pkgPath in $packageInstallPath){
            try{
                $pkgFullPath = $pkgPath.FullName
                Push-Location | Out-Null
                Set-Location $pkgFullPath | out-null
                $libfolder = $null
                foreach($lib in $libtocheck){
                    if(Test-Path (Join-Path $pkgFullPath $lib)){
                        $libfolder = (Get-Item (Join-Path $pkgFullPath $lib)).FullName
                        break
                    }
                }

                $libfolder
            }
            finally{
                Pop-Location | Out-Null
            }
        }
    }
}

<#
.SYNOPSIS
Returns the name (including version number) of the nuget package installed from the
nuget.exe results when calling nuget.exe install.
#>
function InternalGet-PackagePathFromNuGetOutput{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$nugetOutput
    )
    process{
        if(!([string]::IsNullOrWhiteSpace($nugetOutput))){
            ([regex]"'[^']*'").match((($nugetOutput -split "`n")[-1])).groups[0].value.TrimStart("'").TrimEnd("'").Replace(' ','.')
        }
        else{
            throw 'nugetOutput parameter is null or empty'
        }
    }
}

<#
.SYNOPSIS
    When this method is called all files in the given nuget package maching *.psm1 in the tools
    folder will automatically be imported using Import-Module.

.EXAMPLE
    Load-ModuleFromNuGetPackage -name psbuild
    Loads the psbuild module from the latest psbuild nuget package (non-prerelease).

.EXAMPLE
    Load-ModuleFromNuGetPackage -name psbuild -prerelease
    Loads the psbuild module from the latest psbuild nuget package (including prerelease).

.EXAMPLE
    Load-ModuleFromNuGetPackage -name psbuild -prerelease -force
    Loads the psbuild module from the latest psbuild nuget package (including prerelease), and the package
    will be re-dowloaded instead of the cached version.
#>
function Load-ModuleFromNuGetPackage{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        $name,

        [Parameter(Position=1)]
        $version,

        [Parameter(Position=2)]
        [switch]$prerelease,

        [Parameter(Position=3)]
        $cachePath = (InternalGet-CachePath),

        [Parameter(Position=4)]
        $nugetUrl = ('https://nuget.org/api/v2/'),

        [Parameter(Position=5)]
        [switch]$force
    )
    process{
        $pkgDir = Get-NuGetPackage -name $name -version $version -prerelease:$prerelease -nugetUrl $nugetUrl -force:$force -binpath

        $modules = (Get-ChildItem ("$pkgDir\tools") '*.psm1' -ErrorAction SilentlyContinue)
        foreach($module in $modules){
            $moduleFile = $module.FullName
            $moduleName = $module.BaseName

            if(Get-Module $moduleName){
                Remove-Module $moduleName | out-null
            }
            'Loading module from [{0}]' -f $moduleFile | Write-Verbose
            Import-Module $moduleFile -DisableNameChecking -Global -Force
        }
    }
}

function Get-NuGetPackageExpectedPath{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $name,
        [Parameter(Mandatory=$true,Position=1)] # later we can make this optional
        $version,
        [Parameter(Position=2)]
        $cachePath = (InternalGet-CachePath),
        [Parameter(Position=3)]
        [switch]$expandedPath
    )
    process{
        $pathToFoundPkgFolder = $null
        $cachePath=(get-item $cachePath).FullName

        if(!$expandedPath){
            (join-path $cachePath (('{0}.{1}' -f $name, $version)))
        }
        else{
            (join-path $cachePath (('expanded\{0}{1}\{0}.{1}' -f $name, $version)))
        }
    }
}

function Get-NuGetPowerShellVersion{
    param()
    process{
        New-Object -TypeName 'system.version' -ArgumentList '0.2.5.1'
    }
}

if(!$env:IsDeveloperMachine){
    Export-ModuleMember -function Get-*,Set-*,Invoke-*,Save-*,Test-*,Find-*,Add-*,Remove-*,Test-*,Open-*,New-*,Execute-*,Update-*,Load-*
}
else{
    # you can set the env var to expose all functions to importer. easy for development.
    # this is required for pester testing
    Export-ModuleMember -function *
}
