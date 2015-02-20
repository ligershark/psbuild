$env:ExitOnPesterFail = $true
$env:IsDeveloperMachine=$true
$env:PesterEnableCodeCoverage = $true

if($env:APPVEYOR_REPO_BRANCH -eq "release"){
    .\build.ps1 -publishToNuget
}
else {
    .\build.ps1
}