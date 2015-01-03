[cmdletbinding()]
 param()

function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDir = ((Get-ScriptDirectory) + "\")

$importPsbuild = (Join-Path -Path $scriptDir -ChildPath 'import-psbuild.ps1')
. $importPsbuild

# todo: should set this some other way
$env:PSBuildToolsDir = (resolve-path (Join-Path $scriptDir '..\src\psbuild\bin\Debug\'))

Describe 'invoke-msbuild test cases' {
    
    $script:tempProj = 'invoke-msbuild\temp.proj'
    $script:genPath = 'invoke-msbuild\generated.txt'
    $script:tempProjContent = @"
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Demo" ToolsVersion="4.0">

  <Target Name="Demo">
    <Message Text="Inside demo target of file" Importance="high"/>
    <WriteLinesToFile File="$TestDrive\$script:genPath"  Lines="from-unit test"/>
  </Target>

</Project>
"@
    Setup -File -Path $script:tempProj -Content $script:tempProjContent    

    $global:PSBuildSettings.BuildMessageEnabled = $false
    Add-Type -AssemblyName Microsoft.Build
    It "ensure the project is invoked" {
        $path = Join-Path $TestDrive $script:tempProj
        $path | Should Exist

        Invoke-MSBuild $path
        "$TestDrive\$genPath" | Should Exist
    }

    It "ensure when -preprocess is passed that there are no errors" {
        $sourceProj = ("$TestDrive\{0}" -f $script:tempProj)
        
        Invoke-MSBuild $sourceProj -preprocess
    }
}

Describe 'default property tests' {
    $script:envVarTarget = 'Process'
    $script:tempDefaultPropsProj01Path = 'invoke-msbuild\defprops01.proj'
    $script:tempDefaultPropsProj01Content = @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Demo" ToolsVersion="4.0">

  <PropertyGroup>
    <Configuration>Release</Configuration>
  </PropertyGroup>

  <Target Name="Demo">
    <Message Text="Configuration: $(Configuration)" Importance="high"/>
    <Message Text="OutputType: $(OutputType)" Importance="high"/>
  </Target>
  
</Project>
'@
    Setup -File -Path $script:tempDefaultPropsProj01Path -Content $script:tempProjContent
    Add-Type -AssemblyName Microsoft.Build
    $global:PSBuildSettings.BuildMessageEnabled = $false

    It 'confirm default property values are picked up' {
        $path = ("$TestDrive\{0}" -f $script:tempDefaultPropsProj01Path)
        Copy-Item $path C:\temp\result.proj
        $buildResultNoDefault = Invoke-MSBuild -projectsToBuild $path -debugMode -targets Build
        $outputTypeNoDefault = $buildResultNoDefault.EvalProperty('OutputType')

        $outputTypeNoDefault | Should BeNullOrEmpty

        $buildResultWithDefault = Invoke-MSBuild -projectsToBuild $path -debugMode -defaultProperties @{'OutputType'='exe'} -targets Build
        $outputTypeWithDefault = $buildResultWithDefault.EvalProperty('OutputType')

        $outputTypeWithDefault | Should Be 'exe'
    }

    It 'confirm cmd line param trumps default property' {
        $path = ("$TestDrive\{0}" -f $script:tempDefaultPropsProj01Path)
        
        $buildResultWithDefault = Invoke-MSBuild -projectsToBuild $path -debugMode -defaultProperties @{'OutputType'='exe'} -properties @{'OutputType'='dll'} -targets Build
        $outputTypeWithDefault = $buildResultWithDefault.EvalProperty('OutputType')

        $outputTypeWithDefault | Should Be 'dll'
    }

    It 'confirm env vars are not impacted after invocation' {
        $info = New-Object psobject -Property @{
            EnvVarToSet = 'psbuild-temp'
            ValueBefore = 'default'
            ValueDuringBuild = 'override'
        }

        $path = ("$TestDrive\{0}" -f $script:tempDefaultPropsProj01Path)

        # set the env var before the build
        [environment]::SetEnvironmentVariable($info.EnvVarToSet, $info.ValueBefore,$script:envVarTarget)

        [environment]::GetEnvironmentVariable($info.EnvVarToSet,$script:envVarTarget) | 
            Should Be $info.ValueBefore

        $buildResultWithDefault = Invoke-MSBuild -projectsToBuild $path -debugMode -defaultProperties @{$info.EnvVarToSet=$info.ValueDuringBuild} -targets Build
        $outputTypeWithDefault = $buildResultWithDefault.EvalProperty('OutputType')

        [environment]::GetEnvironmentVariable($info.EnvVarToSet,$script:envVarTarget) | 
            Should Be $info.ValueBefore
    }
}
