<#
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
<#
.SYNOPSIS  
	This has two purposes:
        1. Create the msbuild alias
        2. Users can specific a specific msbuild.exe which should be used
#>
function Set-MSBuild{
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

# begin script portions
[string]$script:defaultMSBuildPath = $null
# call this once to ensure the alias is set
Get-MSBuild | Set-MSBuild