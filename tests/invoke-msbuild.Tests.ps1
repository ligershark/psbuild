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

$global:PSBuildSettings.BuildMessageEnabled = $false
Add-Type -AssemblyName Microsoft.Build

function Validate-PropFromMSBuildOutput{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $msbuildOutput,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$propName,
        [Parameter(Mandatory=$true,Position=2)]
        [string]$expectedPropValue
    )
    process{
        $actualValue = ([regex]"\*\*$propName.*\[.*]").match( ($msbuildOutput | Select-String "$propName.*") ).Groups[0].Value
        $actualValue | Should Be ("**$propName=[$expectedPropValue]")
    }
}

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

    $script:tempFailingProjContent = @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Demo" ToolsVersion="4.0">

  <Target Name="Demo">
    <Error Text="Error here"/>
  </Target>

</Project>
'@
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

    It 'throws on a failing project'{
        $sourceProj = ("$TestDrive\{0}" -f $script:tempFailingProj)
        
        {Invoke-MSBuild $sourceProj} | Should throw
    }

    It 'can use ignoreexitcode to prevent exception'{
        $sourceProj = ("$TestDrive\{0}" -f $script:tempFailingProj)

        {Invoke-MSBuild $sourceProj -ignoreExitCode} | Should not throw
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

Describe 'Property tests no quoting'{
    $script:printpropscontent = @'
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Demo" ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
	<Target Name="Demo">
		<Message Text="**VisualStudioVersion=[$(VisualStudioVersion)]" Importance="high"/>
		<Message Text="**Configuration=[$(Configuration)]" Importance="high"/>
		<Message Text="**Platform=[$(Platform)]" Importance="high"/>
		<Message Text="**OutputPath=[$(OutputPath)]" Importance="high"/>
		<Message Text="**DeployOnBuild=[$(DeployOnBuild)]" Importance="high"/>
		<Message Text="**PublishProfile=[$(PublishProfile)]" Importance="high"/>
		<Message Text="**Password=[$(Password)]" Importance="high"/>
 	</Target>
</Project>
'@
    $script:printpropertiesproj = 'invoke-msbuild\printprops.proj'
    Setup -File -Path $script:printpropertiesproj -Content $script:printpropscontent

    $global:PSBuildSettings.BuildMessageEnabled = $false

    $oldValue = $global:PSBuildSettings.EnablePropertyQuoting
    $global:PSBuildSettings.EnablePropertyQuoting = $false
    # invoke-property tests
    . (Join-Path $scriptDir 'property-test-cases.ps1')
    $global:PSBuildSettings.EnablePropertyQuoting = $oldValue
}

Describe 'Property tests with quoting'{
    $script:printpropscontent = @'
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Demo" ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
	<Target Name="Demo">
		<Message Text="**VisualStudioVersion=[$(VisualStudioVersion)]" Importance="high"/>
		<Message Text="**Configuration=[$(Configuration)]" Importance="high"/>
		<Message Text="**Platform=[$(Platform)]" Importance="high"/>
		<Message Text="**OutputPath=[$(OutputPath)]" Importance="high"/>
		<Message Text="**DeployOnBuild=[$(DeployOnBuild)]" Importance="high"/>
		<Message Text="**PublishProfile=[$(PublishProfile)]" Importance="high"/>
		<Message Text="**Password=[$(Password)]" Importance="high"/>
 	</Target>
</Project>
'@
    $script:printpropertiesproj = 'invoke-msbuild\printprops.proj'
    Setup -File -Path $script:printpropertiesproj -Content $script:printpropscontent
    
    $global:PSBuildSettings.BuildMessageEnabled = $false
    
    $oldValue = $global:PSBuildSettings.EnablePropertyQuoting
    $global:PSBuildSettings.EnablePropertyQuoting = $true
    # invoke-property tests
    . (Join-Path $scriptDir 'property-test-cases.ps1')

    It "can specify platform with space" {
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj -Platform 'Mixed Platforms' -nologo)
        Validate-PropFromMSBuildOutput $msbuildOutput Platform 'Mixed Platforms'
    }
    $global:PSBuildSettings.EnablePropertyQuoting = $oldValue
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

        $buildResultNoDefault = Invoke-MSBuild -projectsToBuild $path -debugMode -targets Demo
        $outputTypeNoDefault = $buildResultNoDefault.EvalProperty('OutputType')

        $outputTypeNoDefault | Should BeNullOrEmpty

        $buildResultWithDefault = Invoke-MSBuild -projectsToBuild $path -debugMode -defaultProperties @{'OutputType'='exe'} -targets Demo
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

Describe 'debugMode tests'{
    $script:envVarTarget = 'Process'
    $script:debugModeFilePath = 'invoke-msbuild\debugmode01.proj'
    $script:debugModeFileContent = @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Build" ToolsVersion="4.0">
  <Target Name="Build">
    <Message Text="Hello!" Importance="high"/>
  </Target>

</Project>
'@
    $foo = Setup -File -Path $script:debugModeFilePath -Content $script:debugModeFileContent
    Add-Type -AssemblyName Microsoft.Build
    $global:PSBuildSettings.BuildMessageEnabled = $false

    It 'can build using debugMode without passing in targets'{
        $path = ("$TestDrive\{0}" -f $script:debugModeFilePath)
        $path = (Join-Path $TestDrive $script:debugModeFilePath)
        $buildResult = Invoke-MSBuild -projectsToBuild $path -debugMode
        $buildResult.BuildResult.OverallResult | Should Be Success
    }

    It 'can build using debugMode with passing in targets'{
        $path = ("$TestDrive\{0}" -f $script:debugModeFilePath)
        $path = (Join-Path $TestDrive $script:debugModeFilePath)
        $buildResult = Invoke-MSBuild -projectsToBuild $path -debugMode -targets Build
        $buildResult.BuildResult.OverallResult | Should Be Success
    }
}

<# - no longer supported to disable this
Describe 'Masking tests - masking disabled'{
    $script:printpropscontent = @'
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Demo" ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
	<Target Name="Demo">
		<Message Text="**VisualStudioVersion=[$(VisualStudioVersion)]" Importance="high"/>
		<Message Text="**Configuration=[$(Configuration)]" Importance="high"/>
		<Message Text="**Platform=[$(Platform)]" Importance="high"/>
		<Message Text="**OutputPath=[$(OutputPath)]" Importance="high"/>
		<Message Text="**DeployOnBuild=[$(DeployOnBuild)]" Importance="high"/>
		<Message Text="**PublishProfile=[$(PublishProfile)]" Importance="high"/>
		<Message Text="**Password=[$(Password)]" Importance="high"/>
 	</Target>
</Project>
'@
    $script:printpropertiesproj = 'invoke-msbuild\printprops.proj'
    Setup -File -Path $script:printpropertiesproj -Content $script:printpropscontent
    Remove-Module psbuild -Force

        $env:PSBuildMaskSecrets=$false

        $importPsbuild = (Join-Path -Path $scriptDir -ChildPath 'import-psbuild.ps1')
        . $importPsbuild
        It "can specify password" {
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj -Password PasswordHere -nologo)
        Validate-PropFromMSBuildOutput $msbuildOutput Password PasswordHere
    }
}
#>

Describe 'Masking tests'{
    $script:printpropscontent = @'
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Demo" ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
	<Target Name="Demo">
		<Message Text="**VisualStudioVersion=[$(VisualStudioVersion)]" Importance="high"/>
		<Message Text="**Configuration=[$(Configuration)]" Importance="high"/>
		<Message Text="**Platform=[$(Platform)]" Importance="high"/>
		<Message Text="**OutputPath=[$(OutputPath)]" Importance="high"/>
		<Message Text="**DeployOnBuild=[$(DeployOnBuild)]" Importance="high"/>
		<Message Text="**PublishProfile=[$(PublishProfile)]" Importance="high"/>
		<Message Text="**Password=[$(Password)]" Importance="high"/>
 	</Target>
</Project>
'@
$script:printpropertiesproj = 'invoke-msbuild\printprops.proj'
Setup -File -Path $script:printpropertiesproj -Content $script:printpropscontent
Remove-Module psbuild -Force
$defaultMask = '********'

$importPsbuild = (Join-Path -Path $scriptDir -ChildPath 'import-psbuild.ps1')
. $importPsbuild
It "can specify password" {
    $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
    $msbuildOutput = (Invoke-MSBuild $sourceProj -Password PasswordHere -nologo)
    Validate-PropFromMSBuildOutput $msbuildOutput Password $defaultMask
    $msbuildOutput.Contains('PasswordHere') | Should Be $false
}
<#
It 'can specify a different mask globally'{
    $newMask = '##########'
    $global:FilterStringSettings.DefaultMask = $newMask
    $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
    $msbuildOutput = (Invoke-MSBuild $sourceProj -Password PasswordHere -nologo)
    Validate-PropFromMSBuildOutput $msbuildOutput Password $newMask
    $msbuildOutput.Contains('PasswordHere') | Should Be $false
}
#>
}

Describe 'toolsversion tests'{
    $script:printpropscontent = @'
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Demo" ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
	<Target Name="Demo">
		<Message Text="**VisualStudioVersion=[$(VisualStudioVersion)]" Importance="high"/>
		<Message Text="**Configuration=[$(Configuration)]" Importance="high"/>
		<Message Text="**Platform=[$(Platform)]" Importance="high"/>
		<Message Text="**OutputPath=[$(OutputPath)]" Importance="high"/>
		<Message Text="**DeployOnBuild=[$(DeployOnBuild)]" Importance="high"/>
		<Message Text="**PublishProfile=[$(PublishProfile)]" Importance="high"/>
		<Message Text="**Password=[$(Password)]" Importance="high"/>
	</Target>
</Project>
'@
    $script:printpropertiesproj = 'invoke-msbuild\printprops.proj'
    Setup -File -Path $script:printpropertiesproj -Content $script:printpropscontent

    Mock Invoke-CommandString {
        return {
            $commandArgs
        }
    } -param { $global:lastcmdargs = ($commandArgs -join ' ') } -ModuleName 'psbuild'

    It 'can pass toolsversion'{
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj -toolsversion '12.0')
        $global:lastcmdargs.Contains('/toolsversion:12.0') | Should Be $true
    }

    It 'can not pass toolsversion'{
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj)
        $global:lastcmdargs.Contains('/toolsversion') | Should Be $false
    }
}