param($rootPath, $toolsPath, $package, $project)


if((Get-Module psbuild)){
    Remove-Module psbuild
}
Import-Module (Join-Path -Path ($toolsPath) -ChildPath 'psbuild.psm1')

'inside init.ps1' | Write-Host
