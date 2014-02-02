$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$importPsbuild = (Join-Path -Path $here -ChildPath 'import-psbuild.ps1')
. $importPsbuild


Describe 'invoke-msbuild test cases' {
    
    $script:tempProj = 'invoke-msbuild\temp.proj'
    $script:tempProjContent = @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Demo" ToolsVersion="4.0">

  <Target Name="Demo">
    <Message Text="Inside demo target of file [$(MSBuildProjectFile)]" Importance="high"/>
  </Target>

</Project>
'@
    
    Setup -File -Path 'invoke-msbuild\temp.proj' -Content 'ff'

    It "in the new file" {
        $path = ("$TestDrive\{0}" -f $script:tempProj)
        $path | Should Exist
    }
}