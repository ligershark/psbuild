$env:ExitOnPesterFail = $true
if($env:APPVEYOR_REPO_BRANCH -eq "release"){
    .\build.ps1 -publishToNuget
}
else {
    .\build.ps1
}