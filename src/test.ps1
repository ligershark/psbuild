function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDir = ((Get-ScriptDirectory) + "\")
$moduleName = 'psbuild'
$modulePath = (Join-Path -Path $scriptDir -ChildPath ("{0}.psm1" -f $moduleName))

if(Test-Path $modulePath){
    "Importing psbuild module from [{0}]" -f $modulePath | Write-Verbose

    if((Get-Module $moduleName)){
        Remove-Module $moduleName
    }
    
    Import-Module $modulePath -PassThru -DisableNameChecking | Out-Null
}
else{
    'Unable to find pshelpers module at [{0}]' -f $modulePath | Write-Error
	return
}

$VerbosePreference = "Continue"
# Invoke-MSBuild C:\temp\msbuild\path.proj -properties (@{'foo'='bar';'visualstudioversion'='12.0'}) -extraArgs '/p:foo2=bar2'
#Find-Import C:\temp\msbuild\proj1.proj -labelValue 'SlowCheetah'

$projFilePath = 'C:\temp\msbuild\proj1.proj'
$proj = (Get-Project $projFilePath)
#Add-Import -project $proj -importProject $projFilePath
#Save-Project -project $proj -filePath $projFilePath
#Add-Import -project $proj -importProject 'C:\temp\msbuild\import.targets' -importLabel 'LabelHere' -importCondition ' ''$(VSV)''====''12.0'' ' | Save-Project -filePath $projFilePath

#Save-Project -project $proj -filePath $projFilePath
$test = "test"