$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$importPsbuild = (Join-Path -Path $here -ChildPath 'import-psbuild.ps1')
. $importPsbuild


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

    $global:PSBuildSettings.BuildMessageEnabled = $false

    Setup -File -Path 'invoke-msbuild\temp.proj' -Content $script:tempProjContent

    It "ensure the project is invoked" {
        $path = ("$TestDrive\{0}" -f $script:tempProj)

        Copy-Item $path 'c:\temp\msbuild\genproj.proj'
        $path | Should Exist
        Invoke-MSBuild $path
        "$TestDrive\$genPath" | Should Exist
    }
}