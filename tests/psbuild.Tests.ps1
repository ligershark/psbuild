$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$importPsbuild = (Join-Path -Path $here -ChildPath 'import-psbuild.ps1')
. $importPsbuild
$global:PSBuildSettings.BuildMessageEnabled = $false
function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDir = ((Get-ScriptDirectory) + "\")

set-msbuild
Describe "get and set msbuild test cases" {

    Setup -File 'sayedha\fakemsbuildfile01.txt' 
    Setup -File 'sayedha\fakemsbuildfile02.txt' 
    Add-Type -AssemblyName Microsoft.Build
    It "validate msbuild returns a file that exists" {
        $msbuildPath = Get-MSBuild
        $msbuildPath | Should Exist $msbuildPath
    }

    It "validate set-msbuild works" {
        
        $fakePath = ($msbuildDefaultPath = ("{0}\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe" -f $env:windir))
        $fakePath = "$TestDrive\sayedha\fakemsbuildfile01.txt"
        Set-MSBuild -msbuildPath $fakePath
        $retPath = (Get-MSBuild)
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

    It "validate Get-MSBuildEscapeCharacters returns 10 values" {
        $msbEscape = Get-MSBuildEscapeCharacters
        $msbEscape.Length | Should Be 10
    }
}
set-msbuild


Describe "Open-PSBuildLog test cases" {
    $script:tempProj = 'Open-PSBuildLog\temp.proj'
    $script:tempProjContent = @"
        <?xml version="1.0" encoding="utf-8"?>
        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Demo" ToolsVersion="4.0">

          <Target Name="Demo">
            <Message Text="Hello World" Importance="high"/>
          </Target>

        </Project>
"@
    Setup -File -Path $script:tempProj -Content $script:tempProjContent
    $tempProjFilePath = Join-Path $TestDrive $script:tempProj

    It "validate Open-PSBuildLog returns a file path-default" {
        Invoke-MSBuild $tempProjFilePath
        $logFilePath = Open-PSBuildLog -returnFilePathInsteadOfOpening
        $logFilePath | Should Exist
    }

    It "validate Open-PSBuildLog returns a file path-diagnostic" {
        Invoke-MSBuild $tempProjFilePath
        $logFilePath = Open-PSBuildLog diagnostic -returnFilePathInsteadOfOpening
        $logFilePath | Should Exist
    }

    It "validate Open-PSBuildLog returns a file path-detailed" {
        Invoke-MSBuild $tempProjFilePath
        $logFilePath = Open-PSBuildLog detailed -returnFilePathInsteadOfOpening
        $logFilePath | Should Exist
    }

    It "validate Open-PSBuildLog returns a file path-markdown" {
        Invoke-MSBuild $tempProjFilePath
        $logFilePath = Open-PSBuildLog markdown -returnFilePathInsteadOfOpening
        $logFilePath | Should Exist
    }
}

Describe "Get-MSBuildEscapeCharacters tests" {
    It "returns a non-empty array" {
        $escapeChars = Get-MSBuildEscapeCharacters
        $escapeChars -is [array] | Should Be $true
        $escapeChars | %{
            $_ | Should Not BeNullOrEmpty
        }
    }
}

Describe "Get-MSBuildReservedProperties tests" {
    It "returns non-empty and contains reserved props" {
        $reservedProps = Get-MSBuildReservedProperties

        $allText = ($reservedProps -join "`n")
        $allText | Should NOt BeNullOrEmpty
        $allText | Should Match 'MSBuildBinPath:'
        $allText | Should Match 'MSBuildProjectDirectory:'
        $allText | Should Match 'MSBuildThisFileDirectory:'
        $allText | Should Match 'MSBuildThisFileExtension:'
    }
}

Describe "New-MSBuildProject tests" {
    It "creates a file at specified location" {
        $tempProjFilePath = Join-Path $TestDrive 'New-MSBuildProject\create01.proj'
        $newFile = New-MSBuildProject -filePath ($tempProjFilePath)
        $newFile | Should Not Be $null
        $tempProjFilePath | Should Exist
    }
}

Describe "PSBuild-ConverToDictionary tests" {
    It "does not return empty" {
        $objtoconvert = @{
            'one'='one-value'
            'two'='two-value'
        }

        [system.collections.generic.dictionary[[string],[string]]]$convertedObj = PSBuild-ConverToDictionary $objtoconvert
        $convertedObj | Should Not be $null
        $convertedObj.Count | Should be 2
        $convertedObj['one'] | Should be $objtoconvert['one']
        $convertedObj['two'] | Should be $objtoconvert['two']
    }
}

Describe "env var tests"{
    $envVarNames = @('OutputType','SomeProp')

    It "PSBuildSet-TempVar sets the env var" {

        # PSBuildSet-TempVar
        $envVarsToSet = @{
            'OutputType'='exe'
            'SomeProp'='somevalue'
        }

        PSBuildSet-TempVar $envVarsToSet

        $envVarsToSet.Keys | % {
            $envVarValue = [environment]::GetEnvironmentVariable($_,'Process')
            $envVarValue | Should Be $envVarsToSet[$_]
        }
    }

    It "PSBuildReset-TempEnvVars restores env vars" {
        $originalEnvVars = @{
            'OutputType'='dll'
            'SomeProp'='someorigvalue'
        }

        $originalEnvVars.Keys | % {
            [environment]::SetEnvironmentVariable($_,$originalEnvVars[$_],'Process')
        }

        $envVarsToSet = @{
            'OutputType'='exe'
            'SomeProp'='somevalue'
        }

        PSBuildSet-TempVar $envVarsToSet

        $envVarsToSet.Keys | % {
            $envVarValue = [environment]::GetEnvironmentVariable($_,'Process')
            $envVarValue | Should Be $envVarsToSet[$_]
        }

        PSBuildReset-TempEnvVars

        $originalEnvVars.Keys | % {
            $envVarValue = [environment]::GetEnvironmentVariable($_,'Process')
            $envVarValue | Should Be $originalEnvVars[$_]
        }
    }

    AfterEach {
        # reset env vars back to null
        $envVarNames | % {
            [environment]::SetEnvironmentVariable("$_", $null,'Process')
        }
    }
}

Describe "nologs tests"{
    $script:tempProj = 'nologs\temp.proj'
    $script:tempProjContent = @"
        <?xml version="1.0" encoding="utf-8"?>
        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Demo" ToolsVersion="4.0">

          <Target Name="Demo">
            <Message Text="Hello World" Importance="high"/>
          </Target>

        </Project>
"@
    Setup -File -Path $script:tempProj -Content $script:tempProjContent
    $tempProjFilePath = Join-Path $TestDrive $script:tempProj

    It "nologs does not produce log files" {
        $logDir = $global:PSBuildSettings.LastLogDirectory = (Get-PSBuildLogDirectory -projectPath $tempProjFilePath)
        # if there are any files there now delete them
        Get-ChildItem $logDir *.log | Remove-Item

        Invoke-MSBuild $tempProjFilePath -noLogFiles

        # ensure there are no log files
        $foundFiles = (Get-ChildItem $logDir *.log)
        $foundFiles | Should Be $null
    }

    It "EnableBuildLogging disables logging to files" {
        $global:PSBuildSettings.EnableBuildLogging = $false

        $logDir = $global:PSBuildSettings.LastLogDirectory = (Get-PSBuildLogDirectory -projectPath $tempProjFilePath)
        # if there are any files there now delete them
        Get-ChildItem $logDir *.log | Remove-Item

        Invoke-MSBuild $tempProjFilePath

        # ensure there are no log files
        $foundFiles = (Get-ChildItem $logDir *.log)
        $foundFiles | Should Be $null

        # reset it back to default value
        $global:PSBuildSettings.EnableBuildLogging = $true
    }
}