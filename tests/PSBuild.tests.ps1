$moduleName = $MyInvocation.MyCommand.Name -replace '.tests.ps1$'
$modulePath = Split-Path -Path $PSScriptRoot | Join-Path -ChildPath 'src' -AdditionalChildPath $moduleName
Import-Module -Name $modulePath -Force

InModuleScope $moduleName {
    describe 'Build-PSModule' {
        it "test" {
            $r = Build-PSModule -Name module1 -InformationAction Continue -PassThru
        }
    }
}