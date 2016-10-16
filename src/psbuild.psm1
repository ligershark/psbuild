<#
.SYNOPSIS
	This module will help to use msbuild from powershell.
    When you import this module the msbuild alias will be set.
    You can see what command are available by executing the
    following command.

    Get-Command -Module psbuild

#>
[cmdletbinding()]
param(
    $nugetPsMinModuleVersion = '0.2.1.1'
)

Set-StrictMode -Version Latest

function InternalGet-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}

$scriptDir = ((InternalGet-ScriptDirectory) + "\")

# User settings can override these
$global:PSBuildSettings = New-Object PSObject -Property @{
    EnableBuildLogging = $true
    # set this to false to prevent any messages being output from here via Write-Host
    BuildMessageEnabled = $true

    BuildMessageForegroundColor = [ConsoleColor]::Cyan
    BuildMessageBackgroundColor = [ConsoleColor]::DarkMagenta

    BuildMessageStrongForegroundColor = [ConsoleColor]::Yellow
    BuildMessageStrongBackgroundColor = [ConsoleColor]::DarkGreen

    EnabledLoggers = @('detailed','diagnostic','markdown','appveyor')
    LogDirectory = ('{0}\LigerShark\PSBuild\logs\' -f $env:localappdata)
    LastLogDirectory = $null

    TempDirectory = ('{0}\LigerShark\PSBuild\temp\' -f $env:localappdata)

    DefaultClp = '/clp:v=m;Summary'
    ToolsDir = ''
    MarkdownLoggerVerbosity = 'n'
    EnablePropertyQuoting = $true
    PropertyQuotingRegex = '[''.*''|".*"]'
    EnableAppVeyorSupport = $true
    AppVeyorLoggerPath = 'C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll'
    EnableMaskLogFiles = $true
    EnableAddingHashToLogDir = $true
    ContribDirs = @($scriptDir,(Join-Path $scriptDir '..\contrib\'))
}

function InternalOverrideSettingsFromEnv{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [object[]]$settings = ($global:PSBuildSettings),

        [Parameter(Position=1)]
        [string]$prefix = 'PSBuild'
    )
    process{
        foreach($settingsObj in $settings){
            if($settingsObj -eq $null){
                continue
            }

            $settingNames = $null
            if($settingsObj -is [hashtable]){
                $settingNames = $settingsObj.Keys
            }
            else{
                $settingNames = ($settingsObj | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)

            }

            foreach($name in ($settingNames.Clone())){
                $fullname = ('{0}{1}' -f $prefix,$name)
                if(Test-Path "env:$fullname"){
                    'Updating setting [{0}] to [{1}]' -f ($settingsObj.$name),((get-childitem "env:$fullname").Value) | Write-Verbose
                    $settingsObj.$name = ((get-childitem "env:$fullname").Value)
                }
            }
        }
    }
}
InternalOverrideSettingsFromEnv -settings $global:PSBuildSettings -prefix PSBuild

function Get-PSBuildVersion{
    param()
    process{
        New-Object -TypeName 'system.version' -ArgumentList '1.1.11.1'
    }
}

<#
.SYNOPSIS  
	This returns the path to the tools folder. The tools folder is where you can find
    the following files psbuild.dll and it's dependencies. This method will define
    the value in the following sequence.

     1. see if tools dir is defined in $env:PSBuildToolsDir
     2. see if psbuild.dll exists in the same folder
     3. look for the latest version in %localappdata%
#>
function InternalGet-PSBuildToolsDir{
    [cmdletbinding()]
    param()
    process{
        [string]$private:toolsDir = $null

        $private:toolsDir = $global:PSBuildSettings.ToolsDir

        # 1 see if tools dir is defined in $env:PSBuildToolsDir
        if( [string]::IsNullOrWhiteSpace($private:toolsDir) -and $env:PSBuildToolsDir){
            $private:toolsDir = $env:PSBuildToolsDir
            'Assigned ToolsDir based on $env:PSBuildToolsDir to [{0}]' -f ($global:PSBuildSettings.ToolsDir) | Write-Verbose
        }
        # 2 see if psbuild.dll exists in the same folder
        if([string]::IsNullOrWhiteSpace($private:toolsDir)){
            # look for a file named psbuild.dll in the same folder if it's there use that
            $private:filePath = join-path $scriptDir 'psbuild.dll'
            if(test-path $private:filePath){                
                $private:toolsDir = ((Get-Item $private:filePath).Directory.FullName)
                'Assigned ToolsDir to the script folder [{0}]' -f ($private:toolsDir) | Write-Verbose
            }
        }
        # 3 look for the latest version in %localappdata%
        if([string]::IsNullOrWhiteSpace($private:toolsDir)){
            $lsToolsPath = ('{0}\LigerShark\tools\' -f $env:localappdata)
            $psbuildDllUnderAppData = (Get-ChildItem -Path "$lsToolsPath" -Include 'psbuild.dll' -Recurse -ErrorAction SilentlyContinue | Sort-Object -Descending -ErrorAction SilentlyContinue | Select-Object -First 1 -ErrorAction SilentlyContinue)
            if($psbuildDllUnderAppData -and (test-path $psbuildDllUnderAppData)){
                $private:toolsDir = ((get-item ($psbuildDllUnderAppData)).Directory.FullName)
                'Assigned ToolsDir to temp [{0}]' -f ($private:toolsDir) | Write-Verbose
            }
        }
        # warning
        if([string]::IsNullOrWhiteSpace($private:toolsDir)){
            'psbuild tools directory not found'  | Write-Error
        }

        if(!(Test-Path $private:toolsDir)){
            'Creating tools dir at [{0}]' -f $private:toolsDir | Write-Verbose
            New-Item -Path $private:toolsDir -ItemType Directory | Out-Null
        }

        $private:toolsDir
    }
}

$script:envVarTarget='Process'

function Invoke-CommandString{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [string[]]$command,
        
        [Parameter(Position=1)]
        $commandArgs,

        $ignoreErrors,

        [bool]$maskSecrets,

        [switch]$disableCommandQuoting
    )
    process{
        foreach($cmdToExec in $command){
            'Executing command [{0}]' -f $cmdToExec | Write-Verbose
            
            # write it to a .cmd file
            $destPath = "$([System.IO.Path]::GetTempFileName()).cmd"
            if(Test-Path $destPath){Remove-Item $destPath|Out-Null}
            
            try{
                $commandstr = $cmdToExec
                if(-not $disableCommandQuoting -and $commandstr.Contains(' ') -and (-not ($commandstr -match '''.*''|".*"' ))){
                    $commandstr = ('"{0}"' -f $commandstr)
                }

                '{0} {1}' -f $commandstr, ($commandArgs -join ' ') | Set-Content -Path $destPath | Out-Null

                $actualCmd = ('"{0}"' -f $destPath)
                if($maskSecrets){
                    cmd.exe /D /C $actualCmd | Get-FilteredString
                }
                else{
                    cmd.exe /D /C $actualCmd
                }

                if(-not $ignoreErrors -and ($LASTEXITCODE -ne 0)){
                    $msg = ('The command [{0}] exited with code [{1}]' -f $commandstr, $LASTEXITCODE)
                    throw $msg
                }
            }
            finally{
                if(Test-Path $destPath){Remove-Item $destPath -ErrorAction SilentlyContinue |Out-Null}
            }
        }
    }
}

#####################################################################
# Functions relating to msbuild.exe
#####################################################################

<#
.SYNOPSIS  
	This will return the path to msbuild.exe. If the path has not yet been set
	then the highest installed version of msbuild.exe will be returned.

.PARAMETER bitness
    Determines wheter the 32 or 64-bit version of msbuild.exe is returned.
    32 bit is the default.
#>
function Get-MSBuild{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateSet('32bit','64bit')]
        [string]$bitness = '32bit'
    )
    process{
        $path = $script:defaultMSBuildPath

	    if(!$path){
            $regLocalKey = $null

            if($bitness -eq '32bit'){
                $regLocalKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry32)
            }
            if($bitness -eq '64bit'){
                $regLocalKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
            }

            $versionKeyName = $regLocalKey.OpenSubKey('SOFTWARE\Microsoft\MSBuild\ToolsVersions\').GetSubKeyNames() | Sort-Object {[double]$_} -Descending
            $keyToReturn = ('SOFTWARE\Microsoft\MSBuild\ToolsVersions\{0}' -f $versionKeyName)
            
            # return the key value here
            $path = ( '{0}msbuild.exe' -f $regLocalKey.OpenSubKey($keyToReturn).GetValue('MSBuildToolsPath'))
	    }

        return $path
    }
}
<#
.SYNOPSIS  
	This has two purposes:
        1. Create the msbuild alias
        2. Users can specific a specific msbuild.exe which should be used
#>
function Set-MSBuild{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline=$true,Position=0)]
        $msbuildPath,

        [Parameter(Position=1)]
        [bool]$persist=$true
    )

    process{
        if([string]::IsNullOrWhiteSpace($msbuildPath)){
            $script:defaultMSBuildPath = $null
            $msbuildPath = (Get-MSBuild)
        }
        elseif($persist -eq $true){
            'Updating defalut msbuild.exe to point to [{0}]' -f $msbuildPath | Write-Verbose
            $script:defaultMSBuildPath = $msbuildPath
        }

        'Updating msbuild alias to point to [{0}]' -f $msbuildPath | Write-Verbose
        Set-Alias msbuild $msbuildPath
    }
}

<#
.SYNOPSIS
	Can be used to invoke MSBuild. If the msbuildPath parameter is not passed in
    the Get-MSBuild function will be called to determine the version of MSBuild
    which should be used.


.PARAMETER projectsToBuild
    This is the parameter which determines which file(s) will be built. If no value is
    provided then msbuild will look in the current directory for a single solution to
    build. If a a single value is passed in only that item will be processed. If multiple
    values are passed in then all the values will be processed.

    This will accept the pipeline value as well.

    This will accept either a Visual Studio Project File, or a Visual Studio Solution File (*.sln)

.PARAMETER extraArgs
    You can use this to pass in additional parameters to msbuild.exe. This can be
    one of these types:
        [string]
        [hashtable]
    These properties will be added to the end of the call to msbuild.exe so will
    take precedence over other properties.

.PARAMETER properties
    You can pass in a list of properties (hashtable) that should be applied when
    msbuild is called. Each of the items in the hashtable will be passed to
    msbuild.exe. The key of each entry is the name of the property and the
    value for the key will be the value for the msbuild property.

.PARAMETER targets
    The targets that should be passed to msbuild.exe. This can either be a 
    single value or multiple values. Each value will be conveted to a string.

.PARAMETER msbuildPath
    You can specify the specific msbuild.exe that should be used by passing
    in this value. If this is not specified then Get-MSBuild will be used
    to get the path to msbuild.exe.

.PARAMETER toolsVersion
    This allows you to specify the value for /toolsversion. If you do not pass
    this then the parameter will not be passed. Some valid values include:
        3.5
        4.0
        10.0
        11.0
        12.0

.PARAMETER msbuildBitness
    Determines wheter the 32 or 64-bit version of msbuild.exe is returned.
    32 bit is the default.

.PARAMETER visualStudioVersion
    This will set the VisualStudioVersion MSBuild parameter. Typical values for this include:
        10.0
        11.0
        12.0
        14.0

.PARAMETER Configuration
    This sets the MSBuild property Configuration to the value specified. This will override any value
    in properties or defaultProperties.

.PARAMETER Platform
    This sets the MSBuild property Platform to the value specified. This will override any value
    in properties or defaultProperties.

.PARAMETER textToMask
    This is an array of strings that will be masked (i.e. hidden) from the PowerShell output
    when the build is running. You can use this for connection strings or passwords, etc. so that
    they are not displayed in the PowerShell console. You can also set global values using
    the $global:FilterStringSettings.GlobalReplacements array which will apply to every build.
    You can also control which PowerShell cmdlets are overridden with 
    $global:FilterStringSettings.WriteFunctionsToCreate. The default list is:
    'Out-Default','Write-Output','Write-Host','Write-Debug','Write-Error','Write-Warning','Write-Verbose','Out-Host','Out-String'

.PARAMETER nologo
    When set this passes the /nologo switch to msbuild.exe.

.PARAMETER preprocess
    When set passses the /preprocess switch to msbuild.exe.

.PARAMETER detailedSummary
    When set passses the /detailedSummary switch to msbuild.exe.

.PARAMETER defaultProperties
    This can be used to set default property values. A default property is the value that
    will be returned for a property if there is no value for that property defined.
    This is implemented by setting environment variables at the process level before
    msbuild.exe is invoked and re-setting them after it has completed.

.PARAMETER maxcpucount
    The value for the /maxcpucount (/m) parameter. If this is not provided '/m' will be used.
    If you want to disable this then pass in the value 1 to execute on one core.

.PARAMETER enabledLoggers
    Can be used to turn on or off specific loggers. It's a string array that contains the loggers
    to enable. The three valid options are detailed, diagnostic and markdown. All other values are
    ignored. So if you just want a detailed logger pass -enabledLoggers detailed and
    -enableLoggers @('detailed','diagnostic') for detailed and diagnostic. The default value for
    this is @('detailed','diagnostic','markdown') and can be overridden in $global:PSBuildSettings.EnabledLoggers.

.PARAMETER noLogFiles
    You can use this to disable logging to files for this call to Invoke-MSBuild. Note: you can also
    enable/disable log file generation via a global flag $global:PSBuildSettings.EnableBuildLogging.
    If that is set to false this parameter is ignored and log files will not be written.

.PARAMETER ignoreExitCode
    By default if msbuild.exe exists with a non-zeor exit code the script will throw an exception.
    You can prevent this by passing in -ignoreExitCode.

.PARAMETER disablePropertyQuoting
    By default if you pass a property via -Properties which has a space the property will be surrounded
    with single quotes (') if the value is not already surrounded with single quotes (') or double quotes (")
    if the property value has a space in it. You can disable this by passing this property. You can disable
    this globally with the setting $global:PSBuildSettings.PropertyQuotingRegex.

.EXAMPLE
    Invoke-MSBuild C:\temp\msbuild\msbuild.proj
    Shows how you can build a project.

.EXAMPLE
    Invoke-MSBuild C:\temp\msbuild\msbuild.sln
    Shows how you can build a solution.

.EXAMPLE
    Invoke-MSBuild C:\temp\msbuild\msbuild.proj -configuration Release -visualStudioVersion 12.0
    You can easily pass in the value for the Configuraiton and VisualStudioVersion MSBuild properties.

.EXAMPLE
    Invoke-MSBuild C:\temp\msbuild\msbuild.proj -configuration Release -platform AnyCPU
    You can easily pass in the value for the Configuraiton and Platform MSBuild properties.

.EXAMPLE
    Invoke-MSBuild @('C:\temp\msbuild\proj1.proj';'C:\temp\msbuild\proj2.proj')
    Shows how you can easily build more than one project.

.EXAMPLE
    @('C:\temp\msbuild\proj1.proj';'C:\temp\msbuild\proj2.proj') | Invoke-MSBuild

.EXAMPLE
    @((get-item C:\temp\msbuild\proj1.proj);'C:\temp\msbuild\proj2.proj') | Invoke-MSBuild

.EXAMPLE
    Invoke-MSBuild C:\temp\msbuild\path.proj -properties (@{'foo'='bar';'visualstudioversion'='12.0'}) -extraArgs '/nologo'

.EXAMPLE
    $projects = @()
    $projects += (get-item C:\temp\msbuild\proj1.proj)
    $projects += 'C:\temp\msbuild\proj1.proj'
    Invoke-MSBuild $projects
    $projects | Invoke-MSBuild

.EXAMPLE
    Invoke-MSBuild .\ConsoleApplication1.csproj -visualStudioVersion 12.0  -nologo -preprocess | 
    Set-Content c:\temp\msbuild-pp.txt | 
    start c:\temp\msbuild-pp.txt

.EXAMPLE
    Invoke-MSBuild $defProps -defaultProperties @{'Configuration'='Release'}

.EXAMPLE
    Invoke-MSBuild myproj.csproj -enabledLoggers detailed
    Builds and creates just a detailed log

.EXAMPLE
    Invoke-MSBuild myproj.csproj -enabledLoggers @('detailed','markdown')
    Builds and creates just a detailed and markdown log
#>
function Invoke-MSBuild{
    [cmdletbinding(
        SupportsShouldProcess=$true,
        DefaultParameterSetName ='build')]
    param(
        [Parameter(ParameterSetName='build',Position=1,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='debugMode',Mandatory=$true,Position=1,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='preprocess',Position=1,ValueFromPipeline=$true)]
        [alias('proj')]
        [string[]]$projectsToBuild,
        
        [Parameter(ParameterSetName='build')]
        [ValidateScript({Test-Path $_})]
        [string]$msbuildPath,
        
        [ValidateSet('32bit','64bit')]
        [string]$msbuildBitness = '32bit',

        [alias('tv')]
        [string]$toolsVersion,

        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [alias('p')]
        [Hashtable]$properties,
        
        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [alias('t')]
        [string[]]$targets,
        
        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [ValidateSet('10.0','11.0','12.0','14.0')]
        [alias('vsv')]
        [string]$visualStudioVersion,
        
        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [string]$configuration,

        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [string]$platform,

        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [string]$outputPath,

        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [string]$deployOnBuild,

        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [string]$publishProfile,

        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [string]$password,

        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [array]$textToMask,

        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [alias("m")]
        [int]$maxcpucount,
        
        [Parameter(ParameterSetName='build')]
        [alias('nl')]
        [switch]$nologo,

        [Parameter(ParameterSetName='preprocess')]
        [alias('pp')]
        [switch]$preprocess,

        [Parameter(ParameterSetName='build')]
        [alias('ds')]
        [switch]$detailedSummary,

        [Parameter(ParameterSetName='build')]
        [Parameter(ParameterSetName='debugMode')]
        [alias('dp')]
        [hashtable]$defaultProperties,

        [Parameter(ParameterSetName='build')]
        [alias('clp')]
        [string]$consoleLoggerParams = $global:PSBuildSettings.DefaultClp,

        [Parameter(ParameterSetName='build')]
        [switch]$ignoreExitCode,

        [Parameter(ParameterSetName='build')]
        [string[]]$enabledLoggers = ($global:PSBuildSettings.EnabledLoggers),

        [Parameter(ParameterSetName='build')]
        [switch]$noLogFiles,

        [Parameter(ParameterSetName='build')]
        [switch]$disablePropertyQuoting,

        [Parameter(ParameterSetName='build')]
        [string]$extraArgs,

        [Parameter(ParameterSetName='debugMode')]
        [switch]$debugMode
    )

    begin{
        Add-Type -AssemblyName Microsoft.Build
        if($defaultProperties){
            $defaultProperties | PSBuildSet-TempVar
        }

        if(![string]::IsNullOrWhiteSpace($password)){
            if($textToMask -eq $null){
                $textToMask = @()
            }
            $textToMask += $password
        }

        if($textToMask){
            $script:BuildTextToMask = $textToMask
        }
    }

    end{
        if($defaultProperties){
            PSBuildReset-TempEnvVars
        }

        if( ($global:PSBuildSettings.EnableBuildLogging) -and !($noLogFiles) -and !($debugMode)) {
            "`n>>>> Build completed you can use Open-PSBuildLog to open the log file" | Write-BuildMessage -strong
        }

        $script:BuildTextToMask = [array]@()
    }

    process{
        if([string]::IsNullOrWhiteSpace($msbuildPath)){
            $msbuildPath = (Get-MSBuild -bitness $msbuildBitness)
        }
        # If we weren't provided a project to build, insert a dummy entry into the array
        # to fall back to msbuild default behaviour.
        if ($projectsToBuild -eq $null){
            $projectsToBuild = @($null)
        }
        foreach($project in $projectsToBuild){
            try{
                $msbuildArgs = @()

                [string]$projArg = [string]$project
                if(![string]::IsNullOrWhiteSpace($projArg)){
                    $projArg = ('"{0}"' -f $projArg)
                }

                $msbuildArgs += ([string]$projArg)

                if(-not $properties){
                    $properties = @{}
                }

                if($toolsversion){
                    $msbuildArgs += ('/toolsversion:{0}' -f $toolsversion)
                }

                if($visualStudioVersion){
                    $properties['VisualStudioVersion']=$visualStudioVersion
                }
                if($configuration){
                    $properties['Configuration']=$configuration
                }
                if($platform){
                    $properties['Platform']=$platform
                }
                if($outputPath){
                    $properties['OutputPath']=$outputPath
                }
                if($deployOnBuild){
                    $properties['DeployOnBuild']=$deployOnBuild.ToString()
                }
                if($publishProfile){
                    $properties['PublishProfile']=$publishProfile
                }
                if($password){
                    $properties['Password']=$password
                }

                if($properties){
                    foreach($key in $properties.Keys){
                        $value=$properties[$key]
                        if(!($value)){
                            continue;
                        }
                        else{
                            $valueStr = $value
                            if(($valueStr -match '\s') -and
                                $global:PSBuildSettings.EnablePropertyQuoting -and 
                                !($disablePropertyQuoting)){
                                # if it's already quoted don't add quotes
                                if(!($value -match $global:PSBuildSettings.PropertyQuotingRegex)){
                                    $valueStr = ('"{0}"' -f $value.Replace('"','""'))
                                }
                            }
                        
                            $msbuildArgs += ('/p:{0}={1}' -f $key, $valueStr)
                        }
                    }
                }

                if($targets){
                    foreach($target in $targets){
                        $msbuildArgs += ('/t:{0}' -f $target)
                    }
                }

                if($nologo){
                    $msbuildArgs += '/nologo'
                }

                if($preprocess){
                    $msbuildArgs += '/preprocess'
                }

                if($detailedSummary){
                    $msbuildArgs += '/detailedsummary'
                }

                if($maxcpucount){
                    $msbuildArgs += ('/m:{0}' -f $maxcpucount)
                }
                else{
                    $msbuildArgs += ('/m')
                }

                if($consoleLoggerParams){
                    $msbuildArgs += $consoleLoggerParams
                }

                if($extraArgs){
                    foreach($exArg in $extraArgs){
                        $msbuildArgs += $exArg
                    }
                }

                if($global:PSBuildSettings.EnableBuildLogging -and !($noLogFiles)){
                    $logDir = $global:PSBuildSettings.LastLogDirectory = (Get-PSBuildLogDirectory -projectPath $project)

                    Get-ChildItem $logDir *.log* | Remove-Item -ErrorAction SilentlyContinue | Out-Null

                    $loggers = (InternalGet-PSBuildLoggers -projectPath $project -enabledLoggers $enabledLoggers)
                    foreach($logger in $loggers){
                        $msbuildArgs += $logger
                    }
                }

                if($pscmdlet.ShouldProcess("`n`tmsbuild.exe {0}" -f ($msbuildArgs -join ' '))){
                    if(-not $debugMode){
                        if(!$script:defaultMSBuildPath){
                            'Using msbuild.exe from "{0}". You can use Set-MSBuild to update this.' -f $msbuildPath | Write-BuildMessage
                        }

                        if( ($env:APPVEYOR -eq $true) -and (get-command Add-AppveyorMessage -ErrorAction SilentlyContinue) ){
                            [string]$projstr = $projArg
                            if([string]::IsNullOrWhiteSpace($projstr)){
                                $projstr = '(project not specified)'
                            }
                            $avmsg = (Get-FilteredString -message ('Building projects {0}' -f $projstr))
                            $avdetails = (Get-FilteredString -message ('"{0}" {1}' -f $msbuildPath, ($msbuildArgs -join ' ' )))
                            Add-AppveyorMessage -Message $avmsg -Category Information -Details $avdetails -ErrorAction SilentlyContinue | Out-NUll
                        }

                        $invokeargs = @{'command'=$msbuildPath;'commandArgs'=$msbuildArgs;'maskSecrets'=(HasSecretsToMask -textToMask $textToMask -password $password );'ignoreErrors'=$ignoreExitCode}
                        Invoke-CommandString @invokeargs | Get-FilteredString
                    }
                    else{
                        # in debug mode we call msbuild using the APIs
                        Add-Type -AssemblyName Microsoft.Build
                        $globalProps = (PSBuild-ConverToDictionary -valueToConvert $properties)
                        $pc = (New-Object -TypeName Microsoft.Build.Evaluation.ProjectCollection -ArgumentList $globalProps)

                        # todo: add loggers
                        # $conLogger = New-Object -TypeName Microsoft.Build.Logging.ConsoleLogger
                        # $conLogger.Verbosity = [Microsoft.Build.Framework.LoggerVerbosity]::Detailed
                        # 'Registering logger' | Write-Host
                        # $pc.RegisterLogger($conLogger)

                        $projectObj = $pc.LoadProject((Resolve-Path $project))

                        $projectInstance = $projectObj.CreateProjectInstance()

                        # PS will convert null strings to '' which causes some APIs to fail.
                        # This is the best way I've found to work around this.
                        if($PSBoundParameters.ContainsKey('targets')){
                            $brd = New-Object -TypeName Microsoft.Build.Execution.BuildRequestData -ArgumentList @($projectInstance, ([string[]](@()+$targets)), [Microsoft.Build.Execution.HostServices]$null, [Microsoft.Build.Execution.BuildRequestDataFlags]::ProvideProjectStateAfterBuild)
                        }
                        else{
                            $brd = New-Object -TypeName Microsoft.Build.Execution.BuildRequestData -ArgumentList @($projectInstance, ([string[]]@()), [Microsoft.Build.Execution.HostServices]$null, [Microsoft.Build.Execution.BuildRequestDataFlags]::ProvideProjectStateAfterBuild)
                        }

                        $buildResult = [Microsoft.Build.Execution.BuildManager]::DefaultBuildManager.Build(
                            (New-Object -TypeName Microsoft.Build.Execution.BuildParameters -ArgumentList $pc),
                            $brd)

                        $postBuildProjFilePath = (Join-Path -Path $logDir -ChildPath (Get-Item $project).Name)
                        'Saving post build project file to: [{0}]' -f $postBuildProjFilePath | Write-Verbose
                        $projectInstance.ToProjectRootElement().Save($postBuildProjFilePath) | Out-Null

                        $psbuildResult = New-PSBuildResult -buildResult $buildResult -projectInstance $projectInstance -postBuildProjectFile $postBuildProjFilePath
                    
                        $script:lastDebugBuildResult = $psbuildResult

                        return $psbuildResult
                    }
                }
            }
            catch{
                throw ("{0}`r`n{1}" -f ($_.Exception.ToString()|Get-FilteredString), (Get-PSCallStack|Out-String|Get-FilteredString))
            }
            finally{                
                if( ($global:PSBuildSettings.EnableBuildLogging -and !($noLogFiles)) -and
                    ($global:PSBuildSettings.EnableMaskLogFiles -eq $true) -and (HasSecretsToMask -textToMask $textToMask -password $password)){
                    # replace secrets in log files
                    Import-FileReplacer

                    $replacements = @{}

                    $allTextToMask = New-Object System.Collections.Generic.List[System.String]
                    foreach($str in $textToMask){
                        if(-not [string]::IsNullOrWhiteSpace($str) -and (-not ($replacements.ContainsKey($str)) )) {
                            $replacements.Add($str,$global:FilterStringSettings.DefaultMask)
                        }
                    }
                    if(-not [string]::IsNullOrWhiteSpace($password) -and (-not ($replacements.ContainsKey($password)) )) {
                        $replacements.Add($password,$global:FilterStringSettings.DefaultMask)
                    }
                    foreach($str in $global:FilterStringSettings.GlobalReplacements){
                        if(-not [string]::IsNullOrWhiteSpace($str) -and (-not ($replacements.ContainsKey($password))) ) {
                            $replacements.Add($str,$global:FilterStringSettings.DefaultMask)
                        }
                    }

                    Replace-TextInFolder -folder $logDir -replacements $replacements -include '*'
                }
            }
        }
    }
}
Set-Alias psbuild Invoke-MSBuild

function HasSecretsToMask{
    [cmdletbinding()]
    param(
        [array]$textToMask,
        [string]$password
    )
    process{
        [bool]$hasSecrets = $false

        if($textToMask -ne $null){
            foreach($text in $textToMask){
                if(-not [string]::IsNullOrWhiteSpace($textToMask)){
                    $hasSecrets = $true
                    break
                }
            }
        }

        if($global:FilterStringSettings.GlobalReplacements -ne $null){
            foreach($text in $global:FilterStringSettings.GlobalReplacements){
                if(-not [string]::IsNullOrWhiteSpace($textToMask)){
                    $hasSecrets = $true
                    break
                }
            }
        }

        if(-not [string]::IsNullOrWhiteSpace($password)){
            $hasSecrets = $true
        }

        # return the value to the caller
        $hasSecrets
    }
}

<#
.SYNOPSIS
    When you call Invoke-MSBuild with the -debugMode flag an object is returned that is the build result.
    If you did not save this object you can use this method to reterive that last build result.

.EXAMPLE
    $lastResult = Get-PSBuildLastDebugBuildResult
#>
function Get-PSBuildLastDebugBuildResult{
    [cmdletbinding()]
    param()
    process{
        return $script:lastDebugBuildResult
    }
}

<#
.SYNOPSIS
    If the last call to Invoke-MSBuild used the -debugMode then this can be used to get the "post build"
    representation of the project file. This is essentially the representation of the project that MSBuild
    has in memory for the project at the end of the build.

.EXAMPLE
    Get-PSBuildPostBuildResult
#>
function Get-PSBuildPostBuildResult{
    [cmdletbinding()]
    param()
    process{
        return ((Get-PSBuildLastDebugBuildResult).PostBuildProjectFile)
    }
}

function New-PSBuildResult{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$true)]
        [Microsoft.Build.Execution.BuildResult]
        $buildResult,

        [Parameter(
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$true)]
        [Microsoft.Build.Execution.ProjectInstance]
        $projectInstance,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        $postBuildProjectFile
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $result = New-Object PSObject -Property @{
            BuildResult = $buildResult

            ProjectInstance = $projectInstance
        }

        $result | Add-Member -MemberType ScriptMethod -Name EvalProperty -Value {
            [cmdletbinding()]
            param(
                [Parameter(
                    Mandatory=$true)]
                [string]
                $propName)
            if($this.ProjectInstance){
                $this.ProjectInstance.GetPropertyValue($propName)
            }
            else{
                'project is null'
            }
        }

        $result | Add-Member -MemberType ScriptMethod -Name EvalItem -Value {
            [cmdletbinding()]
            param(
                [Parameter(
                    Mandatory=$true)]
                [string]
                $propName)
            if($this.ProjectInstance){
                # todo: is there a better way to do this?
                $expressionToEval = ('@({0})' -f $propName)
                return $this.ProjectInstance.ExpandString($expressionToEval)
            }
            else{
                'project is null'
            }
        }

        $result | Add-Member -MemberType ScriptMethod ExpandString -Value {
            [cmdletbinding()]
            param(
                [Parameter(
                    Mandatory=$true)]
                [string]
                $unexpandedValue
            )
            process{
                if($this.ProjectInstance){
                    return $this.ProjectInstance.ExpandString($unexpandedValue)
                }
                else{
                    'project is null'
                }
            }
        }

        $result | Add-Member -MemberType NoteProperty -Name PostBuildProjectFile -Value $postBuildProjectFile

        return $result
    }
}

<#
.SYNOPSIS  
	Will return the directory where psbuild will write msbuild log files to while invoking builds.

.EXAMPLE
    $logDir = Get-PSBuildLogDirectory

.EXAMPLE
    'C:\temp\msbuild\new\new.proj' | Get-PSBuildLogDirectory
#>
function Get-PSBuildLogDirectory{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            ValueFromPipeline=$true)]
        $projectPath)
    process{
        if($global:PSBuildSettings.LogDirectory){
            $logDir = $global:PSBuildSettings.LogDirectory
        
            if($projectPath){
                $itemResult = (Get-Item $projectPath)

                $projFileName = ((Get-Item $projectPath).Name)
                $logDir = $null
                if($global:PSBuildSettings.EnableAddingHashToLogDir -and (-not [string]::IsNullOrWhiteSpace($projectPath))) {
                    $projfullpath = (Get-Item $projectPath).FullName
                    $projfilepathhash = Get-StringHash -text $projfullpath
                    $logDir = (Join-Path -Path ($global:PSBuildSettings.LogDirectory) -ChildPath ('{0}-{1}-log\' -f $projFileName,$projfilepathhash) )
                }
                else{
                    $logDir = (Join-Path -Path ($global:PSBuildSettings.LogDirectory) -ChildPath ('{0}-log\' -f $projFileName) )
                }
            }

            # before returning ensure the log directory is created on disk
            if(!(Test-Path -Path $logDir) ){
                'Creating PSBuild log directory at [{0}]' -f $logDir | Write-Verbose
                mkdir $logDir | Out-Null
            }

            return $logDir
        }
        else{
            return $null   
        }
    }
}

#http://jongurgul.com/blog/get-stringhash-get-filehash/
Function Get-StringHash{
    [cmdletbinding()]
    param(
        [String] $text,
        $HashName = "MD5"
    )
    process{
        $sb = New-Object System.Text.StringBuilder
        [System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))|%{
                [Void]$sb.Append($_.ToString("x2"))
            }
        $sb.ToString()
    }
}

function Open-PSBuildLogDirectory{
    [cmdletbinding()]
    param()
    process{
        start (Get-PSBuildLogDirectory)
    }
}

<#
.SYNOPSIS  
	Used to set the directory where psbuild will keep msbuild log files.

.EXAMPLE
    Set-PSBuildLogDirectory -logDirectory 'C:\temp\logs2'
#>
function Set-PSBuildLogDirectory{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            ValueFromPipeline=$true)]
        [string]
        $logDirectory
    )
    process{
        if($logDirectory){
            # ensure that it ends with a slash
            if(!($logDirectory.EndsWith('\')) -and !($logDirectory.EndsWith('/'))){
                # add a trailing slash
                $logDirectory += '\'
            }
            $global:PSBuildSettings.LogDirectory = $logDirectory
        }
        else{
            # reset the log directory
            $global:PSBuildSettings.LogDirectory = ('{0}\LigerShark\PSBuild\logs\' -f $env:localappdata)
        }
    }
}

<#
.SYNOPSIS  
	This will open the last log file in the default editor.
    Typically log files are written with the .log extension so whatever application is associated
    with the .log extension will open the log.

.EXAMPLE
    Open-PSBuildLog
    Open the last default log file (typically detailed verbosity)    

.EXAMPLE
    Open-PSBuildLog markdown
    Opens the last log file in markdown format

.EXAMPLE
    Open-PSBuildLog diagnostic
    Opens the last diagnostic log file

.EXAMPLE
    Open-PSBuildLog detailed
    Opens the last detailed log file. Note: this is the default.

#>
function Open-PSBuildLog{
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeLine=$true,Position=0)]
        [ValidateSet('markdown','detailed','diagnostic')]
        $format,

        [switch]$returnFilePathInsteadOfOpening
    )
    process{
        $private:logDir = $global:PSBuildSettings.LastLogDirectory

        if(![string]::IsNullOrEmpty($format)){
            $private:filename = ('msbuild.{0}.log' -f $format)
                
            if($format -eq 'markdown'){
                $private:filename = ('msbuild.{0}.log.md' -f $format)
            }
            $logFiles = (get-item (join-path $private:logDir $private:filename))
        }
        else{
            if($private:logDir){
                $allFiles =  (Get-ChildItem $private:logDir | Where-Object {$_.PSIsContainer -eq $false} | Sort-Object LastWriteTime | Sort-Object Name)
                $logFiles = $allFiles[0]
            }
            else{
                '$global:PSBuildSettings.LastLogDirectory is empty, no recent logs' | Write-Verbose
            }
        }

        foreach($file in $logFiles){
            if($returnFilePathInsteadOfOpening){
                $file.FullName
            }
            else{
                start ($file.FullName)
            }
        }
    }
}

<#
.SYNOPSIS  
    Method used to get the logger strings that should be appened to the bulid process.

.DESCRIPTION
This will return an array of strings for loggers that should be added to the build process.

    There will be up to 3 values in the result, which are the following.
     - $result[0] = Detailed log
     - $result[1] = Diagnostic log
     - $result[2] = Markdown log

Here are the default loggers that psbuild will use.
    /flp1:v=d;logfile=C:\Users\Sayed\AppData\Local\PSBuild\logs\proj1.proj-log\msbuild.detailed.log 
    /flp2:v=diag;logfile=C:\Users\Sayed\AppData\Local\PSBuild\logs\proj1.proj-log\msbuild.diagnostic.log
    /logger:MarkdownLog,C:\Users\Sayed\AppData\Local\LigerShark\tools\psbuild.0.0.2-beta\tools\MarkdownLog.dll;v=d;logfile=C:\Users\Sayed\AppData\Local\PSBuild\logs\proj1.proj-log\msbuild.markdown.log
#>
function InternalGet-PSBuildLoggers{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            ValueFromPipeline=$true)]
        $projectPath,

        [Parameter(Position=2)]
        $enabledLoggers = ($global:PSBuildSettings.EnabledLoggers)
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{  
        [string]$logDir = (Get-PSBuildLogDirectory -projectPath $projectPath)
        [string]$toolsDir = InternalGet-PSBuildToolsDir
        [string]$projName = if($projectPath) {(get-item $projectPath).BaseName} else{''}

        $private:loggers = @()

        # {0} log directory
        # {1} name of the file being built
        # {2} timestamp property
        # {3} tools directory
        if($enabledLoggers -contains 'detailed'){
            $private:loggers += '/flp1:v=d;logfile="{0}msbuild.detailed.log"'
        }
        if($enabledLoggers -contains 'diagnostic'){
            $private:loggers += '/flp2:v=diag;logfile="{0}msbuild.diagnostic.log"'
        }

        if($enabledLoggers -contains 'markdown'){
            $mdLoggerBinaryPath = join-path $toolsDir 'psbuild.dll'
            if(test-path $mdLoggerBinaryPath){
                $private:loggers += ('/logger:MarkdownLogger,"{3}\psbuild.dll";v=n;logfile="{0}msbuild.markdown.log.md"') #;v=' + $global:PSBuildSettings.MarkdownLoggerVerbosity + '"')
                'Adding markdown logger to the build' | write-verbose
            }
            else{
                'Not adding markdown logger because it was not found in the expected location [{0}]' -f $mdLoggerBinaryPath | write-verbose
            }
        }

        if(  $env:APPVEYOR -eq $true -and
            ($enabledLoggers -contains 'appveyor') -and
            ($global:PSBuildSettings.EnableAppVeyorSupport -eq $true) -and
            (Test-Path $global:PSBuildSettings.AppVeyorLoggerPath) ){

            $private:loggers += ('/logger:"{0}"' -f $global:PSBuildSettings.AppVeyorLoggerPath)
        }

        $loggersResult = @()

        foreach($loggerToAdd in $private:loggers){            
            [string]$dateStr = (Get-Date -format yyyy-MM-dd.h.m.s)            

            $loggerStr = ($loggerToAdd -f $logDir, $projName,$dateStr,$toolsDir)
            $loggersResult += $loggerStr
        }

        return $loggersResult
    }
}

<#
.SYNOPSIS
    This is a convience method to show the common MSBuild escape characters.
#>
function Get-MSBuildEscapeCharacters{
    [cmdletbinding()]
    param()
    process{
        $resultList = @()
        $resultList += @{'  %'='%25'}
        $resultList += @{'  $'='%24'}
        $resultList += @{'  @'='%40'}
        $resultList += @{"  '"='%27'}
        $resultList += @{'  ;'='%3B'}
        $resultList += @{'  ?'='%3F'}
        $resultList += @{'  *'='%2A'}
        $resultList += @{'  ('='%28'}
        $resultList += @{'  )'='%29'}
        $resultList += @{'  "'='%22'}

        return $resultList
    }
}

function Get-MSBuildReservedProperties{
    [cmdletbinding()]
    param()
    process{
        # see if the file exists in the temp directory
        $reservedPropsProjFile = ('{0}reservedprops-v1.proj' -f $global:PSBuildSettings.TempDirectory)
        if(!(Test-Path $reservedPropsProjFile)){
            Create-MSBuildReservedPropertiesFile -filePath $reservedPropsProjFile
        }

        # call it
        Invoke-MSBuild $reservedPropsProjFile -consoleLoggerParams '/clp:v=n' -nologo
    }
}

function Create-MSBuildReservedPropertiesFile{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        $filePath
    )
    process{

    if(!(Test-Path $global:PSBuildSettings.TempDirectory)){
        New-Item $global:PSBuildSettings.TempDirectory -ItemType Directory
    }

@'
<Project ToolsVersion="4.0" DefaultTargets="PrintValues" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">

  <Target Name="PrintValues">
    <Message Text="MSBuild:                        $(MSBuild)"/>
    <Message Text="MSBuildBinPath:                 $(MSBuildBinPath)"/>
    <Message Text="MSBuildExtensionsPath:          $(MSBuildExtensionsPath)"/>
    <Message Text="MSBuildExtensionsPath32:        $(MSBuildExtensionsPath32)"/>
    <Message Text="MSBuildExtensionsPath64:        $(MSBuildExtensionsPath64)"/>
    <Message Text="MSBuildLastTaskResult:          $(MSBuildLastTaskResult)"/>
    <Message Text="MSBuildNodeCount:               $(MSBuildNodeCount)"/>
    <Message Text="MSBuildOverrideTasksPath:       $(MSBuildOverrideTasksPath)"/>
    <Message Text="MSBuildProgramFiles32:          $(MSBuildProgramFiles32)"/>
    <Message Text="MSBuildProjectDefaultTargets:   $(MSBuildProjectDefaultTargets)"/>
    <Message Text="MSBuildProjectDirectory:        $(MSBuildProjectDirectory)"/>
    <Message Text="MSBuildProjectDirectoryNoRoot:  $(MSBuildProjectDirectoryNoRoot)"/>
    <Message Text="MSBuildProjectExtension:        $(MSBuildProjectExtension)"/>
    <Message Text="MSBuildProjectFile:             $(MSBuildProjectFile)"/>
    <Message Text="MSBuildProjectFullPath:         $(MSBuildProjectFullPath)"/>
    <Message Text="MSBuildProjectName:             $(MSBuildProjectName)"/>
    <Message Text="MSBuildStartupDirectory:        $(MSBuildStartupDirectory)"/>
    <Message Text="MSBuildThisFile:                $(MSBuildThisFile)"/>
    <Message Text="MSBuildThisFileDirectory:       $(MSBuildThisFileDirectory)"/>
    <Message Text="MSBuildThisFileDirectoryNoRoot: $(MSBuildThisFileDirectoryNoRoot)"/>
    <Message Text="MSBuildThisFileExtension:       $(MSBuildThisFileExtension)"/>
    <Message Text="MSBuildThisFileFullPath:        $(MSBuildThisFileFullPath)"/>
    <Message Text="MSBuildThisFileName:            $(MSBuildThisFileName)"/>
    <Message Text="MSBuildToolsPath:               $(MSBuildToolsPath)"/>
    <Message Text="MSBuildToolsVersion:            $(MSBuildToolsVersion)"/>
  </Target>

</Project>
'@ | Set-Content -Path $filePath
    }
}

#####################################################################
# Functions for interacting with MSBuild files.
#####################################################################

<#
.SYNOPSIS
	You can use this to create a new MSBuild project. If you specify a value for the
    $filePath parameter then the project file will saved to the specificed location.
    Otherwise an in-memory project file is created an returned to the caller.

.PARAMETER filePath
    An optional parameter. If passed in the project file will be saved to the given location.
#>

function New-MSBuildProject{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        $filePath,

        [string]$toolsVersion
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }

    process{
        # if toolsversion is empty pick the highest tools version on the machine
        if([string]::IsNullOrEmpty($toolsVersion)){
            $regLocalKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry32)
            $toolsVersion = ($regLocalKey.OpenSubKey('SOFTWARE\Microsoft\MSBuild\ToolsVersions\').GetSubKeyNames() | Sort-Object {[double]$_} -Descending |Select-Object -First 1)
        }
        $newProj = [Microsoft.Build.Construction.ProjectRootElement]::Create()
        $newProj.ToolsVersion = $toolsVersion

        if($filePath){
            Save-MSBuildProject -project $newProj -filePath $filePath | Out-Null
        }

        return $newProj
    }
}

<#
.SYNOPSIS
	Can be used to save the MSBuild project to a file.
    After the project is saved $project will be returned.

.OUTPUTS
    Microsoft.Build.Construction.ProjectRootElement. Returns the object
    passed in the $project parameter.
#>
function Save-MSBuildProject{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline = $true)]
        $project,

        [Parameter(
            Position=2,
            Mandatory=$true)]
        $filePath
    )

    begin{
        Add-Type -AssemblyName Microsoft.Build
    }

    process{
        # not working as expected, making $filePath mandatory again
        #if(-not $filePath){
        #    $filePath = $project.Location
        #}

        $fullPath = (Get-Fullpath -path $filePath)
        $project.Save([string]$fullPath)
        return $project
    }
}

<#
.SYNOPSIS
    Can be used to convert a relative path (i.e. .\project.proj) to a full path.
#>
function Get-Fullpath{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline = $true)]
        $path,

        $workingDir = ($pwd)
    )
    process{
        $fullPath = $path
        $oldPwd = $pwd

        Push-Location
        Set-Location $workingDir
        [Environment]::CurrentDirectory = $pwd
        $fullPath = ([System.IO.Path]::GetFullPath($path))
        
        Pop-Location
        [Environment]::CurrentDirectory = $oldPwd

        return $fullPath
    }
}

<#
.SYNOPSIS
    This can be used to open an MSBuild projcet file.
    The object returned is of type Microsoft.Build.Construction.ProjectRootElement.

    You can get the project either from a file or from an object. Regarding the from an existing
    object if the passed in is a ProjectRootElement it will be returned, and otherwise the
    value for $sourceObject.ContainingProject is returned. This is useful to enable
    pipeline continuations based on the return type of the previous function call.

.OUTPUTS
    [Microsoft.Build.Construction.ProjectRootElement]

.EXAMPLE
    Get-MSBuildProject -projectFile 'C:\temp\msbuild\new\new.proj'

.EXAMPLE
    Get-MSBuildProject -projectFile 'C:\temp\msbuild\new\new.proj' | 
        Find-PropertyGroup -labelValue second | 
        Remove-Property -name Configuration |
        Get-MSBuildProject | 
        Save-MSBuildProject -filePath $projFile
#>
function Get-MSBuildProject{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1)]
        $projectFile,

        [Parameter(
            ValueFromPipeline=$true)]
        $sourceObject,
        
        $projectCollection = (New-Object Microsoft.Build.Evaluation.ProjectCollection)
    )
    begin{
        Add-Type -AssemblyName System.Core
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $project = $null
        if($projectFile){
            $fullPath = (Get-Fullpath $projectFile)
            $project = ([Microsoft.Build.Construction.ProjectRootElement]::Open([string]$fullPath,$projectCollection))
        }
        elseif($sourceObject -is [Microsoft.Build.Construction.ProjectRootElement]){
            $project = $sourceObject
        }
        else{
            $project = $sourceObject.ContainingProject
        }
        return $project
    }
}

#####################################################################
# Functions for manipulating MSBuild files
#####################################################################
<#
.SYNOPSIS
    Can be used to determine if the project file passed in has a specific import. 
    It can search for the import either by the value for the Label attribute or 
    the Project attribute. This is determined by the parameters passed in. 
    If both labelValue an projectValue are passed in then labelValue will take precedence.
#>
function Test-Import{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $project,
        $labelValue,
        $projectValue
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $foundImport = (Find-Import -project $project -labelValue $labelValue -projectValue $projectValue)

        $wasFound = $false
        if(-not $foundImport){
            $wasFound = $false
        }
        else{
            $wasFound = $true
        }

        return $wasFound
    }
}
<#
.SYNOPSIS
    Can be used to find imports in an MSBuild file. You can find by looking for the 
    Import by either the Label value or the value for Project. This is determined 
    by the parameters passed in. If both labelValue an projectValue are passed 
    in then labelValue will take precedence.
#>
function Find-Import{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $project,
        $labelValue,
        $projectValue,
        [switch]
        $stopOnFirstResult
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        "Looking for an import, label=[{0}], projet=[{0}]" -f $labelValue,$projectValue | Write-Verbose

        if(!($labelValue) -and !($projectValue)){
            "Both parameters labelValue and projectValue are empty. Not searching for imports." | Write-Warning
            return;
        }

        # $project can either be a ProjectRootElement object or a string
        [Microsoft.Build.Construction.ProjectRootElement]$realProject = $null
        if($project -is [Microsoft.Build.Construction.ProjectRootElement]){
            $realProject = $project
        }
        else{
            $realProject = (Get-MSBuildProject -projectFile ([string]$project))
        }
        $foundImports = @()
        foreach($import in $realProject.Imports){
            [string]$projectStr = if($import.Project){$import.Project} else{''}
            [string]$labelStr = if($import.Label){$import.Label} else{''}

            $projectStr = $projectStr.Trim()
            $labelStr = $labelStr.Trim()

            if($labelValue){
                if([string]::Compare($labelValue,$labelStr,$true) -eq 0){
                    $foundImports += $import
                    "Found import via label" | Write-Verbose
                    if($stopOnFirstResult){
                        return $import
                    }
                }
            }
            elseif($projectValue){
                if([string]::Compare($projectValue,$projectStr,$true) -eq 0){
                    $foundImports += $import
                    "Found import via project" | Write-Verbose
                    if($stopOnFirstResult){
                        return $import
                    }
                }
            }
        }
        
        return $foundImports
    }
}

<#
.SYNOPSIS
    Used to add an import to a project. The project that will be imported
    is passed in $importProject. You can also optionally add a label to 
    the import as well as a condition.

.OUTPUTS
    Microsoft.Build.Construction.ProjectRootElement. Returns the object
    passed in the $project parameter.

.EXAMPLE
    Get-MSBuildProject C:\temp\build.proj | 
        Add-Import -importProject 'c:\temp\import.targets' | 
        Save-MSBuildProject -filePath 'C:\temp\build.proj'

.EXAMPLE
    Get-MSBuildProject C:\temp\build.proj | 
        Add-Import -importProject 'c:\temp\import.targets'-importLabel 'Label' -importCondition ' ''$(VisualStudioVersion)''==''12.0'' ' | 
        Save-MSBuildProject -filePath 'C:\temp\build.proj'
#>
function Add-Import{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [Microsoft.Build.Construction.ProjectRootElement]
        $project,
        [Parameter(
            Position=2,
            Mandatory=$true)]
        $importProject,
        $importLabel,
        $importCondition
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $importToAdd = $project.AddImport($importProject)
        
        if($importLabel){
            $importToAdd.Label = $importLabel
        }

        if($importCondition){
            $importToAdd.Condition = $importCondition
        }
        
        return $project
    }
}

<#
.SYNOPSIS
    This can be used to remove an import from the given MSBuild file. All of the matching
    imports will be removed from the project. If there are multiple imports with the
    same label/project value that matches what is provided they will all be removed.

.OUTPUTS
    Microsoft.Build.Construction.ProjectRootElement. Returns the object
    passed in the $project parameter.
#>
function Remove-Import{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [Microsoft.Build.Construction.ProjectRootElement]
        $project,
        $labelValue,
        $projectValue
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $importsToRemove = (Find-Import -project $project -labelValue $labelValue -projectValue $projectValue)
        foreach($importToRemove in $importsToRemove){
            'Removing import [Project=[{0}],Label=[{1}],Condition=[{2}]] from project [{3}]' -f `
                $importToRemove.Project, $importToRemove.Label, $importToRemove.Condition, $project.Location | Write-Verbose

            $importToRemove.Parent.RemoveChild($importToRemove) | Out-Null
        }

        return $project
    }
}

<#
.SYNOPSIS
    Can be used to find imports in an MSBuild file. You can find by looking for the 
    Import by either the Label value or the value for Project. This is determined 
    by the parameters passed in. If both labelValue an projectValue are passed 
    in then labelValue will take precedence.

.EXAMPLE
    Find-PropertyGroup -project (Get-MSBuildProject 'C:\temp\msbuild\proj1.proj') -labelValue MyPropGroup

.EXAMPLE
    $projFilePath = 'C:\temp\msbuild\proj1.proj'
    $proj = (Get-MSBuildProject $projFilePath)
    $pgs = Find-PropertyGroup -project $proj -labelValue MyPropGroup

.EXAMPLE
    Get-MSBuildProject C:\temp\msbuild\proj1.proj | Find-PropertyGroup -labelValue MyPropGroup

.EXAMPLE
    @('C:\temp\msbuild\proj1.proj';'C:\temp\msbuild\proj2.proj') | Find-PropertyGroup -labelValue MyPropGroup
#>
function Find-PropertyGroup{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $project,

        [Parameter(
            Position=2,
            Mandatory=$true)]
        $labelValue,
        [switch]
        $stopOnFirstResult
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        "Looking for a PropertyGroup. Label=[{0}]" -f $labelValue | Write-Verbose

        # $project can either be a ProjectRootElement object or a string
        [Microsoft.Build.Construction.ProjectRootElement]$realProject = $null
        if($project -is [Microsoft.Build.Construction.ProjectRootElement]){
            $realProject = $project
        }
        else{
            $realProject = (Get-MSBuildProject -projectFile ([string]$project))
        }

        $foundPgs = @()
        foreach($pg in $realProject.PropertyGroups){
            [string]$pgLabelStr = if($pg.Label){$pg.Label}else{''}
            $pgLabelStr = $pgLabelStr.Trim()

            if([string]::Compare($labelValue,$pgLabelStr,$true) -eq 0){
                $foundPgs += $pg
                'Found property group for label [{0}]' -f $labelValue | Write-Verbose
                if($stopOnFirstResult){
                    return $pg
                }
            }            
        }
        
        return $foundPgs
    }
}

<#
.SYNOPSIS
    Will remove PropertyGroup elements based on the Label attribute. If there is more than one
    matching property group than all the matching values will be removed.

.OUTPUTS
    Microsoft.Build.Construction.ProjectRootElement. Returns the object
    passed in the $project parameter.

.EXAMPLE
    Get-MSBuildProject 'C:\temp\msbuild\new\new.proj' | Remove-PropertyGroup -labelValue MyPropGroup | Save-MSBuildProject -filePath 'C:\temp\msbuild\new\new.proj'
#>
function Remove-PropertyGroup{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $project,

        [Parameter(
            Position=2,
            Mandatory=$true)]
        $labelValue
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $pgsToRemove = (Find-PropertyGroup -project $project -labelValue $labelValue)
        foreach($pg in $pgsToRemove){
            'Removing PropertyGroup with label [{0}]' -f $labelValue | Write-Verbose
            $pg.Parent.RemoveChild($pg)
        }
        return $project
    }
}

<#
.SYNOPSIS
    This will create a new PropertyGroup element in the given project. Optionally you can
    specify a label and condition for the element being created.

.OUTPUTS
    Microsoft.Build.Construction.ProjectRootElement. Returns the object
    passed in the $project parameter.

.EXAMPLE
    Get-MSBuildProject 'C:\temp\msbuild\new\new.proj' | Remove-PropertyGroup -labelValue MyPropGroup | Save-MSBuildProject -filePath 'C:\temp\msbuild\new\new.proj'
#>
function Add-PropertyGroup{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [Microsoft.Build.Construction.ProjectRootElement]
        $project,
        
        [Parameter(
            Position=2)]
        $label,

        [Parameter(
            Position=3)]
        $condition
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $pgToAdd = $project.AddPropertyGroup();

        if($label){
            $pgToAdd.Label = $label
        }

        if($condition){
            $pgToAdd.Condition = $condition
        }
        
        return $project
    }
}

<#
.SYNOPSIS
    Will return $true/$false indicating if there exists at least on PropertyGroup
    with the provided Label.

.OUTPUTS
    [bool]

.EXAMPLE
    Get-MSBuildProject 'C:\temp\msbuild\new\new.proj' | Test-PropertyGroup -label Label1
#>
function Test-PropertyGroup{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $project,

        [Parameter(
            Position=2,
            Mandatory=$true)]
        $label
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $foundPg = (Find-PropertyGroup -project $project -label $label)

        $wasFound = $false
        if(-not $foundPg){
            $wasFound = $false
        }
        else{
            $wasFound = $true
        }

        return $wasFound
    }
}

<#
.SYNOPSIS
    Can be used to look for a property within a given container (typically either a Project or PropertyGroup)
    by either Name or Label. If both are provided the function will just search using Name.

.EXAMPLE
    Get-MSBuildProject 'C:\temp\msbuild\new\new.proj' | Find-Property -label Label1

.EXAMPLE
    Get-MSBuildProject 'C:\temp\msbuild\new\new.proj' | Find-PropertyGroup -labelValue first | Find-Property -label Label1
#>
function Find-Property{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]            
        $propertyContainer,

        $name,
        $label,
        [switch]
        $stopOnFirstResult
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        if(!($name) -and !($label)){
            'Both name and label parameters are empty. Not searching for property' | Write-Warning
            return
        }

        $foundProperties = @()
        foreach($prop in $propertyContainer.Properties){
            [string]$propName = $prop.Name
            [string]$propLabel = $prop.Label
            
            $propIsMatch = $false
            if($label){
                if([string]::Compare($propLabel,$label,$true) -eq 0){
                    $propIsMatch = $true                    
                }
            }
            elseif($name){
                if([string]::Compare($propName,$name,$true) -eq 0){
                    $propIsMatch = $true
                }
            }

            if($propIsMatch){
                'Found property with label [{0}]' -f $label | Write-Verbose
                $foundProperties += $prop
                if($stopOnFirstResult){
                    break
                }
            }
        }

        return $foundProperties
    }
}

<#
.SYNOPSIS
    Can be used to see if a given property exists. You can search by either Name or Label of the
    given property. The parameters will be passed to Find-Property and the rules for what is
    found or not is determined by that.

.OUTPUTS
    [bool]

.EXAMPLE
    You can search through the entire project by passing it in as the propertyContainer parameter
    
    Get-MSBuildProject 'C:\temp\msbuild\new\new.proj' | Test-Property -label Label1

.EXAMPLE
    You can search through a specific PropertyGroup element by passing it in as the propertyContainer parameter

    Get-MSBuildProject 'C:\temp\msbuild\new\new.proj' | Find-PropertyGroup -labelValue first | Test-Property -label Label1
#>
function Test-Property{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $propertyContainer,

        [Parameter(
            Position=2)]
        $name,

        [Parameter(
            Position=3)]
        $label
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $foundProp = (Find-Property -propertyContainer $propertyContainer -name $name -label $label -stopOnFirstResult)

        $wasFound = $false
        if(-not $foundProp){
            $wasFound = $false
        }
        else{
            $wasFound = $true
        }

        return $wasFound
    }
}

<#
.SYNOPSIS
    Can be used to remove a property. You can search for properties to be removed
    based on Name or Label. Find-Property will be used to locate the properties.
    The rules outlined there will apply here on items that will be removed.

.OUTPUTS
    Will return $propertyContainer

.EXAMPLE
    Get-MSBuildProject -projectFile 'C:\temp\msbuild\new\new.proj' | Remove-Property -Label label1 | Save-MSBuildProject -filePath $projFile

.EXAMPLE
    Get-MSBuildProject -projectFile 'C:\temp\msbuild\new\new.proj' | Remove-Property -name Configuration | Save-MSBuildProject -filePath $projFile

.EXAMPLE
    Get-MSBuildProject -projectFile 'C:\temp\msbuild\new\new.proj' | 
        Find-PropertyGroup -labelValue second | 
        Remove-Property -name Configuration |
        Get-MSBuildProject | 
        Save-MSBuildProject -filePath $projFile
#>
function Remove-Property{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]            
        $propertyContainer,

        $name,
        $label
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $propsToRemove = (Find-Property -propertyContainer $propertyContainer -name $name -label $label)
        foreach($prop in $propsToRemove){
            'Removing Property name=[{0}],Label=[{1}]' -f $name, $label | Write-Verbose
            $prop.Parent.RemoveChild($prop)
        }

        return $propertyContainer
    }
}

<#
.SYNOPSIS
    This will add a property to the given project.
.OUTPUTS

.EXAMPLE
    Get-MSBuildProject 'C:\temp\msbuild\new\new.proj' | Add-Property -name Configuration -value Debug | Get-MSBuildProject | Save-MSBuildProject -filePath 'C:\temp\msbuild\new\new.proj'

.EXAMPLE
    Add-Property -propertyContainer (Get-MSBuildProject 'C:\temp\msbuild\new\new.proj') -name Configuration -value Debug | Get-MSBuildProject | Save-MSBuildProject -filePath 'C:\temp\msbuild\new\new.proj'

.EXAMPLE
    Add-Property -propertyContainer (Get-MSBuildProject 'C:\temp\msbuild\new\new.proj') `
         -name Configuration -value Debug -label Custom -condition' ''$(VSV)''==''12.0'' ' | 
    Get-MSBuildProject | 
    Save-MSBuildProject -filePath 'C:\temp\msbuild\new\new.proj'
#>
function Add-Property{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            Mandatory=$true,
            ValueFromPipeline=$true)]
        $propertyContainer,
        
        [Parameter(
            Position=2,
            Mandatory=$true)]
        $name,

        [Parameter(
            Position=3)]
        $value,

        [Parameter(
            Position=4)]
        $label,

        [Parameter(
            Position=5)]
        $condition
    )
    begin{
        Add-Type -AssemblyName Microsoft.Build
    }
    process{
        $propToAdd = $propertyContainer.AddProperty($name,$value)

        if($label){
            $propToAdd.Label = $label
        }

        if($condition){
            $propToAdd.Condition = $condition
        }
        
        return $propToAdd
    }
}

#####################################################################
# "Internal" functions
#####################################################################

function PSBuild-ConverToDictionary{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            Position=0,
            ValueFromPipeline=$true)]
        [hashtable]
        $valueToConvert
    )
    process{
        $valueToReturn = New-Object 'system.collections.generic.dictionary[[string],[string]]'

        if($valueToConvert){
            $valueToConvert.Keys | ForEach-Object {
                $valueToReturn.Add($_, ($valueToConvert[$_]))
            }
        }

        return $valueToReturn
    }
}

$script:envVarToRestore = @{}
function PSBuildSet-TempVar{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            Position=0,
            ValueFromPipeline=$true)]
        [hashtable]
        $envVars
    )
    begin{
        $script:envVarToRestore = @{}
    }
    process{
        foreach($key in $envVars.Keys){
            $oldValue = [environment]::GetEnvironmentVariable("$key",$script:envVarTarget)
            $newValue = ($envVars[$key])
            $script:envVarToRestore[$key]=($oldValue)
            
            'Setting temp env var [{0}={1}]`tPrevious value:[{2}]' -f $key, $newValue, $oldValue | Write-Verbose
            [environment]::SetEnvironmentVariable("$key", $newValue,$script:envVarTarget)
        }
    }
}

function PSBuildReset-TempEnvVars{
    [cmdletbinding()]
    param()
    process{
        foreach($key in $script:envVarToRestore.Keys){
            $previousValue = ($script:envVarToRestore[$key])

            [environment]::SetEnvironmentVariable("$key",$previousValue,$script:envVarTarget)
        }
    }
}

$script:BuildTextToMask = [array]@()
$global:FilterStringSettings = New-Object PSObject -Property @{
    DefaultMask = '********'
    GlobalReplacements = [array]@()
    # WriteFunctionsToCreate = 'Out-Default','Write-Output','Write-Host','Write-Debug','Write-Error','Write-Warning','Write-Verbose','Out-Host','Out-String'
}
<#
.SYNOPSIS
Given a string ($message) and strings to remove ($textToRemove) this will mask the given text from
$textToRemove in $message and return the result.

.PARAMETER message
    The message to filter.

.PARAMETER textToRemove
    This is an array of strings that will be masked (i.e. hidden) from the PowerShell output.
    You can use this for connection strings or passwords, etc. so that
    they are not displayed in the PowerShell console. You can also set global values using
    the $global:FilterStringSettings.GlobalReplacements array which will apply to every build.
    You can also control which PowerShell cmdlets are overridden with
    $global:FilterStringSettings.WriteFunctionsToCreate. The default list is:
    'Out-Default','Write-Output','Write-Host','Write-Debug','Write-Error','Write-Warning','Write-Verbose','Out-Host','Out-String'

.PARAMETER mask
    The string that will be used in place of secrets. If no value is specifed then the value from $global:FilterStringSettings.DefaultMask
    will be used, which is set to '********' by default.
#>
function Get-FilteredString{
[cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$message,
        [string[]]$textToRemove,
        [string]$mask = ($global:FilterStringSettings.DefaultMask)
    )
    process{
        if($message -ne $null){
            $replacements = New-Object System.Collections.Generic.List[System.String]

            foreach($tr in $textToRemove){
                if(-not ($replacements.Contains($tr))){
                    $replacements.Add($tr)
                }
            }

            foreach($gtr in $global:FilterStringSettings.GlobalReplacements){
                if(-not ($replacements.Contains($gtr))){
                    $replacements.Add($gtr)
                }
            }

            if($script:BuildTextToMask){
                foreach($btr in $script:BuildTextToMask){
                    if(-not ($replacements.Contains($btr))){
                        $replacements.Add($btr)
                    }
                }
            }

            foreach($msg in $message){
                foreach($repl in $replacements){
                    $msg = $msg.Replace($repl,$mask)
                }

                $msg
            }
        }
        else{
            # required so that empty lines are output to the console
            $message
        }
    }
}

<#
.SYNOPSIS
    Function that can be called to write a build message.
    This is just a wrapper to Write-Host so that if we chose to replace that with something else
    it will be easy later.    
#>
function Write-BuildMessage{
    [cmdletbinding()]
    param(
        [Parameter(
            Position=1,
            ValueFromPipeline=$true)]
        $message,

        [switch]
        $strong
    )
    process{

        if($global:PSBuildSettings.BuildMessageEnabled -and $message){
            $fgColor = $global:PSBuildSettings.BuildMessageForegroundColor
            $bColor = $global:PSBuildSettings.BuildMessageBackgroundColor
            if($strong){
                $fgColor = $global:PSBuildSettings.BuildMessageStrongForegroundColor
                $bColor = $global:PSBuildSettings.BuildMessageStrongBackgroundColor
            }

            if($Host -and ($Host.Name -eq 'ConsoleHost')){
                $message | Write-Host
            }
            else{
                $message | Write-Output
            }
        }
    }
}

<#
.SYNOPSIS
    This will download and import the given version of pester https://github.com/pester/Pester, which is a
    PowerShell testing framework.

.PARAMETER pesterVersion
    The version to import.
#>
function Import-Pester{
    [cmdletbinding()]
    param(
        $pesterVersion = '3.3.14'
    )
    process{
        Import-NuGetPowershell

        Remove-Module pester -ErrorAction SilentlyContinue

        [System.IO.DirectoryInfo]$pesterDir = (Get-NuGetPackage -name 'pester' -version $pesterVersion -binpath)
        [System.IO.FileInfo]$pesterModPath = (Join-Path $pesterDir.FullName 'pester.psd1')
        if(-not (Test-Path $pesterModPath.FullName)){
            throw ('Pester not found at [{0}]' -f $pesterModPath.FullName)
        }

        Import-Module $pesterModPath.FullName -Global
    }
}

<#
.SYNOPSIS
    This will download and import nuget-powershell (https://github.com/ligershark/nuget-powershell),
    which is a PowerShell utility that can be used to easily download nuget packages.

    If nuget-powershell is already loaded then the download/import will be skipped.

.PARAMETER nugetPsMinModVersion
    The minimum version to import
#>
function Import-NuGetPowershell{
    [cmdletbinding()]
    param(
        $nugetPsMinModVersion = $nugetPsMinModuleVersion
    )
    process{
        # see if nuget-powershell is available and load if not
        $nugetpsloaded = $false
        if((get-command Get-NuGetPackage -ErrorAction SilentlyContinue)){
            # check the module to ensure we have the correct version
            <#
            $currentversion = (Get-Module -Name nuget-powershell).Version
            if( ($currentversion -ne $null) -and ($currentversion.CompareTo([version]::Parse($nugetPsMinModVersion)) -ge 0 )){
                $nugetpsloaded = $true
            }
            #>
        }

        if(!$nugetpsloaded){
            #(new-object Net.WebClient).DownloadString("https://raw.githubusercontent.com/ligershark/nuget-powershell/master/get-nugetps.ps1") | iex
            'Looking for nuget-powershell' | Write-Verbose
            foreach($path in $global:PSBuildSettings.ContribDirs){
                $modpath = (Join-Path $path 'nuget-powershell.psd1')
                if(Test-Path $modpath){
                    Import-Module $modpath -DisableNameChecking -Global | Write-Verbose
                }
            }
        }

        # check to see that it was loaded
        if((get-command Get-NuGetPackage -ErrorAction SilentlyContinue)){
            $nugetpsloaded = $true
        }

        if(-not $nugetpsloaded){
            throw ('Unable to load nuget-powershell, unknown error')
        }
    }
}

<#
.SYNOPSIS
    This will download and import the given version of file-replacer (https://github.com/ligershark/template-builder/blob/master/file-replacer.psm1),
    which can be used to replace text in files under a given folder.

    If file-replacer is already loaded then the download/import will be skipped.

.PARAMETER fileReplacerVersion
    The version to import.
#>
function Import-FileReplacer{
    [cmdletbinding()]
    param(
        [string]$fileReplacerVersion = '0.4.0-beta'
    )
    process{
        $fileReplacerLoaded = $false
        # Replace-TextInFolder
        if(get-command Replace-TextInFolder -ErrorAction SilentlyContinue){
            $fileReplacerLoaded = $true
        }

        # download/import file-replacer
        if(-not $fileReplacerLoaded){
            'Loading file-replacer' | Write-Verbose
            foreach($path in $global:PSBuildSettings.ContribDirs){
                $modpath = (Join-Path $path 'file-replacer.psm1')
                if(Test-Path $modpath){
                    Import-Module $modpath -DisableNameChecking -Global | Write-Verbose
                }
            }
        }
    }
}

if( ($env:IsDeveloperMachine -eq $true) ){
    # you can set the env var to expose all functions to importer. easy for development.
    # this is required for pester testing
    Export-ModuleMember -function * -Alias *
}
else{
    Export-ModuleMember -function Get-*,Set-*,Invoke-*,Save-*,Test-*,Find-*,Add-*,Remove-*,Test-*,Open-*,New-*,Import-* -Alias psbuild
}


#################################################################
# begin script portions
#################################################################

Add-Type -AssemblyName Microsoft.Build

[string]$script:defaultMSBuildPath = $null
[string]$script:VisualStudioVersion = $null
# call this once to ensure the alias is set
Get-MSBuild | Set-MSBuild -persist $false
