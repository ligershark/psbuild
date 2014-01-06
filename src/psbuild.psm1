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
        
        [Hashtable]
        $properties,
        
        $targets,
        
        [string]
        $extraArgs
    )

    begin{
        Add-Type -AssemblyName Microsoft.Build
    }

    process{
        foreach($project in $projectsToBuild){
            $msbuildArgs = @()
            $msbuildArgs += ([string]$project)

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

            if($extraArgs){
                foreach($exArg in $extraArgs){
                    $msbuildArgs += $exArg
                }
            }
        
            "Calling msbuild.exe with the following args: {0}" -f (($msbuildArgs -join ' ')) | Write-Verbose
            & msbuild $msbuildArgs
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
        $filePath
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }

    process{
        $newProj = [Microsoft.Build.Construction.ProjectRootElement]::Create()

        if($filePath){
            Save-Project $newProj
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
            Mandatory=$true,
            ValueFromPipeline = $true)]
        $project,

        [Parameter(Mandatory=$true)]
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

        $fullPath = (Get-Fullpath -path $filePath)
        $project.Save([string]$fullPath)
        return $project
    }
}

<#
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
#>
function Get-Project{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            Position=1)]
        $projectFile,
        
        $projectCollection = (New-Object Microsoft.Build.Evaluation.ProjectCollection)
    )
    begin{
        Add-Type -AssemblyName System.Core
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $fullPath = (Get-Fullpath $projectFile)
        $proj = ([Microsoft.Build.Construction.ProjectRootElement]::Open([string]$fullPath,$projectCollection))
        return $proj
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

        return ($foundImport -ne $null)
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
        "Looking for an import, project: {0}" -f $project | Write-Verbose

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
#>
<# work in progress

function Find-PropertyGroup{
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
        "Looking for an import, project: {0}" -f $project | Write-Verbose

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
#>
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

