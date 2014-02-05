﻿<#

.SYNOPSIS  
	This module will help to use msbuild from powershell.
    When you import this module the msbuild alias will be set.
    You can see what command are available by executing the
    following command.

    Get-Command -Module psbuild

#>
[cmdletbinding()]
param()

# User settings go here
$global:PSBuildSettings = New-Object PSObject -Property @{
    EnableBuildLogging = $true
    # set this to false to prevent any messages being output from here via Write-Host
    BuildMessageEnabled = $true

    BuildMessageForegroundColor = [ConsoleColor]::Cyan
    BuildMessageBackgroundColor = [ConsoleColor]::DarkMagenta

    BuildMessageStrongForegroundColor = [ConsoleColor]::Yellow
    BuildMessageStrongBackgroundColor = [ConsoleColor]::DarkGreen

    LogDirectory = ('{0}\PSBuild\logs\' -f $env:LOCALAPPDATA)

    DefaultClp = '/clp:v=m'
}

#####################################################################
# Functions relating to msbuild.exe
#####################################################################

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
				        Sort-Object {$_.Name} | 
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
	This has two purposes:
        1. Create the msbuild alias
        2. Users can specific a specific msbuild.exe which should be used
#>
function Set-MSBuild{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        $msbuildPath = (Get-MSBuild)
    )

    process{
            'Updating msbuild alias to point to [{0}]' -f $msbuildPath | Write-Verbose
            Set-Alias msbuild $msbuildPath
                
            'Updating defalut msbuild.exe to point to [{0}]' -f $msbuildPath | Write-Verbose
            $script:defaultMSBuildPath = $msbuildPath
    }
}

<#
.SYNOPSIS
	Can be used to invoke MSBuild. If the msbuildPath parameter is not passed in
    the Get-MSBuild function will be called to determine the version of MSBuild
    which should be used.

.PARAMETER $projectsToBuild
    This is the parameter which determines which file(s) will be built. If a single
    value is passed in only that item will be processed. If multiple values are passed
    in then all the values will be processed.

    This will accept the pipeline value as well.

.PARAMETER extraArgs
    You can use this to pass in additional parameters to msbuild.exe. This can be
    one of these types:
        [string]
        [hashtable]
    These properties will be added to the end of the call to msbuild.exe so will
    take precedence over other properties.

.PARAMETER properties
    You can pass in a list of properties (hashtable) that should be applied when
    msbuild is called. Each of the items in the hashtable will be passed to
    msbuild.exe. The key of each entry is the name of the property and the
    value for the key will be the value for the msbuild property.

.PARAMETER targets
    The targets that should be passed to msbuild.exe. This can either be a 
    single value or multiple values. Each value will be conveted to a string.

.PARAMETER msbuildPath
    You can specify the specific msbuild.exe that should be used by passing
    in this value. If this is not specified then Get-MSBuild will be used
    to get the path to msbuild.exe.

.PARAMETER visualStudioVersion
    This will set the VisualStudioVersion MSBuild parameter. Typical values for this include:
        10.0
        11.0
        12.0

.PARAMETER nologo
    When set this passes the /nologo switch to msbuild.exe.

.PARAMETER preprocess
    When set passses the /preprocess switch to msbuild.exe.

.PARAMETER detailedSummary
    When set passses the /detailedSummary switch to msbuild.exe.

.PARAMETER defaultProperties
    This can be used to set default property values. A default property is the value that
    will be returned for a property if there is no value for that property defined.
    This is implemented by setting environment variables at the process level before
    msbuild.exe is invoked and re-setting them after it has completed.

.PARAMETER maxcpucount
    The value for the /maxcpucount (/m) parameter. If this is not provided '/m' will be used.
    If you want to disable this then pass in the value 1 to execute on one core.

.EXAMPLE
    Invoke-MSBuild C:\temp\msbuild\msbuild.proj

.EXAMPLE
    Invoke-MSBuild 'C:\temp\msbuild\msbuild.proj'

.EXAMPLE
    Invoke-MSBuild @('C:\temp\msbuild\proj1.proj';'C:\temp\msbuild\proj2.proj')

.EXAMPLE
    @('C:\temp\msbuild\proj1.proj';'C:\temp\msbuild\proj2.proj') | Invoke-MSBuild

.EXAMPLE
    @((get-item C:\temp\msbuild\proj1.proj);'C:\temp\msbuild\proj2.proj') | Invoke-MSBuild

.EXAMPLE
    Invoke-MSBuild C:\temp\msbuild\path.proj -properties (@{'foo'='bar';'visualstudioversion'='12.0'}) -extraArgs '/nologo'

.EXAMPLE
    $projects = @()
    $projects += (get-item C:\temp\msbuild\proj1.proj)
    $projects += 'C:\temp\msbuild\proj1.proj'
    Invoke-MSBuild $projects
    $projects | Invoke-MSBuild

.EXAMPLE
    Invoke-MSBuild .\ConsoleApplication1.csproj -visualStudioVersion 12.0  -nologo -preprocess | 
    Set-Content c:\temp\msbuild-pp.txt | 
    start c:\temp\msbuild-pp.txt

.EXAMPLE
    Invoke-MSBuild $defProps -defaultProperties @{'Configuration'='Release'}

#>
function Invoke-MSBuild{
    [cmdletbinding(SupportsShouldProcess=$True)]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [alias('proj')]
        $projectsToBuild,
        
        $msbuildPath = (Get-MSBuild),
        
        [alias('p')]
        [Hashtable]
        $properties,
        
        [alias('t')]
        $targets,
        
        [alias('vsv')]
        $visualStudioVersion,
     
        [alias("m")]
        [int]
        $maxcpucount,
        
        [alias('nl')]
        [switch]
        $nologo,

        [alias('pp')]
        [switch]
        $preprocess,

        [alias('ds')]
        [switch]
        $detailedSummary,

        [alias('dp')]
        $defaultProperties,

        [alias('clp')]
        $consoleLoggerParams = $global:PSBuildSettings.DefaultClp,

        [string]
        $extraArgs,

        [switch]
        $debugMode
    )

    begin{
        Add-Type -AssemblyName Microsoft.Build
        if($defaultProperties){
            $defaultProperties | PSBuildSet-TempVar
        }
    }

    end{
        if($defaultProperties){
            PSBuildReset-TempEnvVars
        }

        ">>>> Build completed you can use Get-PSBuildLog to see the log files" | Write-BuildMessage -strong
    }

    process{
        foreach($project in $projectsToBuild){
            $msbuildArgs = @()
            $msbuildArgs += ([string]$project)

            if(-not $properties){
                $properties = @{}
            }

            if($visualStudioVersion){
                $properties['VisualStudioVersion']=$visualStudioVersion
            }

            if($properties){
                foreach($key in $properties.Keys){
                    $value=$properties[$key]
                    if(!($value)){
                        continue;
                    }

                    $msbuildArgs += ('/p:{0}={1}' -f $key, $value)
                }
            }
            if($targets){
                foreach($target in $targets){
                    $msbuildArgs += ('/t:{0}' -f $target)
                }
            }

            if($nologo){
                $msbuildArgs += '/nologo'
            }

            if($preprocess){
                $msbuildArgs += '/preprocess'
            }

            if($detailedSummary){
                $msbuildArgs += '/detailedsummary'
            }

            if($maxcpucount){
                $msbuildArgs += ('/m:{0}' -f $maxcpucount)
            }
            else{
                $msbuildArgs += ('/m')
            }

            if($consoleLoggerParams){
                $msbuildArgs += $consoleLoggerParams
            }

            if($extraArgs){
                foreach($exArg in $extraArgs){
                    $msbuildArgs += $exArg
                }
            }

            if($global:PSBuildSettings.EnableBuildLogging){
                $projObj = (Get-Project -projectFile $project)
                $loggers = (Get-PSBuildLoggers -project $projObj)
                foreach($logger in $loggers){
                    $msbuildArgs += $logger
                }

                $global:PSBuildSettings.LogDirectory = (Get-PSBuildLogDirectory -project $projObj)
            }

            "Calling msbuild.exe with the following args: {0}" -f ($msbuildArgs -join ' ') | Write-BuildMessage
            
            if($pscmdlet.ShouldProcess("`n`tmsbuild.exe {0}" -f ($msbuildArgs -join ' '))){
                
                if(-not $debugMode){
                    & ((Get-MSBuild).FullName) $msbuildArgs
                }
                else{
                    # in debug mode we call msbuild using the APIs
                    Add-Type -AssemblyName Microsoft.Build
                    $globalProps = (PSBuild-ConverToDictionary -valueToConvert $properties)
                    $pc = (New-Object -TypeName Microsoft.Build.Evaluation.ProjectCollection)

                    $projectObj = $pc.LoadProject($project)
                    # todo: add loggers
                    $projectInstance = $projectObj.CreateProjectInstance()

                    $brdArgs = @($projectInstance, ([string[]](@()+$targets)), [Microsoft.Build.Execution.HostServices]$null, [Microsoft.Build.Execution.BuildRequestDataFlags]::ProvideProjectStateAfterBuild)
                    $brd = New-Object -TypeName Microsoft.Build.Execution.BuildRequestData -ArgumentList $brdArgs
                    
                    $buildResult = [Microsoft.Build.Execution.BuildManager]::DefaultBuildManager.Build(
                        (New-Object -TypeName Microsoft.Build.Execution.BuildParameters -ArgumentList $pc),
                        $brd)
                    $psbuildResult = New-PSBuildResult -buildResult $buildResult -projectInstance $projectInstance
                    
                    $script:lastDebugBuildResult = $psbuildResult
                    return $psbuildResult
                }
            }
        }
    }
}

<#
.SYNOPSIS
    When you call Invoke-MSBuild with the -debugMode flag an object is returned that is the build result.
    If you did not save this object you can use this method to reterive that last build result.

.EXAMPLE
    $lastResult = Get-PSBuildLastDebugBuildResult
#>
function Get-PSBuildLastDebugBuildResult{
    [cmdletbinding()]
    param()
    process{
        return $script:lastDebugBuildResult
    }
}

function New-PSBuildResult{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$true)]
        [Microsoft.Build.Execution.BuildResult]
        $buildResult,

        [Parameter(
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$true)]
        [Microsoft.Build.Execution.ProjectInstance]
        $projectInstance
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $result = New-Object PSObject -Property @{
            BuildResult = $buildResult

            ProjectInstance = $projectInstance
        }

        $result | Add-Member -MemberType ScriptMethod -Name EvalProperty -Value {
            [cmdletbinding()]
            param(
                [Parameter(
                    Mandatory=$true)]
                [string]
                $propName)
            if($this.ProjectInstance){
                $this.ProjectInstance.GetPropertyValue($propName)
            }
            else{
                'project is null'
            }
        }

        $result | Add-Member -MemberType ScriptMethod -Name EvalItem -Value {
            [cmdletbinding()]
            param(
                [Parameter(
                    Mandatory=$true)]
                [string]
                $propName)
            if($this.ProjectInstance){
                # todo: is there a better way to do this?
                $expressionToEval = ('@({0})' -f $propName)
                return $this.ProjectInstance.ExpandString($expressionToEval)
            }
            else{
                'project is null'
            }
        }

        $result | Add-Member -MemberType ScriptMethod ExpandString -Value {
            [cmdletbinding()]
            param(
                [Parameter(
                    Mandatory=$true)]
                [string]
                $unexpandedValue
            )
            process{
                if($this.ProjectInstance){
                    return $this.ProjectInstance.ExpandString($unexpandedValue)
                }
                else{
                    'project is null'
                }
            }
        }

        return $result
    }
}

# variables related to logging
$script:loggers = @()
<#
.SYNOPSIS  
	Will return the directory where psbuild will write msbuild log files to while invoking builds.

.EXAMPLE
    $logDir1 = Get-PSBuildLogDirectory

.EXAMPLE
    Get-Project 'C:\temp\msbuild\new\new.proj' | Get-PSBuildLogDirectory
#>
function Get-PSBuildLogDirectory{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            ValueFromPipeline=$true)]
        $project)
    process{
        if($global:PSBuildSettings.LogDirectory){
            $logDir = $global:PSBuildSettings.LogDirectory
        
            if($project){
                $itemResult = (Get-Item $project.Location.File)

                $projFileName = ((Get-Item $project.Location.File).Name)
                $logDir = (Join-Path -Path ($global:PSBuildSettings.LogDirectory) -ChildPath ('{0}\' -f $projFileName) )
            }

            # before returning ensure the log directory is created on disk
            if(!(Test-Path -Path $logDir) ){
                'Creating PSBuild log directory at [{0}]' -f $logDir | Write-Verbose
                mkdir $logDir | Out-Null
            }

            return $logDir
        }
        else{
            return $null   
        }
    }
}

<#
.SYNOPSIS  
	Used to set the directory where psbuild will keep msbuild log files.

.EXAMPLE
    Set-PSBuildLogDirectory -logDirectory 'C:\temp\logs2'
#>
function Set-PSBuildLogDirectory{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            ValueFromPipeline=$true)]
        [string]
        $logDirectory
    )
    process{
        if($logDirectory){
            # ensure that it ends with a slash
            if(!($logDirectory.EndsWith('\')) -and !($logDirectory.EndsWith('/'))){
                # add a trailing slash
                $logDirectory += '\'
            }
            $global:PSBuildSettings.LogDirectory = $logDirectory
        }
        else{
            # reset the log directory
            $global:PSBuildSettings.LogDirectory = ('{0}\PSBuild\logs\' -f $env:LOCALAPPDATA)
        }
    }
}

<#
.SYNOPSIS
	You can use this to access the last set of log files created.

.EXAMPLE
    Get-PSBuildLastLogs

.EXAMPLE
    How to copy the files to another folder and rename them.
    Get-PSBuildLastLogs | 
    ForEach-Object { 
        Copy-Item -Path $_.FullName -destination (Join-Path 'c:\temp\msbuild\sidewaffle\' ('sw-{0}' -f $_.Name)) }
#>
function Get-PSBuildLastLogs{
    [cmdletbinding()]
    param()
    process{
        if($global:PSBuildSettings.LogDirectory){
            return (Get-ChildItem $global:PSBuildSettings.LogDirectory | Where-Object {$_.PSIsContainer -eq $false} | Sort-Object LastWriteTime | Sort-Object Name)
        }
        else{
            '$global:PSBuildSettings.LogDirectory is empty, no recent logs' | Write-Verbose
        }
    }
}
<#
.SYNOPSIS  
	This will open the last log file in the default editor.
    Typically log files are written with the .log extension so whatever application is associated
    with the .log extension will open the log.

.EXAMPLE
    Open the last default log file (typically detailed verbosity)
    Open-PSBuildLog

.EXAMPLE
    Open-PSBuildLog -logIndex 1 (typically detailed verbosity)

.EXAMLPE
    Open the log files by getting the input from pipeline
    Get-PSBuildLog | Open-PSBuildLog
#>
function Open-PSBuildLog{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeLine=$true,Position=0)]
        [System.IO.FileSystemInfo[]]$logFiles = (Get-PSBuildLastLogs)[0],
        $logIndex = 0
    )
    process{
        foreach($file in $logFiles){
            start $file.FullName
        }
    }
}

<#
.SYNOPSIS  
	This will return the last log file. Typically there are two loggers attached
    a detailed logger and a diagnostic logger. By default this will return the 
    detailed log (0 index). You can use the logIndex parameter to access any log
    other than the default.

.OUTPUTS
    System.IO.FileInfo.
    Returns the FileInfo object for the log file specified.

.EXAMPLE
    Get-PSBuildLog

.EXAMPLE
    You can use this to see the last few lines of the log file easily.
    Get-PSBuildLog | Get-Content -Tail 100

.EXAMPLE
    If you want to open the log file in the default editor you can use this.
    Get-PSBuildLog | start

.EXAMPLE
    Get-PSBuildLog -logIndex 0 | Get-Content -Tail 50
#>
function Get-PSBuildLog{
    [cmdletbinding()]
    param(
        [Parameter(
            ValueFromPipeline=$true)]
        $logIndex = 0
    )
    process{
        return (Get-PSBuildLastLogs)[$logIndex]
    }
}

<#
.SYNOPSIS  
    This will return the logger strings for the next build for the given project (optional).
    The strings will have all place holders replaced with final values. You can pass the
    result of this call directly to msbuild.exe as parameters

.DESCRIPTION
    This will return the collection of logger strings fully expanded. The logger strings will
    be called with a string format with the following tokens.
        # {0} is the log directory
        # {1} is the name of the file being built
        # {2} is a timestamp property

Here are the default loggers that psbuild will use.
    @('/flp1:v=d;logfile={0}msbuild.d.{1}.{2}.log';'/flp1:v=diag;logfile={0}msbuild.diag.{1}.{2}.log')

.EXAMPLE
    $loggers1 = (Get-PSBuildLoggers -project $proj)
#>
function Get-PSBuildLoggers{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            ValueFromPipeline=$true)]
        $project
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        if(!($script:loggers)){
            Set-PSBuildLoggers
        }
        # we need to expand the logger strings before returning
            # {0} is the log directory
            # {1} is the name of the file being built
            # {2} is a timestamp property
        $loggersResult = @()
        foreach($loggerToAdd in $script:loggers){
            [string]$logDir = (Get-PSBuildLogDirectory -project $project)
            [string]$projName = if($project) {(get-item $project.Location.File).BaseName} else{''}
            [string]$dateStr = (Get-Date -format yyyy-MM-dd.h.m.s)
            $loggerStr = ($loggerToAdd -f $logDir, $projName,$dateStr)
            $loggersResult += $loggerStr
        }

        return $loggersResult
    }
}

<#
.SYNOPSIS  
    This will return the logger strings for the next build for the given project (optional).
    The strings will have all place holders replaced with final values. You can pass the
    result of this call directly to msbuild.exe as parameters

.DESCRIPTION
    This will return the collection of logger strings fully expanded. The logger strings will
    be called with a string format with the following tokens.
        # {0} is the log directory
        # {1} is the name of the file being built
        # {2} is a timestamp property

.EXAMPLE
    $customLoggers = @()
    $customLoggers += '/flp1:v=d;logfile={0}custom.d.{2}.log'
    $customLoggers += '/flp2:v=diag;logfile={0}custom.diag.{2}.log'

    Set-PSBuildLoggers -loggers $customLoggers
#>
function Set-PSBuildLoggers{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            ValueFromPipeline=$true)]
        $loggers
    )
    process{
        if($loggers){
            $script:loggers = $loggers
        }
        else{
            # reset loggers to the default value
            $script:loggers = @()
            # {0} is the log directory
            # {1} is the name of the file being built
            # {2} is a timestamp property
            $script:loggers += '/flp1:v=d;logfile={0}msbuild.detailed.log'
            $script:loggers += '/flp2:v=diag;logfile={0}msbuild.diagnostic.log'
        }
    }
}

<#
.SYNOPSIS
    This is a convience method to show the common MSBuild escape characters.
#>
function Get-MSBuildEscapeCharacters{
    [cmdletbinding()]
    param()
    process{
    $resultList = @()
    $resultList += @{'%'='%25'}
    $resultList += @{'$'='%24'}
    $resultList += @{'@'='%40'}
    $resultList += @{"'"='%27'}
    $resultList += @{';'='%3B'}
    $resultList += @{'?'='%3F'}
    $resultList += @{'*'='%2A'}
    $resultList += @{'('='%28'}
    $resultList += @{')'='%29'}
    $resultList += @{'"'='%22'}
        
    return $resultList
    }
}

#####################################################################
# Functions for interacting with MSBuild files.
#####################################################################

<#
.SYNOPSIS
	You can use this to create a new MSBuild project. If you specify a value for the
    $filePath parameter then the project file will saved to the specificed location.
    Otherwise an in-memory project file is created an returned to the caller.

.PARAMETER filePath
    An optional parameter. If passed in the project file will be saved to the given location.
#>

function New-Project{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1)]
        $filePath
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }

    process{
        $newProj = [Microsoft.Build.Construction.ProjectRootElement]::Create()

        if($filePath){
            Save-Project -project $newProj -filePath $filePath | Out-Null
        }

        return $newProj
    }
}

<#
.SYNOPSIS
	Can be used to save the MSBuild project to a file.
    After the project is saved $project will be returned.

.OUTPUTS
    Microsoft.Build.Construction.ProjectRootElement. Returns the object
    passed in the $project parameter.
#>
function Save-Project{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline = $true)]
        $project,

        [Parameter(
            Position=2,
            Mandatory=$true)]
        $filePath
    )

    begin{
        Add-Type -AssemblyName Microsoft.Build
    }

    process{
        # not working as expected, making $filePath mandatory again
        #if(-not $filePath){
        #    $filePath = $project.Location
        #}
        #'project.Location.File: [{0}]' -f $project.Location.File | Write-Host

        $fullPath = (Get-Fullpath -path $filePath)
        $project.Save([string]$fullPath)
        return $project
    }
}

<#
.SYNOPSIS
    Can be used to convert a relative path (i.e. .\project.proj) to a full path.
#>
function Get-Fullpath{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline = $true)]
        $path,

        $workingDir = ($pwd)
    )
    process{
        $fullPath = $path
        $oldPwd = $pwd

        Push-Location
        Set-Location $workingDir
        [Environment]::CurrentDirectory = $pwd
        $fullPath = ([System.IO.Path]::GetFullPath($path))
        
        Pop-Location
        [Environment]::CurrentDirectory = $oldPwd

        return $fullPath
    }
}

<#
.SYNOPSIS
    This can be used to open an MSBuild projcet file.
    The object returned is of type Microsoft.Build.Construction.ProjectRootElement.

    You can get the project either from a file or from an object. Regarding the from an existing
    object if the passed in is a ProjectRootElement it will be returned, and otherwise the
    value for $sourceObject.ContainingProject is returned. This is useful to enable
    pipeline continuations based on the return type of the previous function call.

.OUTPUTS
    [Microsoft.Build.Construction.ProjectRootElement]

.EXAMPLE
    Get-Project -projectFile 'C:\temp\msbuild\new\new.proj'

.EXAMPLE
    Get-Project -projectFile 'C:\temp\msbuild\new\new.proj' | 
        Find-PropertyGroup -labelValue second | 
        Remove-Property -name Configuration |
        Get-Project | 
        Save-Project -filePath $projFile
#>
function Get-Project{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1)]
        $projectFile,

        [Parameter(
            ValueFromPipeline=$true)]
        $sourceObject,
        
        $projectCollection = (New-Object Microsoft.Build.Evaluation.ProjectCollection)
    )
    begin{
        Add-Type -AssemblyName System.Core
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $project = $null
        if($projectFile){
            $fullPath = (Get-Fullpath $projectFile)
            $project = ([Microsoft.Build.Construction.ProjectRootElement]::Open([string]$fullPath,$projectCollection))
        }
        elseif($sourceObject -is [Microsoft.Build.Construction.ProjectRootElement]){
            $project = $sourceObject
        }
        else{
            $project = $sourceObject.ContainingProject
        }
        return $project
    }
}

#####################################################################
# Functions for manipulating MSBuild files
#####################################################################
<#
.SYNOPSIS
    Can be used to determine if the project file passed in has a specific import. 
    It can search for the import either by the value for the Label attribute or 
    the Project attribute. This is determined by the parameters passed in. 
    If both labelValue an projectValue are passed in then labelValue will take precedence.
#>
function Test-Import{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $project,
        $labelValue,
        $projectValue
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $foundImport = (Find-Import -project $project -labelValue $labelValue -projectValue $projectValue)

        $wasFound = $false
        if(-not $foundImport){
            $wasFound = $false
        }
        else{
            $wasFound = $true
        }

        return $wasFound
    }
}
<#
.SYNOPSIS
    Can be used to find imports in an MSBuild file. You can find by looking for the 
    Import by either the Label value or the value for Project. This is determined 
    by the parameters passed in. If both labelValue an projectValue are passed 
    in then labelValue will take precedence.
#>
function Find-Import{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $project,
        $labelValue,
        $projectValue,
        [switch]
        $stopOnFirstResult
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        "Looking for an import, label=[{0}], projet=[{0}]" -f $labelValue,$projectValue | Write-Verbose

        if(!($labelValue) -and !($projectValue)){
            "Both parameters labelValue and projectValue are empty. Not searching for imports." | Write-Warning
            return;
        }

        # $project can either be a ProjectRootElement object or a string
        [Microsoft.Build.Construction.ProjectRootElement]$realProject = $null
        if($project -is [Microsoft.Build.Construction.ProjectRootElement]){
            $realProject = $project
        }
        else{
            $realProject = (Get-Project -projectFile ([string]$project))
        }
        $foundImports = @()
        foreach($import in $realProject.Imports){
            [string]$projectStr = if($import.Project){$import.Project} else{''}
            [string]$labelStr = if($import.Label){$import.Label} else{''}

            $projectStr = $projectStr.Trim()
            $labelStr = $labelStr.Trim()

            if($labelValue){
                if([string]::Compare($labelValue,$labelStr,$true) -eq 0){
                    $foundImports += $import
                    "Found import via label" | Write-Verbose
                    if($stopOnFirstResult){
                        return $import
                    }
                }
            }
            elseif($projectValue){
                if([string]::Compare($projectValue,$projectStr,$true) -eq 0){
                    $foundImports += $import
                    "Found import via project" | Write-Verbose
                    if($stopOnFirstResult){
                        return $import
                    }
                }
            }
        }
        
        return $foundImports
    }
}

<#
.SYNOPSIS
    Used to add an import to a project. The project that will be imported
    is passed in $importProject. You can also optionally add a label to 
    the import as well as a condition.

.OUTPUTS
    Microsoft.Build.Construction.ProjectRootElement. Returns the object
    passed in the $project parameter.

.EXAMPLE
    Get-Project C:\temp\build.proj | 
        Add-Import -importProject 'c:\temp\import.targets' | 
        Save-Project -filePath 'C:\temp\build.proj'

.EXAMPLE
    Get-Project C:\temp\build.proj | 
        Add-Import -importProject 'c:\temp\import.targets'-importLabel 'Label' -importCondition ' ''$(VisualStudioVersion)''==''12.0'' ' | 
        Save-Project -filePath 'C:\temp\build.proj'
#>
function Add-Import{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [Microsoft.Build.Construction.ProjectRootElement]
        $project,
        [Parameter(
            Position=2,
            Mandatory=$true)]
        $importProject,
        $importLabel,
        $importCondition
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $importToAdd = $project.AddImport($importProject)
        
        if($importLabel){
            $importToAdd.Label = $importLabel
        }

        if($importCondition){
            $importToAdd.Condition = $importCondition
        }
        
        return $project
    }
}

<#
.SYNOPSIS
    This can be used to remove an import from the given MSBuild file. All of the matching
    imports will be removed from the project. If there are multiple imports with the
    same label/project value that matches what is provided they will all be removed.

.OUTPUTS
    Microsoft.Build.Construction.ProjectRootElement. Returns the object
    passed in the $project parameter.
#>
function Remove-Import{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [Microsoft.Build.Construction.ProjectRootElement]
        $project,
        $labelValue,
        $projectValue
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $importsToRemove = (Find-Import -project $project -labelValue $labelValue -projectValue $projectValue)
        foreach($importToRemove in $importsToRemove){
            'Removing import [Project=[{0}],Label=[{1}],Condition=[{2}]] from project [{3}]' -f `
                $importToRemove.Project, $importToRemove.Label, $importToRemove.Condition, $project.Location | Write-Verbose

            $importToRemove.Parent.RemoveChild($importToRemove) | Out-Null
        }

        return $project
    }
}

<#
.SYNOPSIS
    Can be used to find imports in an MSBuild file. You can find by looking for the 
    Import by either the Label value or the value for Project. This is determined 
    by the parameters passed in. If both labelValue an projectValue are passed 
    in then labelValue will take precedence.

.EXAMPLE
    Find-PropertyGroup -project (Get-Project 'C:\temp\msbuild\proj1.proj') -labelValue MyPropGroup

.EXAMPLE
    $projFilePath = 'C:\temp\msbuild\proj1.proj'
    $proj = (Get-Project $projFilePath)
    $pgs = Find-PropertyGroup -project $proj -labelValue MyPropGroup

.EXAMPLE
    Get-Project C:\temp\msbuild\proj1.proj | Find-PropertyGroup -labelValue MyPropGroup

.EXAMPLE
    @('C:\temp\msbuild\proj1.proj';'C:\temp\msbuild\proj2.proj') | Find-PropertyGroup -labelValue MyPropGroup
#>
function Find-PropertyGroup{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $project,

        [Parameter(
            Position=2,
            Mandatory=$true)]
        $labelValue,
        [switch]
        $stopOnFirstResult
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        "Looking for a PropertyGroup. Label=[{0}]" -f $labelValue | Write-Verbose

        # $project can either be a ProjectRootElement object or a string
        [Microsoft.Build.Construction.ProjectRootElement]$realProject = $null
        if($project -is [Microsoft.Build.Construction.ProjectRootElement]){
            $realProject = $project
        }
        else{
            $realProject = (Get-Project -projectFile ([string]$project))
        }

        $foundPgs = @()
        foreach($pg in $realProject.PropertyGroups){
            [string]$pgLabelStr = if($pg.Label){$pg.Label}else{''}
            $pgLabelStr = $pgLabelStr.Trim()

            if([string]::Compare($labelValue,$pgLabelStr,$true) -eq 0){
                $foundPgs += $pg
                'Found property group for label [{0}]' -f $labelValue | Write-Verbose
                if($stopOnFirstResult){
                    return $pg
                }
            }            
        }
        
        return $foundPgs
    }
}

<#
.SYNOPSIS
    Will remove PropertyGroup elements based on the Label attribute. If there is more than one
    matching property group than all the matching values will be removed.

.OUTPUTS
    Microsoft.Build.Construction.ProjectRootElement. Returns the object
    passed in the $project parameter.

.EXAMPLE
    Get-Project 'C:\temp\msbuild\new\new.proj' | Remove-PropertyGroup -labelValue MyPropGroup | Save-Project -filePath 'C:\temp\msbuild\new\new.proj'
#>
function Remove-PropertyGroup{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $project,

        [Parameter(
            Position=2,
            Mandatory=$true)]
        $labelValue
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $pgsToRemove = (Find-PropertyGroup -project $project -labelValue $labelValue)
        foreach($pg in $pgsToRemove){
            'Removing PropertyGroup with label [{0}]' -f $labelValue | Write-Verbose
            $pg.Parent.RemoveChild($pg)
        }
        return $project
    }
}

<#
.SYNOPSIS
    This will create a new PropertyGroup element in the given project. Optionally you can
    specify a label and condition for the element being created.

.OUTPUTS
    Microsoft.Build.Construction.ProjectRootElement. Returns the object
    passed in the $project parameter.

.EXAMPLE
    Get-Project 'C:\temp\msbuild\new\new.proj' | Remove-PropertyGroup -labelValue MyPropGroup | Save-Project -filePath 'C:\temp\msbuild\new\new.proj'
#>
function Add-PropertyGroup{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [Microsoft.Build.Construction.ProjectRootElement]
        $project,
        
        [Parameter(
            Position=2)]
        $label,

        [Parameter(
            Position=3)]
        $condition
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $pgToAdd = $project.AddPropertyGroup();

        if($label){
            $pgToAdd.Label = $label
        }

        if($condition){
            $pgToAdd.Condition = $condition
        }
        
        return $project
    }
}

<#
.SYNOPSIS
    Will return $true/$false indicating if there exists at least on PropertyGroup
    with the provided Label.

.OUTPUTS
    [bool]

.EXAMPLE
    Get-Project 'C:\temp\msbuild\new\new.proj' | Test-PropertyGroup -label Label1
#>
function Test-PropertyGroup{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $project,

        [Parameter(
            Position=2,
            Mandatory=$true)]
        $label
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $foundPg = (Find-PropertyGroup -project $project -label $label)

        $wasFound = $false
        if(-not $foundPg){
            $wasFound = $false
        }
        else{
            $wasFound = $true
        }

        return $wasFound
    }
}

<#
.SYNOPSIS
    Can be used to look for a property within a given container (typically either a Project or PropertyGroup)
    by either Name or Label. If both are provided the function will just search using Name.

.EXAMPLE
    Get-Project 'C:\temp\msbuild\new\new.proj' | Find-Property -label Label1

.EXAMPLE
    Get-Project 'C:\temp\msbuild\new\new.proj' | Find-PropertyGroup -labelValue first | Find-Property -label Label1
#>
function Find-Property{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]            
        $propertyContainer,

        $name,
        $label,
        [switch]
        $stopOnFirstResult
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        if(!($name) -and !($label)){
            'Both name and label parameters are empty. Not searching for property' | Write-Warning
            return
        }

        $foundProperties = @()
        foreach($prop in $propertyContainer.Properties){
            [string]$propName = $prop.Name
            [string]$propLabel = $prop.Label
            
            $propIsMatch = $false
            if($label){
                if([string]::Compare($propLabel,$label,$true) -eq 0){
                    $propIsMatch = $true                    
                }
            }
            elseif($name){
                if([string]::Compare($propName,$name,$true) -eq 0){
                    $propIsMatch = $true
                }
            }

            if($propIsMatch){
                'Found property with label [{0}]' -f $label | Write-Verbose
                $foundProperties += $prop
                if($stopOnFirstResult){
                    break
                }
            }
        }

        return $foundProperties
    }
}

<#
.SYNOPSIS
    Can be used to see if a given property exists. You can search by either Name or Label of the
    given property. The parameters will be passed to Find-Property and the rules for what is
    found or not is determined by that.

.OUTPUTS
    [bool]

.EXAMPLE
    You can search through the entire project by passing it in as the propertyContainer parameter
    
    Get-Project 'C:\temp\msbuild\new\new.proj' | Test-Property -label Label1

.EXAMPLE
    You can search through a specific PropertyGroup element by passing it in as the propertyContainer parameter

    Get-Project 'C:\temp\msbuild\new\new.proj' | Find-PropertyGroup -labelValue first | Test-Property -label Label1
#>
function Test-Property{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $propertyContainer,

        [Parameter(
            Position=2)]
        $name,

        [Parameter(
            Position=3)]
        $label
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $foundProp = (Find-Property -propertyContainer $propertyContainer -name $name -label $label -stopOnFirstResult)

        $wasFound = $false
        if(-not $foundProp){
            $wasFound = $false
        }
        else{
            $wasFound = $true
        }

        return $wasFound
    }
}

<#
.SYNOPSIS
    Can be used to remove a property. You can search for properties to be removed
    based on Name or Label. Find-Property will be used to locate the properties.
    The rules outlined there will apply here on items that will be removed.

.OUTPUTS
    Will return $propertyContainer

.EXAMPLE
    Get-Project -projectFile 'C:\temp\msbuild\new\new.proj' | Remove-Property -Label label1 | Save-Project -filePath $projFile

.EXAMPLE
    Get-Project -projectFile 'C:\temp\msbuild\new\new.proj' | Remove-Property -name Configuration | Save-Project -filePath $projFile

.EXAMPLE
    Get-Project -projectFile 'C:\temp\msbuild\new\new.proj' | 
        Find-PropertyGroup -labelValue second | 
        Remove-Property -name Configuration |
        Get-Project | 
        Save-Project -filePath $projFile
#>
function Remove-Property{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]            
        $propertyContainer,

        $name,
        $label
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $propsToRemove = (Find-Property -propertyContainer $propertyContainer -name $name -label $label)
        foreach($prop in $propsToRemove){
            'Removing Property name=[{0}],Label=[{1}]' -f $name, $label | Write-Verbose
            $prop.Parent.RemoveChild($prop)
        }

        return $propertyContainer
    }
}

<#
.SYNOPSIS
    This will add a property to the given project.
.OUTPUTS

.EXAMPLE
    Get-Project 'C:\temp\msbuild\new\new.proj' | Add-Property -name Configuration -value Debug | Get-Project | Save-Project -filePath 'C:\temp\msbuild\new\new.proj'

.EXAMPLE
    Add-Property -propertyContainer (Get-Project 'C:\temp\msbuild\new\new.proj') -name Configuration -value Debug | Get-Project | Save-Project -filePath 'C:\temp\msbuild\new\new.proj'

.EXAMPLE
    Add-Property -propertyContainer (Get-Project 'C:\temp\msbuild\new\new.proj') `
         -name Configuration -value Debug -label Custom -condition' ''$(VSV)''==''12.0'' ' | 
    Get-Project | 
    Save-Project -filePath 'C:\temp\msbuild\new\new.proj'
#>
function Add-Property{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $propertyContainer,
        
        [Parameter(
            Position=2,
            Mandatory=$true)]
        $name,

        [Parameter(
            Position=3)]
        $value,

        [Parameter(
            Position=4)]
        $label,

        [Parameter(
            Position=5)]
        $condition
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $propToAdd = $propertyContainer.AddProperty($name,$value)

        if($label){
            $propToAdd.Label = $label
        }

        if($condition){
            $propToAdd.Condition = $condition
        }
        
        return $propToAdd
    }
}

#####################################################################
# "Internal" functions
#####################################################################

function PSBuild-ConverToDictionary{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [hashtable]
        $valueToConvert
    )
    process{
        $valueToReturn = New-Object 'system.collections.generic.dictionary[[string],[string]]'

        if($valueToConvert){
            $valueToConvert.Keys | ForEach-Object {
                $valueToReturn.Add($_, ($valueToConvert[$_]))
            }
        }

        return $valueToReturn
    }
}

$script:envVarToRestore = @{}
function PSBuildSet-TempVar{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [hashtable]
        $envVars
    )
    process{
        foreach($key in $envVars.Keys){
            $oldValue = [environment]::GetEnvironmentVariable("$key","Process")
            $newValue = ($envVars[$key])
            $script:envVarToRestore[$key]=($oldValue)
            
            'Setting temp env var [{0}={1}]`tPrevious value:[{2}]' -f $key, $newValue, $oldValue | Write-Verbose
            [environment]::SetEnvironmentVariable("$key", $newValue,'Process')
        }
    }
}

function PSBuildReset-TempEnvVars{
    [cmdletbinding()]
    param()
    process{
        foreach($key in $script:envVarToRestore.Keys){
            $oldValue = [environment]::GetEnvironmentVariable("$key","Process")
            $newValue = ($script:envVarToRestore[$key])

            'Resetting temp env var [{0}={1}]`tPrevious value:[{2}]' -f $key, $newValue, $oldValue | Write-Verbose
            [environment]::SetEnvironmentVariable("$key",$newValue,'Process')
        }
    }
}

<#
.SYNOPSIS
    Function that can be called to write a build message.
    This is just a wrapper to Write-Host so that if we chose to replace that with something else
    it will be easy later.    
#>
function Write-BuildMessage{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            ValueFromPipeline=$true)]
        $message,

        [switch]
        $strong
    )
    process{
        if($global:PSBuildSettings.BuildMessageEnabled -and $message){
            $fgColor = $global:PSBuildSettings.BuildMessageForegroundColor
            $bColor = $global:PSBuildSettings.BuildMessageBackgroundColor
            if($strong){
                $fgColor = $global:PSBuildSettings.BuildMessageStrongForegroundColor
                $bColor = $global:PSBuildSettings.BuildMessageStrongBackgroundColor
            }

            $message | Write-Host -ForegroundColor $fgColor -BackgroundColor $bColor
        }
    }
}

Export-ModuleMember -function Get-*,Set-*,Invoke-*,Save-*,Test-*,Find-*,Add-*,Remove-*,Test-*,Open-*
#################################################################
# begin script portions
#################################################################

Add-Type -AssemblyName Microsoft.Build

[string]$script:defaultMSBuildPath = $null
[string]$script:VisualStudioVersion = $null
# call this once to ensure the alias is set
Get-MSBuild | Set-MSBuild