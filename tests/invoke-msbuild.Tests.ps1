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
if(!($env:PSBuildToolsDir)){
    $env:PSBuildToolsDir = (resolve-path (Join-Path $scriptDir '..\src\psbuild\bin\Debug\'))
}

Describe 'invoke-msbuild test cases' {
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
    $script:tempProj = 'invoke-msbuild\temp.proj'
    Setup -File -Path $script:tempProj -Content $script:tempProjContent

    $script:tempFailingProjContent = @"
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Demo" ToolsVersion="4.0">

  <Target Name="Demo">
    <Error Text="Error here"/>
  </Target>

</Project>
"@
    $script:tempFailingProj = 'invoke-msbuild\tempfailing.proj'
    Setup -File -Path $script:tempFailingProj -Content $script:tempFailingProjContent

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

    It "can specify visualstudioversion" {
        $sourceProj = ("$TestDrive\{0}" -f $script:tempProj)
        
        Invoke-MSBuild $sourceProj -visualStudioVersion 12.0
    }

    It "can specify configuration" {
        $sourceProj = ("$TestDrive\{0}" -f $script:tempProj)
        
        Invoke-MSBuild $sourceProj -configuration Release
    }

    It "can specify OutputPath" {
        $sourceProj = ("$TestDrive\{0}" -f $script:tempProj)
        
        Invoke-MSBuild $sourceProj -outputPath c:\temp\outputpath\
    }

    It "can specify DeployOnBuild" {
        $sourceProj = ("$TestDrive\{0}" -f $script:tempProj)
        
        Invoke-MSBuild $sourceProj -deployOnBuild $true
    }

    It "can specify PublishProfile" {
        $sourceProj = ("$TestDrive\{0}" -f $script:tempProj)
        
        Invoke-MSBuild $sourceProj -publishProfile MyProfile
    }

    It "can specify password" {
        $sourceProj = ("$TestDrive\{0}" -f $script:tempProj)
        
        Invoke-MSBuild $sourceProj -password PasswordHere
    }

    It 'throws on a failing project'{
        $sourceProj = ("$TestDrive\{0}" -f $script:tempFailingProj)
        
        {Invoke-MSBuild $sourceProj} | Should throw
    }

    It 'can build without passing in a project file'{
        $sourceProj = ("$TestDrive\{0}" -f $script:tempProj)
        $tempFolder = (New-Item -Type Directory -Path ('{0}\tempbuildnoprojfile' -f $TestDrive)).FullName
        Copy-Item $sourceProj (Join-Path $tempFolder 'myproj.csproj')
        Push-Location
        Set-Location $tempFolder
        Invoke-MSBuild
        Pop-Location
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