[cmdletbinding(DefaultParameterSetName='build')]
param(
    [Parameter(ParameterSetName='build',Position=0)]
    [switch]$build,
    
    [Parameter(ParameterSetName='setversion',Position=0)]
    [switch]$setversion,

    [Parameter(ParameterSetName='getversion',Position=0)]
    [switch]$getversion,

    # build parameters
    [Parameter(ParameterSetName='build',Position=1)]
    [switch]$CleanOutputFolder,

    [Parameter(ParameterSetName='build',Position=2)]
    [switch]$publishToNuget,

    [Parameter(ParameterSetName='build',Position=3)]
    [string]$nugetApiKey = ($env:NuGetApiKey),

    [Parameter(ParameterSetName='build',Position=4)]
    [switch]$noTests,

    # setversion parameters
    [Parameter(ParameterSetName='setversion',Position=1,Mandatory=$true)]
    [string]$newversion,

    [Parameter(ParameterSetName='setversion',Position=2)]
    [string]$oldversion,

    [Parameter(ParameterSetName='openciwebsite',Position=0)]
    [Alias('openci')]
    [switch]$openciwebsite,

    [Parameter(ParameterSetName='updateDeps',Position=0)]
    [switch]$updateDeps
)
 
 function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDir = ((Get-ScriptDirectory) + "\")
[string]$script:defaultMSBuildPath=$null
<#
.SYNOPSIS  
	This will return the path to msbuild.exe. If the path has not yet been set
	then the highest installed version of msbuild.exe will be returned.
#>
function Get-MSBuildExe{
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
        $toolsDir = ("$env:LOCALAPPDATA\LigerShark\tools.01\"),

        $nugetDownloadUrl = 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe'
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
$script:pkgDownloaderEnabled = $false
function Enable-PackageDownloader{
    [cmdletbinding()]
    param(
        $toolsDir = "$env:LOCALAPPDATA\LigerShark\tools.01\package-downloader\v1\",
        $pkgDownloaderDownloadUrl = 'http://go.microsoft.com/fwlink/?LinkId=524325') # package-downloader.psm1
    process{

        if(!($script:pkgDownloaderEnabled)){
            if(get-module package-downloader){
                remove-module package-downloader | Out-Null
            }

            if(!(get-module package-downloader)){
                if(!(Test-Path $toolsDir)){ New-Item -Path $toolsDir -ItemType Directory -WhatIf:$false }

                $expectedPath = (Join-Path ($toolsDir) 'package-downloader.psm1')
                if(!(Test-Path $expectedPath)){
                    'Downloading [{0}] to [{1}]' -f $pkgDownloaderDownloadUrl,$expectedPath | Write-Verbose
                    (New-Object System.Net.WebClient).DownloadFile($pkgDownloaderDownloadUrl, $expectedPath)
                }

                if(!$expectedPath){throw ('Unable to download package-downloader.psm1')}

                'importing module [{0}]' -f $expectedPath | Write-Output
                Import-Module $expectedPath -DisableNameChecking -Force
                $script:pkgDownloaderEnabled = $true
            }
        }
    }
}

function Update-FilesWithCommitId{
    [cmdletbinding()]
    param(
        [string]$commitId = ($env:APPVEYOR_REPO_COMMIT),

        [Parameter(Position=2)]
        [string]$filereplacerVersion = '0.2.0-beta'
    )
    process{
        if(![string]::IsNullOrWhiteSpace($commitId)){
            'Updating commitId from [{0}] to [{1}]' -f '$(COMMIT_ID)',$commitId | Write-Verbose

            Enable-PackageDownloader
            'trying to load file replacer' | Write-Verbose
            Enable-NuGetModule -name 'file-replacer' -version $filereplacerVersion

            $folder = $scriptDir
            $include = '*.nuspec'
            # In case the script is in the same folder as the files you are replacing add it to the exclude list
            $exclude = "$($MyInvocation.MyCommand.Name);"
            $replacements = @{
                '$(COMMIT_ID)'="$commitId"
            }
            Replace-TextInFolder -folder $folder -include $include -exclude $exclude -replacements $replacements | Write-Verbose
            'Replacement complete' | Write-Verbose
        }
    }
}

function SetVersion{
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

        Enable-PackageDownloader
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

        # update the .psd1 file
        $replacements = @{
            ($oldversion.Replace('-beta','.1'))=($newversion.Replace('-beta','.1'))
        }
        Replace-TextInFolder -folder $folder -include '*.ps*1' -exclude $exclude -replacements $replacements | Write-Verbose
        'Replacement complete' | Write-Verbose
    }
}

function PublishNuGetPackage{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$nugetPackages,

        [Parameter(Mandatory=$true)]
        $nugetApiKey
    )
    process{
        foreach($nugetPackage in $nugetPackages){
            $pkgPath = (get-item $nugetPackage).FullName
            $cmdArgs = @('push',$pkgPath,'-ApiKey',$nugetApiKey,'-Source','https://api.nuget.org/v3/index.json','-NonInteractive')

            'Publishing nuget package with the following args: [nuget.exe {0}]' -f ($cmdArgs -join ' ') | Write-Verbose
            &(Get-Nuget) $cmdArgs
                
            if($? -eq $false){
                "Upload of [{0}] to appveyor failed; Failing Build..." -f $pkgPath | Write-Error
                exit 1
            }
        }
    }
}


function Clean-OutputFolder{
    [cmdletbinding()]
    param()
    process{
        $outputFolder = Get-OutputRoot

        if(Test-Path $outputFolder){
            'Deleting output folder [{0}]' -f $outputFolder | Write-Host
            Remove-Item $outputFolder -Recurse -Force
        }

    }
}

function LoadPester{
    [cmdletbinding()]
    param(
        $pesterDir = (resolve-path (Join-Path $scriptDir 'contrib\pester\'))
    )
    process{
        if(!(Get-Module pester)){
            if($env:PesterDir -and (test-path $env:PesterDir)){
                $pesterDir = $env:PesterDir
            }

            if(!(Test-Path $pesterDir)){
                throw ('Pester dir not found at [{0}]' -f $pesterDir)
            }
            $modFile = (Join-Path $pesterDir 'Pester.psm1')
            'Loading pester from [{0}]' -f $modFile | Write-Verbose
            Import-Module (Join-Path $pesterDir 'Pester.psm1')
        }
    }
}

function Get-OutputRoot{
    [cmdletbinding()]
    param()
    process{
        Join-Path $scriptDir "OutputRoot"
    }
}

function Run-Tests{
    [cmdletbinding()]
    param(
        $testDirectory = (join-path $scriptDir tests)
    )
    begin{ 
        LoadPester
        $previousToolsDir = $env:PSBuildToolsDir
        $env:PSBuildToolsDir = (Join-Path (Get-OutputRoot) 'PSBuild\')
    }
    process{
        # go to the tests directory and run pester
        push-location
        set-location $testDirectory
     
        $pesterArgs = @{
            '-PassThru' = $true
        }
        if($env:ExitOnPesterFail -eq $true){
            $pesterArgs.Add('-EnableExit',$true)
        }
        if($env:PesterEnableCodeCoverage -eq $true){
            $pesterArgs.Add('-CodeCoverage','..\src\psbuild.psm1')
        }

        $pesterResult = Invoke-Pester @pesterArgs
        pop-location

        if($pesterResult.FailedCount -gt 0){
            throw ('Failed test cases: {0}' -f $pesterResult.FailedCount)
        }
    }
    end{
        $env:PSBuildToolsDir = $previousToolsDir
    }
}

function Build{
    [cmdletbinding()]
    param()
    process{
        if($publishToNuget){ $CleanOutputFolder = $true }

        if($CleanOutputFolder){
            Clean-OutputFolder
        }

        Update-FilesWithCommitId

        $projFilePath = get-item (Join-Path $scriptDir 'psbuild.proj')

        $msbuildArgs = @()
        $msbuildArgs += $projFilePath.FullName
        $msbuildArgs += '/p:Configuration=Release'
        $msbuildArgs += '/p:VisualStudioVersion=12.0'
        $msbuildArgs += '/flp1:v=d;logfile=msbuild.d.log'
        $msbuildArgs += '/flp2:v=diag;logfile=msbuild.diag.log'
        $msbuildArgs += '/m'

        & ((Get-MSBuildExe).FullName) $msbuildArgs

        if(-not ($noTests)){
            Run-Tests
        }

        # publish to nuget if selected
        if($publishToNuget){
            (Get-ChildItem -Path (Get-OutputRoot) 'psbuild*.nupkg').FullName | PublishNuGetPackage -nugetApiKey $nugetApiKey
        }
    }
}
<#
.SYNOPSIS
This will update the contents of the contrib folder for nuget-powershell and file-replacer
#>
function Update-Dependencies{
    [cmdletbinding()]
    param(
        [string]$destDir
    )
    process{

        if([string]::IsNullOrWhiteSpace($destDir)){
            $destDir = (Join-Path $scriptDir 'contrib')
        }

        # create a new temp folder
        $tempFolder = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psbuild\build\{0}' -f [System.IO.Path]::GetRandomFileName().Replace('.','')))
        New-Item -Path $tempFolder -ItemType Directory
        # restore the packages to that folder
        'Getting latest file-replacer' | Write-Output
        $fpPath = Get-NuGetPackage -name 'file-replacer' -prerelease -cachePath $tempFolder -binpath
        
        'Getting latest nuget-powershell' | Write-Output
        $npPath = Get-NuGetPackage -name 'nuget-powershell' -prerelease -cachePath $tempFolder -binpath

        #move the files to the dest dir
        Copy-Item -path "$fpPath\*.ps*1" -Destination "$destDir"
        Copy-Item -path "$fpPath\*.dll" -Destination "$destDir"

        Copy-Item -path "$npPath\*.ps*1" -Destination "$destDir"
    }
}

function OpenCiWebsite{
    [cmdletbinding()]
    param()
    process{
        start 'https://ci.appveyor.com/project/sayedihashimi/psbuild'
    }
}

if(!$build -and !$setversion -and !$getversion -and !$openciwebsite -and !$updateDeps){
    $build = $true
}

try{
    if($build){ Build }
    elseif($setversion){ SetVersion -newversion $newversion }
    elseif($getversion){ GetExistingVersion | Write-Output }
    elseif($updateDeps){ Update-Dependencies | Write-Output}
    elseif($openciwebsite){ OpenCiWebsite }    
    else{
        $cmds = @('-build','-setversion')
        'Command not found or empty, please pass in one of the following [{0}]' -f ($cmds -join ' ') | Write-Error
    }
}
catch{
    "Build failed with an exception:`n{0}" -f ($_.Exception.Message) |  Write-Error
    exit 1
}
