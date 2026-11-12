$ErrorActionPreference = 'Stop'
$bootstrapScript = Join-Path $PSScriptRoot 'bootstrap.py'
& python $bootstrapScript
if ($LASTEXITCODE -ne 0) { throw 'Native platform bootstrap failed. See the output above.' }
