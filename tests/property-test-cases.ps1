
    It "can specify visualstudioversion" {
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj -visualStudioVersion 12.0 -nologo)
        Validate-PropFromMSBuildOutput $msbuildOutput 'VisualStudioVersion' 12.0
    }

    It "can specify configuration" {
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj -configuration Release -nologo)
        Validate-PropFromMSBuildOutput $msbuildOutput Configuration Release
    }

    It "can specify platform no space" {
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj -Platform AnyCPU -nologo)
        Validate-PropFromMSBuildOutput $msbuildOutput Platform AnyCPU
    }
    
    It "can specify OutputPath" {
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj -OutputPath c:\temp\outputpath\ -nologo)
        Validate-PropFromMSBuildOutput $msbuildOutput OutputPath c:\temp\outputpath\
    }

    It "can specify DeployOnBuild" {
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj -DeployOnBuild $true -nologo)
        Validate-PropFromMSBuildOutput $msbuildOutput DeployOnBuild true
    }

    It "can specify PublishProfile" {
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj -PublishProfile MyProfile -nologo)
        Validate-PropFromMSBuildOutput $msbuildOutput PublishProfile MyProfile
    }
    <#
    It "can specify password" {
        $env:PSBuildMaskSecrets=$false
        $sourceProj = ("$TestDrive\{0}" -f $script:printpropertiesproj)
        $msbuildOutput = (Invoke-MSBuild $sourceProj -Password PasswordHere -nologo)
        Validate-PropFromMSBuildOutput $msbuildOutput Password PasswordHere
        $env:PSBuildMaskSecrets=$true
    }
    #>
