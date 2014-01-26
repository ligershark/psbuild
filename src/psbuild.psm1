<#

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
$global:PSBuildPromptSettings = New-Object PSObject -Property @{
    # set this to false to prevent any messages being output from here via Write-Host
    BuildMessageEnabled = $true

    BuildMessageForegroundColor = [ConsoleColor]::Cyan
    BuildMessageBackgroundColor = $host.UI.RawUI.BackgroundColor

    BuildMessageStrongForegroundColor = [ConsoleColor]::Yellow
    BuildMessageStrongBackgroundColor = [ConsoleColor]::DarkGreen

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
	    $path = $defaultMSBuildPath

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

#>
function Invoke-MSBuild{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
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
        
        [switch]
        $nologo,

        [alias('pp')]
        [switch]
        $preprocess,

        [alias('ds')]
        [switch]
        $detailedSummary,

        [string]
        $extraArgs,

        [switch]
        $noLogging
    )

    begin{
        Add-Type -AssemblyName Microsoft.Build
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

            if($extraArgs){
                foreach($exArg in $extraArgs){
                    $msbuildArgs += $exArg
                }
            }
        
            if(-not $noLogging){
                # $script:lastLogDirectory = (Get-PSBuildLogDirectory -project
                $projObj = (Get-Project -projectFile $project)
                $loggers = (Get-PSBuildLoggers -project $projObj)
                foreach($logger in $loggers){
                    $msbuildArgs += $logger
                }

                $script:lastLogDirectory = (Get-PSBuildLogDirectory -project $projObj)
            }

            "Calling msbuild.exe with the following args: {0}" -f (($msbuildArgs -join ' ')) | Write-BuildMessage
            & ((Get-MSBuild).FullName) $msbuildArgs

            ">>>> Build completed you can use Get-PSBuildLastLogs to see the log files`n" | Write-BuildMessage -strong
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
        if($global:PSBuildPromptSettings.BuildMessageEnabled -and $message){
            $fgColor = $global:PSBuildPromptSettings.BuildMessageForegroundColor
            $bColor = $global:PSBuildPromptSettings.BuildMessageBackgroundColor
            if($strong){
                $fgColor = $global:PSBuildPromptSettings.BuildMessageStrongForegroundColor
                $bColor = $global:PSBuildPromptSettings.BuildMessageStrongBackgroundColor
            }

            $message | Write-Host -ForegroundColor $fgColor -BackgroundColor $bColor
        }
    }
}

# variables related to logging
$script:logDirectory = ('{0}\PSBuild\logs\' -f $env:LOCALAPPDATA)
$script:loggers = @()
$script:lastLogDirectory
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
        if($script:logDirectory){
            $logDir = $script:logDirectory
        
            if($project){
                $itemResult = (Get-Item $project.Location.File)

                $projFileName = ((Get-Item $project.Location.File).Name)
                $logDir = (Join-Path -Path $script:logDirectory -ChildPath ('{0}\' -f $projFileName) )
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
            $script:logDirectory = $logDirectory
        }
        else{
            # reset the log directory
            $script:logDirectory = ('{0}\PSBuild\logs\' -f $env:LOCALAPPDATA)
        }
    }
}

<#
.SYNOPSIS  
	You can use this to access the last set of log files created.

.EXAMPLE
    Get-PSBuildLastLogs
#>
function Get-PSBuildLastLogs{
    [cmdletbinding()]
    param()
    process{
        if($script:lastLogDirectory){
            return (Get-ChildItem $script:lastLogDirectory | Sort-Object LastWriteTime)
        }
        else{
            '$script:lastLogDirectory is empty, no recent logs' | Write-Verbose
        }
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


Export-ModuleMember -function *
Export-ModuleMember -Variable *
Export-ModuleMember -Cmdlet *
#################################################################
# begin script portions
#################################################################

Add-Type -AssemblyName Microsoft.Build

[string]$script:defaultMSBuildPath = $null
[string]$script:VisualStudioVersion = $null
# call this once to ensure the alias is set
Get-MSBuild | Set-MSBuild

