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
        [switch]$PassThru,

        [Parameter()]
        [PSBuildLogLevel]$LogLevel = 'Execution'
    )
    
    begin
    {
        $taskRunner = [PSBuildDefaultTaskRunner]
    }
    process
    {
        #Initialize module context
        $workspaces = [System.Collections.Generic.List[PSBuildWorkspace]]::new()
        foreach ($dm in $script:discoveredModules)
        {
            $workspaces.Add([PSBuildFactory]::NewBuildWorkspace($dm.Name, $dm.FolderPath, $script:defaultModuleBuildTasks, $script:LogHanlderClass, $LogLevel, [PSBuildModuleContext]))
        }

        #Execute OnBegin
        $taskRunner::RunTasks($workspaces, [PSBuildTaskMethod]::OnBegin)

        #Execute OnProcess
        $taskRunner::RunTasks($workspaces, [PSBuildTaskMethod]::OnProcess)

        #Execute OnEnd
        $taskRunner::RunTasks($workspaces, [PSBuildTaskMethod]::OnEnd)
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
    'PSModuleBuildTaskGetManifest'
    "PSModuleBuildTaskGetPrivateFunctions"
)

$LogHanlderClass = 'PSBuildLogCollection'

#endregion

#region base classes
class PSBuildWorkspace
{
    [System.Collections.Generic.List[PSBuildTask]]$Tasks = [System.Collections.Generic.List[PSBuildTask]]::new()
    [PSBuildContextBase]$Context
    [PSBuildWorkspaceState]$State = [PSBuildWorkspaceState]::Available
    [PSBuildLogCollectionBase]$Logs
}

class PSBuildLogEntry
{
    [datetime]$Timestamp
    [string]$Source
    [string]$Type
    [string]$Message
}

class PSBuildLogCollectionBase : System.Collections.Generic.List[object]
{
    [PSBuildLogLevel]$LogLevel
    [void] AddExecution([string]$message, [string]$source)
    {
        throw 'Not implemented'
    }
    [void] AddInformation([string]$message, [string]$source)
    {
        throw 'Not implemented'
    }
    [void] AddWarning([string]$message, [string]$source)
    {
        throw 'Not implemented'
    }
    [void] AddError([string]$message, [string]$source)
    {
        throw 'Not implemented'
    }
}

class PSBuildLogCollection : PSBuildLogCollectionBase
{
    [void] AddExecution([string]$message, [string]$source)
    {
        $this.Add([PSBuildLogEntry]@{
                Timestamp = Get-Date
                Source    = $source
                Type      = 'Execution'
                Message   = $message
            })
        if ($this.LogLevel.HasFlag([PSBuildLogLevel]::Execution))
        {
            Write-Information -MessageData "Execution: $source -> $message" -InformationAction Continue
        }
    }
    [void] AddExecutionError([string]$message, [string]$source)
    {
        $this.Add([PSBuildLogEntry]@{
                Timestamp = Get-Date
                Source    = $source
                Type      = 'Error'
                Message   = $message
            })
        throw [PSBuildExecutionException]::new("$source -> $message")
    }
    [void] AddInformation([string]$message, [string]$source)
    {
        $this.Add([PSBuildLogEntry]@{
                Timestamp = Get-Date
                Source    = $source
                Type      = 'Information'
                Message   = $message
            })
        if ($this.LogLevel.HasFlag([PSBuildLogLevel]::Information))
        {
            Write-Information -MessageData "Information: $source -> $message" -InformationAction Continue
        }
    }
    [void] AddWarning([string]$message, [string]$source)
    {
        $this.Add([PSBuildLogEntry]@{
                Timestamp = Get-Date
                Source    = $source
                Type      = 'Warning'
                Message   = $message
            })
        if ($this.LogLevel.HasFlag([PSBuildLogLevel]::Warning))
        {
            Write-Warning -Message "$source -> $message"
        }
    }
    [void] AddError([string]$message, [string]$source)
    {
        $this.Add([PSBuildLogEntry]@{
                Timestamp = Get-Date
                Source    = $source
                Type      = 'Error'
                Message   = $message
            })
        throw [PSBuildTaskException]::new("$source -> $message")
    }
}

class PSBuildTask
{
    [string]$Name
    [string]$Type
    [System.Collections.Generic.HashSet[string]]$ImplementedMethods = [System.Collections.Generic.HashSet[string]]::new()
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
        $This.Logs.AddInformation($message, $this::Name)
    }

    [void]WriteWarning([string]$message)
    {
        $This.Logs.AddWarning($message, $this::Name)
    }

    [void]WriteError([string]$message)
    {
        $This.Logs.AddError($message, $this::Name)
    }
}

class PSBuildTaskRunnerBase
{
    static [void]RunTasks([System.Collections.Generic.List[PSBuildWorkspace]]$workspaces, [PSBuildTaskMethod]$method)
    {
        throw "Not implemented"
    }
}

class PSBuildFactory
{
    static [PSBuildWorkspace]NewBuildWorkspace([string]$name, [string]$folderPath, [System.Collections.Generic.List[string]]$tasks, [string]$logHanlderType, [PSBuildLogLevel]$logLevel, [type]$contextType)
    {
        $result = [PSBuildWorkspace]::new()
        foreach ($t in $tasks)
        {
            $result.Tasks.Add([PSBuildFactory]::NewBuildTask($t))
        }

        $result.Logs = New-Object -TypeName $logHanlderType -ErrorAction Stop
        $result.Logs.LogLevel = $logLevel
        $result.Context = $contextType::new()
        $result.Context.Name = $name
        $result.Context.FolderPath = $folderPath

        return $result
    }

    static [PSBuildTask]NewBuildTask([string]$type)
    {
        $result = [PSBuildTask]::New()

        #check if build task type exist
        $taskType = $type -as [type]
        if (-not $taskType)
        {
            throw "task: $type not found"
        }

        $result.Name = $taskType::Name
        $result.Type = $type
        $taskType.GetMethods() | ForEach-Object -Process {
            if ($_.DeclaringType -eq $taskType -and $_.Name -in [PSBuildTaskMethod].GetEnumValues())
            {
                $result.ImplementedMethods.Add($_.Name)
            }
        }

        return $result
    }
}

class PSBuildTaskException : System.Exception
{
    PSBuildTaskException([string]$message): base($message)
    {

    }
}

class PSBuildExecutionException : System.Exception
{
    PSBuildExecutionException([string]$message): base($message)
    {

    }
}
#endregion

#region module classes
class PSBuildModuleContext : PSBuildContextBase
{
    [hashtable]$Manifest
    [System.Collections.Generic.Dictionary[string, PSBuildModuleFunction]]$PrivateFunctions = [System.Collections.Generic.Dictionary[string, PSBuildModuleFunction]]::new()
    [System.Collections.Generic.Dictionary[string, PSBuildModuleFunction]]$PublicFUnctions = [System.Collections.Generic.Dictionary[string, PSBuildModuleFunction]]::new()
}

class PSBuildModuleFunction
{
    [string]$Name
    [string]$Source
    [System.Management.Automation.Language.Ast]$Ast
    [string]$RelativeSource
}

#endregion

#region buildTaskRunners
class PSBuildDefaultTaskRunner : PSBuildTaskRunnerBase
{
    static [void]RunTasks([System.Collections.Generic.List[PSBuildWorkspace]]$workspaces, [PSBuildTaskMethod]$method) 
    {
        foreach ($workspace in $workspaces)
        {
            foreach ($task in $workspace.Tasks)
            {
                if ($workspace.State -eq [PSBuildWorkspaceState]::Available)
                {
                    try
                    {
                        $workspace.State = [PSBuildWorkspaceState]::Busy
                        [PSBuildDefaultTaskRunner]::RunTask($task, $method, $workspace.Context, $workspace.Logs)
                        $workspace.State = [PSBuildWorkspaceState]::Available
                    }
                    catch
                    {
                        $workspace.State = [PSBuildWorkspaceState]::Failed
                        throw $_
                    }
                }
            }
        }
    }

    static [void]RunTask([PSBuildTask]$task, [PSBuildTaskMethod]$method, [PSBuildContextBase]$context, [PSBuildLogCollectionBase]$Logs)
    {
        if ($task.ImplementedMethods.Contains($method.ToString()))
        {
            $taskInstance = New-Object -TypeName $task.Type -ErrorAction Stop
            Add-Member -InputObject $taskInstance -MemberType NoteProperty -Name Logs -Value $Logs
            $taskInstance.Context = $context
            try
            {
                $taskInstance.Logs.AddExecution('Starting', "$($taskInstance::Name)[$method]")
                $taskInstance."$method"()
                $taskInstance.Logs.AddExecution('Completed', "$($taskInstance::Name)[$method]")
            }
            catch [PSBuildTaskException]
            {
                throw $_
            }
            catch
            {
                $taskInstance.Logs.AddExecutionError('Failed', "$($taskInstance::Name)[$method]")
            }
        }
        else
        {
            $Logs.AddExecution('Skipped[not implemented]', "$($task.Name)[$method]")
        }
    }
}
#endregion

#region buildTasks
class PSModuleBuildTaskGetManifest : PSBuildTaskBase
{
    static [string]$Name = 'GetManifest'

    [void]OnBegin()
    {
        $manifestPath = Join-Path -Path $This.Context.FolderPath -ChildPath "$($This.Context.Name).psbuild.psd1"
        $this.Context.Manifest = Import-PowerShellDataFile -Path $manifestPath
    }
}

class PSModuleBuildTaskGetPrivateFunctions : PSBuildTaskBase
{
    static [string]$Name = 'GetPrivateFunctions'

    [void]AddFunctionToContext([PSBuildModuleFunction]$function)
    {
        if ($this.Context.PrivateFunctions.ContainsKey($function.Name))
        {
            $this.WriteError("Function: '$($function.Name)' in file: '$($function.RelativeSource)' is already defined in: '$($this.Context.PrivateFunctions[$function.Name].RelativeSource)'")
        }
        else
        {
            $this.Context.PrivateFunctions.Add($function.Name, $function)
        }
    }

    [System.Collections.Generic.List[PSBuildModuleFunction]]FindFunctions([string]$path, [string]$moduleRootFolder)
    {
        $result = [System.Collections.Generic.List[PSBuildModuleFunction]]::new()
        $getChildItemsParam = @{
            Path    = Join-Path -Path $path -ChildPath '*'
            File    = $true
            Include = '*.psm1', '*.ps1'
        }
        $functionDefinitionFiles = Get-ChildItem @getChildItemsParam
        foreach ($fdf in $functionDefinitionFiles)
        {
            $relativeSource = [System.IO.Path]::GetRelativePath($moduleRootFolder, $fdf.FullName)
            switch ($fdf.Extension)
            {
                '.psm1'
                {
                    $codeBlock = [ScriptBlock]::Create([System.IO.File]::ReadAllText($fdf.FullName))
                    $functionDefinitions = Get-AstStatement -Ast $codeBlock.Ast -Type FunctionDefinitionAst
                    foreach ($fd in $functionDefinitions)
                    {
                        $result.Add([PSBuildModuleFunction]@{
                                Name           = $fd.Name
                                Ast            = $codeBlock.Ast
                                Source         = $fdf.FullName
                                RelativeSource = $relativeSource
                            })
                    }
                    break
                }

                '.ps1'
                {
                    $codeBlock = [ScriptBlock]::Create([System.IO.File]::ReadAllText($fdf.FullName))
                    $functionDefinition = Get-AstStatement -Ast $codeBlock.Ast -Type FunctionDefinitionAst
                    if (($functionDefinition | Measure-Object).Count -gt 1)
                    {
                        $this.WriteError("File: '$relativeSource' contains more than one function definition")
                    }
                    $result.Add([PSBuildModuleFunction]@{
                            Name           = $functionDefinition.Name
                            Ast            = $codeBlock.Ast
                            Source         = $fdf.FullName
                            RelativeSource = $relativeSource
                        })
                    break
                }
            }
        }
        return $result
    }

    [void]OnBegin()
    {
        $privateFunctionsPath = Join-Path -Path $This.Context.FolderPath -ChildPath 'privateFunctions'
        if (Test-Path -Path $privateFunctionsPath)
        {
            $funInPath = $this.FindFunctions($privateFunctionsPath, $this.Context.FolderPath)
            foreach ($fip in $funInPath)
            {
                $this.AddFunctionToContext($fip)
            }
        }
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

[Flags()] enum PSBuildLogLevel
{
    Information = 2
    Warning = 4
    Execution = 8
}
#endregion