$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$importPsbuild = (Join-Path -Path $here -ChildPath 'import-psbuild.ps1')
. $importPsbuild

Describe 'tests for Get-PSBuildLogDirectory' {
    $script:tempPSBuildLogProj01Path = 'invoke-msbuild\psbulidlog01.proj'
    $script:tempPSBuildLogProj01Content = @'
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
    Setup -File -Path $script:tempPSBuildLogProj01Path -Content $script:tempPSBuildLogProj01Content

    $global:PSBuildSettings.BuildMessageEnabled = $false
    Add-Type -AssemblyName Microsoft.Build

    It 'tests for Get-PSBuildLogDirectory' {
        $projFilePath = ("$TestDrive\{0}" -f $script:tempPSBuildLogProj01Path)

        $projFileInfo = Get-Item $projFilePath

        $logdir = Get-PSBuildLogDirectory -projectPath $projFilePath

        $expectedLogDirName = ('{0}\' -f $projFileInfo.Name)
        # logdir should end in the 'proj-file-name\'
        $logdir | Should Match ".*psbulidlog01.proj-log\\$"
    }

    It 'Get-PSBuildLoggers returns a list with 2 values' {
        # Get-PSBuildLoggers
        $projFilePath = ("$TestDrive\{0}" -f $script:tempPSBuildLogProj01Path)
        $project = Get-MSBuildProject $projFilePath

        $loggers = Get-PSBuildLoggers -projectPath $projFilePath

        $foo = 'bar'
    }
}

Describe 'tests for Get-PSBuildLoggers' {
    $script:tempPSBuildLogProj01Path = 'invoke-msbuild\psbulidlog01.proj'
    $script:tempPSBuildLogProj01Content = @'
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
    Setup -File -Path $script:tempPSBuildLogProj01Path -Content $script:tempPSBuildLogProj01Content

    $global:PSBuildSettings.BuildMessageEnabled = $false
    Add-Type -AssemblyName Microsoft.Build

    It 'Get-PSBuildLoggers returns a list with 2 values' {
        # Get-PSBuildLoggers
        $projFilePath = ("$TestDrive\{0}" -f $script:tempPSBuildLogProj01Path)
        $project = Get-MSBuildProject $projFilePath

        $loggers = Get-PSBuildLoggers -projectPath $projFilePath

        $loggers | Should Not BeNullOrEmpty
        $loggers.Length | Should Be 2
        # | Should Match "*detailed"
        $loggers[0] | Should Match "detailed"
        $loggers[1] | Should Match "diagnostic"
    }

}