$VerbosePreference = "Continue"
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


# Invoke-MSBuild C:\temp\msbuild\path.proj -properties (@{'foo'='bar';'visualstudioversion'='12.0'}) -extraArgs '/p:foo2=bar2'
#Find-Import C:\temp\msbuild\proj1.proj -labelValue 'SlowCheetah'

$projFilePath = 'C:\temp\msbuild\proj1.proj'
$proj = (Get-Project $projFilePath)
#$pgs = (Find-PropertyGroup -project $proj -labelValue MyPropGroup)
#$pgs = (Get-Project C:\temp\msbuild\proj1.proj | Find-PropertyGroup -labelValue MyPropGroup)
$test = "test"