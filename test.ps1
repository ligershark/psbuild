
'executing test.ps1' | Write-Output

function Out-Default{
    [cmdletbinding(ConfirmImpact='Medium')]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [System.Management.Automation.PSObject]$InputObject
    )
    begin{
        $wrappedObject = $ExecutionContext.InvokeCommand.GetCmdlet('Out-Default')
        $sb = { & $wrappedObject @PSBoundParameters }
        $__sp = $sb.GetSteppablePipeline()
        $__sp.Begin($pscmdlet)
    }
    process{
        $__sp.Process('***' + $_)
    }
    end{
        $__sp.End()
    }
}

function Write-Host{
    [cmdletbinding(ConfirmImpact='Medium')]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [System.Management.Automation.PSObject]$InputObject
    )
    begin{
        $wrappedObject = $ExecutionContext.InvokeCommand.GetCmdlet('Write-Host')
        $sb = { & $wrappedObject @PSBoundParameters }
        $__sp = $sb.GetSteppablePipeline()
        $__sp.Begin($pscmdlet)
    }
    process{
        $__sp.Process('***' + $_)
    }
    end{
        $__sp.End()
    }
}

function Write-Output{
    [cmdletbinding(ConfirmImpact='Medium')]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [System.Management.Automation.PSObject]$InputObject
    )
    begin{
        $wrappedObject = $ExecutionContext.InvokeCommand.GetCmdlet('Write-Host')
        $sb = { & $wrappedObject @PSBoundParameters }
        $__sp = $sb.GetSteppablePipeline()
        $__sp.Begin($pscmdlet)
    }
    process{
        $__sp.Process('***' + $_)
    }
    end{
        $__sp.End()
    }
}

'test' | out-default
'http://sedodream.com' | Out-Default
'foo'|Write-Output
'bar'|Write-Host