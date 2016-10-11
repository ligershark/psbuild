[cmdletbinding()]
param(
    [Parameter(Position=0)]
    $pathToReplacerAssembly
)

Set-StrictMode -Version 3

function Get-ScriptDirectory{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}
$scriptDir = ((Get-ScriptDirectory) + "\")

$buildprops = new-object psobject -Property @{
    ReplacerAssemblyFileName = 'LigerShark.FileReplacer.dll'
    ReplacerAssemblyLoaded = $false
}

function FindReplacerAssembly{
    [cmdletbinding()]
    param()
    process{
        
        $foundPath = $null
        $pathsToCheck = @()

        if($env:ReplacerAssemblyFilePath){
           $pathsToCheck += $env:ReplacerAssemblyFilePath 
        }

        $pathsToCheck += (join-path $scriptDir $buildprops.ReplacerAssemblyFileName)

        foreach($path in $pathsToCheck){
            'Looking for replace assembly at [{0}]' -f $path | Write-Verbose

            if(test-path $path){
                'Found replacer assembly at [{0}]' -f $path | Write-Verbose
                $foundPath = $path
                break
            }
        }

        $foundPath
    }
}

function LoadReplacerAssembly{
    [cmdletbinding()]
    param(
        [switch]$force
    )
    process{
        if($force){
            $buildprops.ReplacerAssemblyLoaded=$false
        }

        if(!($buildprops.ReplacerAssemblyLoaded)){            
            $pathtoreplacerAssembly = FindReplacerAssembly
            if(!$pathtoreplacerAssembly){
                throw ('Unable to find the replacer assembly')
            }

            'Loading replacer assembly from [{0}]' -f $pathtoreplacerAssembly | Write-Verbose
            Add-Type -path $pathtoreplacerAssembly
        }
        else{
            'LoadReplacerAssembly skipping the load for the assembly since it has already been loaded' | Write-Verbose
        }
    }
}

function Replace-TextInFolder{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateScript({test-path $_})]
        [string]$folder,

        [Parameter(Position=1)]
        [hashtable]$replacements,
        

        [Parameter(Position=2)]
        [ValidateNotNullOrEmpty()]
        [string]$include='*.*',

        [Parameter(Position=3)]
        [string]$exclude
    )
    begin{ LoadReplacerAssembly }
    process{
        try{         
            $folder = (Get-Item $folder).FullName
            'Starting replacements in folder [{0}]' -f $folder | Write-Verbose
            # convert replacements to correct object
            $repDictionary = New-Object 'system.collections.generic.dictionary[string,string]'

            $replacements.Keys | % {
                $repDictionary.Add($_,$replacements[$_])
            }

            $logger = new-object System.Text.StringBuilder
            $replacer = new-object LigerShark.TemplateBuilder.Tasks.RobustReplacer
            $replacer.ReplaceInFiles($folder,$include,$exclude,$repDictionary,$logger)
            $logger.ToString() | Write-Verbose
        }
        catch{
            throw("Unable to complete replacements.`nError: [{0}]" -f ($_.Exception.Message))
        }
    }
}
