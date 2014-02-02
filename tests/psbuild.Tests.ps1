$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$importPsbuild = (Join-Path -Path $here -ChildPath 'import-psbuild.ps1')
. $importPsbuild

Describe "get and set msbuild test cases" {

    Setup -File 'sayedha\fakemsbuildfile01.txt' 
    Setup -File 'sayedha\fakemsbuildfile02.txt' 

    It "validate msbuild returns a file that exists" {
        $msbuildPath = Get-MSBuild
        $msbuildPath | Should Exist $msbuildPath
    }

    It "validate set-msbuild works" {
        
        $fakePath = ($msbuildDefaultPath = ("{0}\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe" -f $env:windir))
        $fakePath = "$TestDrive\sayedha\fakemsbuildfile01.txt"

        Set-MSBuild -msbuildPath $fakePath
        $retPath = Get-MSBuild
        $retPath | Should Be $fakePath
    }

    It "validate set-msbuild to null resets" {
        # call set-msbuild with a value and then call it with null and ensure the default value is used
        Set-MSBuild -msbuildPath "$TestDrive\sayedha\fakemsbuildfile02.txt"

        $valueBeforeSet = Get-MSBuild

        Set-MSBuild

        $valueAfterSet = Get-MSBuild

        $valueBeforeSet | Should Not Be $valueAfterSet
    }
}