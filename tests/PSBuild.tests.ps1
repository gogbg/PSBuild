$moduleName = $MyInvocation.MyCommand.Name -replace '.tests.ps1$'
$modulePath = Split-Path -Path $PSScriptRoot | Join-Path -ChildPath 'src' -AdditionalChildPath $moduleName
Import-Module -Name $modulePath -Force

InModuleScope $moduleName {
    Describe 'Build-PSModule' {
        It "Should build module" {
            $script:m = Build-PSModule -Name module1 -PassThru -LogLevel Execution, Information, Warning
        }

        It "Should find 2 private functions" {
            $script:m.PrivateFunctions.Count | Should -BeExactly 2
        }
    }
}