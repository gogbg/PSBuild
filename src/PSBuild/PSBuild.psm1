#region functions

function Build-PSModule
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory)]
        [ArgumentCompleter(
            {
                param(
                    [Parameter()]
                    $CommandName,
        
                    [Parameter()]
                    $ParameterName,
        
                    [Parameter()]
                    $WordToComplete,

                    [Parameter()]
                    $commandAst
                )

                (Find-PSModuleDefinition -Name $WordToComplete).Name
            }
        )]
        [ValidateScript(
            {
                $script:discoveredModules = Find-PSModuleDefinition -Name $WordToComplete
                $_ -in $script:discoveredModules.Name
            },
            ErrorMessage = { throw "Module: $_ not found" }
        )]
        [string[]]$Name
    )
    
    begin
    {
        #Initialize module context
        $moduleContexts = [System.Collections.Generic.List[PSModuleBuildContext]]::new()
        foreach ($dm in $script:discoveredModules)
        {
            $moduleBuildFactory = [PSModuleBuildFactory]::New()
            $moduleContexts.Add($moduleBuildFactory.NewPSModuleBuildInfo($dm.Name, $dm.FolderPath, $script:defaultModuleBuildTasks))
        }

        #Execute OnBegin
        foreach ($mc in $moduleContexts)
        {
            foreach ($task in $mc.Tasks)
            {
                if ($task.GetMember('OnBegin'))
                {
                    Write-Information "Building module: '$($mc.ModuleInfo.Name)'.Task: 'OnBegin/$($task.Name)' started"
                    $mc.ModuleInfo = $task::OnBegin($mc.ModuleInfo)
                    Write-Information "Building module: '$($mc.ModuleInfo.Name)'.Task: 'OnBegin/$($task.Name)' completed"
                }
            }
        }
    }

    process
    {
        $moduleContexts | ForEach-Object -Parallel {
            Write-Information "Building module: '$($_.ModuleInfo.Name)' started"
            foreach ($task in $_.Tasks)
            {
                try
                {
                    #Execute OnProcess
                    if ($task.GetMember('OnProcess'))
                    {
                        Write-Information "Building module: '$($_.ModuleInfo.Name)'.Task: 'OnProcess/$($task.Name)' started"
                        $_.ModuleInfo = $task::OnProcess($_.ModuleInfo)
                        Write-Information "Building module: '$($_.ModuleInfo.Name)'.Task: 'OnProcess/$($task.Name)' completed"
                    }
                }
                catch
                {
                    Write-Error "Building module: '$($_.ModuleInfo.Name)' in progress. Executing task: '$($task.Name)' failed. Details: $_"
                }
            }
        }
    }

    end
    {
        #Execute OnEnd
        foreach ($mc in $moduleContexts)
        {
            foreach ($task in $mc.Tasks)
            {
                if ($task.GetMember('OnEnd'))
                {
                    Write-Information "Building module: '$($_.ModuleInfo.Name)'.Task: 'OnEnd/$($task.Name)' started"
                    $mc.ModuleInfo = $task::OnEnd($mc.ModuleInfo)
                    Write-Information "Building module: '$($_.ModuleInfo.Name)'.Task: 'OnEnd/$($task.Name)' started"
                }
            }
        }
    }
}

function Find-PSModuleDefinition
{
    [cmdletbinding()]
    param
    (
        [Parameter()]
        [string]$Name
    )

    process
    {
        Get-ChildItem -Filter "*${Name}.psbuild.psd1" -Recurse | ForEach-Object -Process {
            [pscustomobject]@{
                Name       = $_.BaseName -replace '.psbuild$'
                FolderPath = $_.Directory
            }
        }
    }
}

#endregion

#region variables

$defaultModuleBuildTasks = @(
    'PSModuleBuildTask_GetFolder'
)

#endregion

#region classes

class PSModuleBuildFactory
{
    [PSModuleBuildContext]NewPSModuleBuildInfo([string]$name, [string]$folderPath, [System.Collections.Generic.List[string]]$tasks)
    {
        $result = [PSModuleBuildContext]::new()
        $result.ModuleInfo = [PSModuleBuildInfo]::new()
        $result.ModuleInfo.Name = $name
        $result.ModuleInfo.FolderPath = $folderPath
        foreach ($t in $tasks)
        {
            $tType = $t -as [type]
            if ($tType)
            {
                $result.Tasks.Add($tType)
            }
            else
            {
                Write-Warning "Task: '$t' not found"
            }
        }
        return $result
    }
}

class PSModuleBuildInfo
{
    [string]$FolderPath
    [string]$Name
    [string]$Version
    [string]$Functions
}

class PSModuleBuildContext
{
    [PSModuleBuildInfo]$ModuleInfo = ([PSModuleBuildInfo]::new())
    [System.Collections.Generic.List[type]]$Tasks = ([System.Collections.Generic.List[type]]::new())
}

class PSModuleBuildTaskBase
{
    static [PSModuleBuildInfo]OnBegin([PSModuleBuildInfo]$moduleBuildInfo)
    {
        throw 'Not implemented'
    }

    static [PSModuleBuildInfo]OnProcess([PSModuleBuildInfo]$moduleBuildInfo)
    {
        throw 'Not implemented'
    }

    static [PSModuleBuildInfo]OnEnd([PSModuleBuildInfo]$moduleBuildInfo)
    {
        throw 'Not implemented'
    }
    
    static [void]WriteInformation([string]$message)
    {
        Write-Information -MessageData $message
    }

    static [void]WriteWarning([string]$message)
    {
        Write-Warning -Message $message
    }
}

class PSModuleBuildTask_GetFolder : PSModuleBuildTaskBase
{
    static [PSModuleBuildInfo]OnBegin([PSModuleBuildInfo]$moduleBuildInfo)
    {
        [PSModuleBuildTask_GetFolder]::WriteInformation('Info from OnBegin')
        return $moduleBuildInfo
    }

    static [PSModuleBuildInfo]OnProcess([PSModuleBuildInfo]$moduleBuildInfo)
    {
        [PSModuleBuildTask_GetFolder]::WriteInformation('Info from OnProcess')
        return $moduleBuildInfo
    }

    static [PSModuleBuildInfo]OnEnd([PSModuleBuildInfo]$moduleBuildInfo)
    {
        [PSModuleBuildTask_GetFolder]::WriteInformation('Info from OnEnd')
        return $moduleBuildInfo
    }
}

#endregion