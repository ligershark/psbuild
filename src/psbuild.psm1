﻿<#
.SYNOPSIS  
	This module will help to use msbuild from powershell.
    When you import this module the msbuild alias will be set
#>



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
        $project.Save([string]$filePath)
    }
}


<#
.SYNOPSIS  
	Can be used to invoke MSBuild. If the msbuildPath parameter is not passed in
    the Get-MSBuild function will be called to determine the version of MSBuild
    which should be used.

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

.EXAMPLE
    Invoke-MSBuild C:\temp\msbuild\msbuild.proj

.EXAMPLE
    Invoke-MSBuild 'C:\temp\msbuild\msbuild.proj'

.EXAMPLE
    Invoke-MSBuild @('C:\temp\msbuild\proj1.proj';'C:\temp\msbuild\proj2.proj')

.EXAMPLE
    @('C:\temp\msbuild\proj1.proj';'C:\temp\msbuild\proj2.proj') | Invoke-MSBuild

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
        $projectToBuild,
        
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

#################################################################
# begin script portions
#################################################################


[string]$script:defaultMSBuildPath = $null
[string]$script:VisualStudioVersion = $null
# call this once to ensure the alias is set
Get-MSBuild | Set-MSBuild