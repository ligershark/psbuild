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

    It 'tests for Get-PSBuildLogDirectory (no hashing)' {
        $global:PSBuildSettings.EnableAddingHashToLogDir = $false

        $projFilePath = ("$TestDrive\{0}" -f $script:tempPSBuildLogProj01Path)

        $projFileInfo = Get-Item $projFilePath

        $logdir = Get-PSBuildLogDirectory -projectPath $projFilePath

        $expectedLogDirName = ('{0}\' -f $projFileInfo.Name)
        # logdir should end in the 'proj-file-name\'
        $logdir | Should Match ".*psbulidlog01.proj-log\\$"

        $global:PSBuildSettings.EnableAddingHashToLogDir = $true
    }

    It 'tests for Get-PSBuildLogDirectory' {
        $projFilePath = ("$TestDrive\{0}" -f $script:tempPSBuildLogProj01Path)

        $projFileInfo = Get-Item $projFilePath

        $logdir = Get-PSBuildLogDirectory -projectPath $projFilePath

        $expectedLogDirName = ('{0}\' -f $projFileInfo.Name)
        # logdir should end in the 'proj-file-name\'
        $logdir | Should Match ".*psbulidlog01.proj-.*log\\$"
    }
}
