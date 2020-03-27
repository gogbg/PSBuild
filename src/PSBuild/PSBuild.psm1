#region functions

function Invoke-PSBuildTask
{
    [CmdletBinding()]
    [OutputType([PSBuildContext])]
    param
    (
        [Parameter(Mandatory)]
        [PSBuildContext]$BuildContext,

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
        $moduleContexts = [System.Collections.Generic.List[PSBuildContext]]::new()
        foreach ($dm in $script:discoveredModules)
        {
            $moduleBuildFactory = [PSBuildFactory]::New()
            $moduleContexts.Add($moduleBuildFactory.NewBuildContext($dm.Name, $dm.FolderPath, $script:defaultModuleBuildTasks))
        }

        foreach ($mc in $moduleContexts)
        {
            #Execute OnBegin
            $mc.TaskRunner.RunTasks($mc,[PSBuildTaskMethod]::OnBegin)
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
            $_.TaskRunner.RunTasks($_,[PSBuildTaskMethod]::OnProcess)
            #$_ = Invoke-PSBuildTask -BuildContext $_ -Method OnProcess
        }
    }
    end
    {
        foreach ($mc in $moduleContexts)
        {
            #Execute OnEnd
            $mc.TaskRunner.RunTasks($mc,[PSBuildTaskMethod]::OnEnd)
            #$mc = Invoke-PSBuildTask -BuildContext $mc -Method OnEnd
        }

        #return result
        if ($PassThru.IsPresent)
        {
            $moduleContexts.ModuleInfo
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
class PSBuildContext
{
    [System.Collections.Generic.List[PSBuildTask]]$Tasks = ([System.Collections.Generic.List[PSBuildTask]]::new())
    [PSBuildTaskRunnerBase]$TaskRunner
}

class PSBuildTask
{
    [string]$Name
    [PSBuildTaskState]$State = [PSBuildTaskState]::Initialized
    [type]$Type
}

class PSBuildInfoBase
{

}

class PSBuildTaskBase
{
    [PSBuildInfoBase]OnBegin([PSBuildInfoBase]$buildInfo)
    {
        throw 'Not implemented'
    }

    [PSBuildInfoBase]OnProcess([PSBuildInfoBase]$buildInfo)
    {
        throw 'Not implemented'
    }

    [PSBuildInfoBase]OnEnd([PSBuildInfoBase]$buildInfo)
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
    static [void]RunTasks([PSBuildContext]$buildContext,[PSBuildTaskMethod]$method) {
        throw "Not implemented"
    }
}

class PSBuildFactory
{
    static [type]$DefaultTaskRunner = [PSBuildDefaultTaskRunner]

    [PSBuildContext]NewBuildContext([string]$name, [string]$folderPath, [System.Collections.Generic.List[string]]$tasks)
    {
        #Initialize taskRunner
        $taskRunner = $this::DefaultTaskRunner::new()

        return $this.NewBuildContext($name,$folderPath,$tasks,$taskRunner)
    }

    [PSBuildContext]NewBuildContext([string]$name, [string]$folderPath, [System.Collections.Generic.List[string]]$tasks, [PSBuildTaskRunnerBase]$taskRunner)
    {
        $result = [PSBuildContext]::new()
        $result.TaskRunner = $taskRunner
        $result.ModuleInfo = [PSBuildInfoBase]::new()
        $result.ModuleInfo.Name = $name
        $result.ModuleInfo.FolderPath = $folderPath
        foreach ($t in $tasks)
        {
            $result.Tasks.Add($this.NewBuildTask($t))
        }

        $result.TaskRunner.BuildContext = $result
        return $result
    }

    [PSBuildTask]NewBuildTask([string]$name)
    {
        $result = [PSBuildTask]::New()
        $result.Name = $name
        $type = $name -as [type]
        if (-not $type)
        {
            throw "task: $name not found"
        }

        $result.Type = $type
        return $result
    }
}
#endregion

#region module classes
class PSModuleBuildInfo : PSBuildInfoBase
{
    [string]$FolderPath
    [string]$Name
    [string]$Version
    [string]$Functions
}

class PSModuleBuildContext : PSBuildContext
{
    [PSModuleBuildInfo]$ModuleInfo = [PSModuleBuildInfo]::new()
}
#endregion

#region buildTaskRunners
class PSBuildDefaultTaskRunner : PSBuildTaskRunnerBase
{
    static [void]RunTasks([PSBuildContext]$buildContext,[PSBuildTaskMethod]$method) {
        foreach ($task in $buildContext.Tasks)
        {
            $taskMethod = $task.Type.GetMethod($method)
            if ($taskMethod)
            {
                $taskInstance = $task.Type::new()
                $buildContext.ModuleInfo = $taskInstance."$method"($buildContext.ModuleInfo)
            }
        }
    }
}
#endregion

#region buildTasks
class PSModuleBuildTaskGetVersion : PSBuildTaskBase
{
    [PSModuleBuildInfo]OnBegin([PSModuleBuildInfo]$buildInfo)
    {
        $this.WriteWarning('Info from OnBegin')
        return $buildInfo
    }

    [PSModuleBuildInfo]OnProcess([PSModuleBuildInfo]$buildInfo)
    {
        $manifestPath = Join-Path -Path $buildInfo.FolderPath -ChildPath "$($buildInfo.Name).psbuild.psd1"
        $manifest = Test-ModuleManifest -Path $manifestPath
        $buildInfo.Version = $manifest.Version
        $this.WriteWarning('Info from OnProcess')
        return $buildInfo
    }

    [PSModuleBuildInfo]OnEnd([PSModuleBuildInfo]$buildInfo)
    {
        $this.WriteWarning('Info from OnEnd')
        return $buildInfo
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