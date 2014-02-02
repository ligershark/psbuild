# based off of the scrit at http://psget.net/GetPsGet.ps1
function Install-PSBuild {
    $ModulePaths = @($Env:PSModulePath -split ';')
    
    $ExpectedUserModulePath = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath WindowsPowerShell\Modules
    $Destination = $ModulePaths | Where-Object { $_ -eq $ExpectedUserModulePath}
    if (-not $Destination) {
        $Destination = $ModulePaths | Select-Object -Index 0
    }

    $downloadUrl = 'https://raw.github.com/ligershark/psbuild/master/src/psbuild.psm1'
    New-Item ($Destination + "\psbuild\") -ItemType Directory -Force | out-null
    'Downloading PsGet from {0}' -f $downloadUrl | Write-Host
    $client = (New-Object Net.WebClient)
    $client.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    $client.DownloadFile($downloadUrl, $Destination + "\psbuild\psbuild.psm1")

    $executionPolicy  = (Get-ExecutionPolicy)
    $executionRestricted = ($executionPolicy -eq "Restricted")
    if ($executionRestricted){
        Write-Warning @"
Your execution policy is $executionPolicy, this means you will not be able import or use any scripts including modules.
To fix this change your execution policy to something like RemoteSigned.

        PS> Set-ExecutionPolicy RemoteSigned

For more information execute:
        
        PS> Get-Help about_execution_policies

"@
    }

    if (!$executionRestricted){
        # ensure PsGet is imported from the location it was just installed to
        Import-Module -Name $Destination\psbuild
    }    
    Write-Host "psbuild is installed and ready to use" -Foreground Green
    Write-Host @"
USAGE:
    PS> Invoke-MSBuild 'C:\temp\msbuild\msbuild.proj'
    PS> Invoke-MSBuild C:\temp\msbuild\path.proj -properties (@{'foo'='bar';'visualstudioversion'='12.0'}) -extraArgs '/nologo'

For more details:
    get-help Invoke-MSBuild
Or visit http://msbuildbook.com/psbuild
"@
}

Install-PSBuild