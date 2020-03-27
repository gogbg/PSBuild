#region functions

function Invoke-PSBuildTask
{
    [CmdletBinding()]
    [OutputType([PSBuildWorkspace])]
    param
    (
        [Parameter(Mandatory)]
        [PSBuildWorkspace]$BuildContext,

        [Parameter(Mandatory)]
        [ValidateSet('OnBegin','OnProcess','OnEnd')]
        [string]$Method
    )

    process
    {
        foreach ($task in $BuildContext.Tasks)
        {
            $taskMethod = $task.Type.GetMethod($Method)
            if ($taskMethod)
            {
                $taskInstance = $task.Type::new()
                $BuildContext.ModuleInfo = $taskInstance."$Method"($BuildContext.ModuleInfo)
            }
        }

        $BuildContext
    }
}

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
        #Get PSBuild module
        $psbuildModule = Get-Module -Name PSBuild
        $psbuildModulePath = $psbuildModule.Path
        #$psbuildModuleBase = $psbuildModule.ModuleBase

        #Initialize module context
        $moduleContexts = [System.Collections.Generic.List[PSBuildWorkspace]]::new()
        foreach ($dm in $script:discoveredModules)
        {
            $moduleContexts.Add([PSBuildFactory]::NewBuildWorkspace($dm.Name, $dm.FolderPath, $script:defaultModuleBuildTasks,[PSBuildDefaultTaskRunner],[PSBuildModuleContext]))
        }

        foreach ($mc in $moduleContexts)
        {
            #Execute OnBegin
            $mc.TaskRunner::RunTasks($mc,[PSBuildTaskMethod]::OnBegin)
            #$mc = Invoke-PSBuildTask -BuildContext $mc -Method OnBegin
        }
    }
    process
    {
        $moduleContexts | ForEach-Object -Parallel {
            #Load classes from psbuild module
            Invoke-Expression -command "using module $Using:psbuildModulePath"
            #Import-Module -Name $Using:psbuildModuleBase -Force

            #Execute OnProcess
            $_.TaskRunner::RunTasks($_,[PSBuildTaskMethod]::OnProcess)
            #$_ = Invoke-PSBuildTask -BuildContext $_ -Method OnProcess
        }
    }
    end
    {
        foreach ($mc in $moduleContexts)
        {
            #Execute OnEnd
            $mc.TaskRunner::RunTasks($mc,[PSBuildTaskMethod]::OnEnd)
            #$mc = Invoke-PSBuildTask -BuildContext $mc -Method OnEnd
        }

        #return result
        if ($PassThru.IsPresent)
        {
            $moduleContexts.Context
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
}

class PSBuildTask
{
    [string]$Name
    [PSBuildTaskState]$State = [PSBuildTaskState]::Initialized
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

    [PSBuildContextBase]OnBegin([PSBuildContextBase]$context)
    {
        throw 'Not implemented'
    }

    [PSBuildContextBase]OnProcess([PSBuildContextBase]$context)
    {
        throw 'Not implemented'
    }

    [PSBuildContextBase]OnEnd([PSBuildContextBase]$context)
    {
        throw 'Not implemented'
    }
    
    [void]WriteInformation([string]$message)
    {
        Write-Information -MessageData $message
    }

    [void]WriteWarning([string]$message)
    {
        Write-Warning -Message $message
    }
}

class PSBuildTaskRunnerBase
{
    static [void]RunTasks([PSBuildWorkspace]$buildContext,[PSBuildTaskMethod]$method) {
        throw "Not implemented"
    }
}

class PSBuildFactory
{
    static [PSBuildWorkspace]NewBuildWorkspace([string]$name, [string]$folderPath, [System.Collections.Generic.List[string]]$tasks, [type]$taskRunnerType, [type]$contextType)
    {
        $result = [PSBuildWorkspace]::new()
        $result.TaskRunner = $taskRunnerType::new()
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
    static [void]RunTasks([PSBuildWorkspace]$buildContext,[PSBuildTaskMethod]$method) {
        foreach ($task in $buildContext.Tasks)
        {
            $taskMethod = $task.Type.GetMethods() | Where-Object {$_.DeclaringType -eq $task.Type -and $_.Name -eq $method.ToString()}
            if ($taskMethod)
            {
                $taskInstance = $task.Type::new()
                $buildContext.Context = $taskInstance."$method"($buildContext.Context)
            }
        }
    }
}
#endregion

#region buildTasks
class PSModuleBuildTaskGetVersion : PSBuildTaskBase
{
    static [string]$Name = 'GetVersion'

    [PSBuildModuleContext]OnBegin([PSBuildModuleContext]$context)
    {
        $this.WriteWarning('Info from OnBegin')
        return $context
    }

    [PSBuildModuleContext]OnProcess([PSBuildModuleContext]$context)
    {
        $manifestPath = Join-Path -Path $context.FolderPath -ChildPath "$($context.Name).psbuild.psd1"
        $manifest = Test-ModuleManifest -Path $manifestPath
        $context.Version = $manifest.Version
        $this.WriteWarning('Info from OnProcess')
        return $context
    }

    [PSBuildModuleContext]OnEnd([PSBuildModuleContext]$context)
    {
        $this.WriteWarning('Info from OnEnd')
        return $context
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

enum PSBuildTaskState
{
    Initialized
    Started
    Completed
    Failed
}

#endregion