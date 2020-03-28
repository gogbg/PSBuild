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
        [string[]]$Name,

        [Parameter()]
        [switch]$PassThru
    )
    
    begin
    {
        $taskRunner = [PSBuildDefaultTaskRunner]

        #Get PSBuild module
        $psbuildModule = Get-Module -Name PSBuild
        $psbuildModulePath = $psbuildModule.Path
        #$psbuildModuleBase = $psbuildModule.ModuleBase
    }
    process
    {

        #Initialize module context
        $workspaces = [System.Collections.Generic.List[PSBuildWorkspace]]::new()
        foreach ($dm in $script:discoveredModules)
        {
            $workspaces.Add([PSBuildFactory]::NewBuildWorkspace($dm.Name, $dm.FolderPath, $script:defaultModuleBuildTasks,[PSBuildModuleContext]))
        }

        #Execute OnBegin
        $taskRunner::RunTasks($workspaces,[PSBuildTaskMethod]::OnBegin)

        $workspaces | ForEach-Object -Parallel {
            $taskRunner = $Using:taskRunner

            #Load classes from psbuild module
            Invoke-Expression -command "using module $Using:psbuildModulePath"

            #Execute OnProcess
            $taskRunner::RunTasks($_,[PSBuildTaskMethod]::OnProcess)
        }

        #Execute OnEnd
        $taskRunner::RunTasks($workspaces,[PSBuildTaskMethod]::OnEnd)
    }
    end
    {
        #return result
        if ($PassThru.IsPresent)
        {
            $workspaces.Context
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
    'PSModuleBuildTaskGetVersion'
)

#endregion

#region base classes
class PSBuildWorkspace
{
    [System.Collections.Generic.List[PSBuildTask]]$Tasks = ([System.Collections.Generic.List[PSBuildTask]]::new())
    [PSBuildTaskRunnerBase]$TaskRunner
    [PSBuildContextBase]$Context
    [PSBuildWorkspaceState]$State = [PSBuildWorkspaceState]::Available
    [System.Collections.Generic.List[PSBuildLogEntry]]$Logs = [System.Collections.Generic.List[PSBuildLogEntry]]::new()
}

class PSBuildLogEntry
{
    [datetime]$Timestamp
    [string]$Source
    [string]$Type
    [string]$Message
}

class PSBuildTask
{
    [string]$Name
    [type]$Type
}

class PSBuildContextBase
{
    [string]$Name
    [string]$FolderPath
}

class PSBuildTaskBase
{
    static [string]$Name
    [PSBuildContextBase]$Context

    [void]OnBegin()
    {
        throw 'Not implemented'
    }

    [void]OnProcess()
    {
        throw 'Not implemented'
    }

    [void]OnEnd()
    {
        throw 'Not implemented'
    }
    
    [void]WriteInformation([string]$message)
    {
        $This.Workspace.Logs.Add([PSBuildLogEntry]@{
            Timestamp=Get-Date
            Source=$this::Name
            Type='Information'
            Message=$message
        })
        Write-Information -MessageData $message
    }

    [void]WriteWarning([string]$message)
    {
        $This.Workspace.Logs.Add([PSBuildLogEntry]@{
            Timestamp=Get-Date
            Source=$this::Name
            Type='Warning'
            Message=$message
        })
        Write-Warning -Message $message
    }

    [void]WriteError([string]$message)
    {
        $This.Workspace.Logs.Add([PSBuildLogEntry]@{
            Timestamp=Get-Date
            Source=$this::Name
            Type='Error'
            Message=$message
        })
        Write-Error -Message $message
    }
}

class PSBuildTaskRunnerBase
{
    static [void]RunTasks([System.Collections.Generic.List[PSBuildWorkspace]]$workspaces,[PSBuildTaskMethod]$method) {
        throw "Not implemented"
    }
}

class PSBuildFactory
{
    static [PSBuildWorkspace]NewBuildWorkspace([string]$name, [string]$folderPath, [System.Collections.Generic.List[string]]$tasks, [type]$contextType)
    {
        $result = [PSBuildWorkspace]::new()
        foreach ($t in $tasks)
        {
            $result.Tasks.Add([PSBuildFactory]::NewBuildTask($t))
        }

        $result.Context = $contextType::new()
        $result.Context.Name = $name
        $result.Context.FolderPath = $folderPath

        return $result
    }

    static [PSBuildTask]NewBuildTask([string]$type)
    {
        $result = [PSBuildTask]::New()

        #check if build task type exist
        $typeExist = $type -as [type]
        if (-not $typeExist)
        {
            throw "task: $type not found"
        }

        $result.Name = $typeExist::Name
        $result.Type = $typeExist
        return $result
    }
}
#endregion

#region module classes
class PSBuildModuleContext : PSBuildContextBase
{
    [string]$Version
    [string]$Functions
}

#endregion

#region buildTaskRunners
class PSBuildDefaultTaskRunner : PSBuildTaskRunnerBase
{
    static [void]RunTasks([System.Collections.Generic.List[PSBuildWorkspace]]$workspaces,[PSBuildTaskMethod]$method) {
        foreach ($workspace in $workspaces)
        {
            if ($workspace.State -eq [PSBuildWorkspaceState]::Available)
            {
                foreach ($task in $workspace.Tasks)
                {
                    $taskMethod = $task.Type.GetMethods() | Where-Object {$_.DeclaringType -eq $task.Type -and $_.Name -eq $method.ToString()}
                    if ($taskMethod)
                    {
                        $taskInstance = $task.Type::new()
                        Add-Member -InputObject $taskInstance -MemberType NoteProperty -Name Workspace -TypeName PSBuildWorkspace -Value $workspace
                        $taskInstance.Context = $workspace.Context
                        try
                        {
                            $taskInstance.Workspace.State = [PSBuildWorkspaceState]::Busy
                            $taskInstance."$method"()
                            $taskInstance.Workspace.State = [PSBuildWorkspaceState]::Available
                        }
                        catch
                        {
                            $taskInstance.Workspace.State = [PSBuildWorkspaceState]::Failed
                        }
                    }
                }
            }
        }
    }
}
#endregion

#region buildTasks
class PSModuleBuildTaskGetVersion : PSBuildTaskBase
{
    static [string]$Name = 'GetVersion'

    [void]OnBegin()
    {
        $this.WriteWarning('Info from OnBegin')
    }

    [void]OnProcess()
    {
        $this.WriteWarning('Info from OnProcess')
        $manifestPath = Join-Path -Path $This.Context.FolderPath -ChildPath "$($This.Context.Name).psbuild.psd1"
        $manifest = Test-ModuleManifest -Path $manifestPath
        $This.Context.Version = $manifest.Version
    }

    [void]OnEnd()
    {
        $this.WriteWarning('Info from OnEnd')
    }
}
#endregion

#region enums

enum PSBuildTaskMethod
{
    OnBegin
    OnProcess
    OnEnd
}

enum PSBuildWorkspaceState
{
    Available
    Busy
    Completed
    Failed
}

#endregion