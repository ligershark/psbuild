
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

#$projFile = 'C:\temp\msbuild\temp.proj'
#$defProps = 'C:\temp\msbuild\defProps\defProps.proj'
#[environment]::SetEnvironmentVariable("test","orig")

#$bResult = Invoke-MSBuild $projFile -debugMode
#$proj = (Get-Project $projFile)

#Invoke-MSBuild -projectsToBuild C:\temp\msbuild\new\new.proj
#Invoke-MSBuild -projectsToBuild C:\temp\msbuild\new\new.proj
#Get-Project $projFile | Save-Project -filePath $projFile
#$pgs = (Find-PropertyGroup -project $proj -labelValue MyPropGroup)
#$pgs = (Get-Project C:\temp\msbuild\proj1.proj | Find-PropertyGroup -labelValue MyPropGroup)
#Get-Project $projFile | Remove-PropertyGroup -labelValue MyPropGroup | Save-Project -filePath $projFile
#Get-Project $projFile | Add-PropertyGroup | Save-Project -filePath $projFile
#Test-PropertyGroup -project $proj -label Label1

#Remove-Property -propertyContainer $proj -Label label1 | Save-Project -filePath $projFile
#Add-Property -propertyContainer $proj -name Configuration -value Debug | Get-Project | Save-Project -filePath $projFile
#$logDir1 = Get-PSBuildLogDirectory
#Set-PSBuildLogDirectory -logDirectory 'C:\Users\Sayed\AppData\Local\PSBuild\logs2'
#$logDir2 = Get-PSBuildLogDirectory

#######################################################################
<#
Get-Project 'C:\temp\msbuild\new\new.proj' | Get-PSBuildLogDirectory


$loggers1 = (Get-PSBuildLoggers -project $proj)

$customLoggers = @()
$customLoggers += '/flp1:v=d;logfile={0}custom.d.{1}.{2}.log'
$customLoggers += '/flp1:v=diag;logfile={0}custom.diag.{1}.{2}.log'

Set-PSBuildLoggers -loggers $customLoggers
$loggers2 = (Get-PSBuildLoggers -project $proj)
#>
$test = "test"