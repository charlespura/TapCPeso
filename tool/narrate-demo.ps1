$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$audioDirectory = Join-Path $projectRoot 'demo\audio'
New-Item -ItemType Directory -Path $audioDirectory -Force | Out-Null
$speaker = New-Object -ComObject SAPI.SpVoice
$voices = $speaker.GetVoices()
for ($voiceIndex = 0; $voiceIndex -lt $voices.Count; $voiceIndex++) {
    if ($voices.Item($voiceIndex).GetDescription() -like '*Zira*') {
        $speaker.Voice = $voices.Item($voiceIndex)
        break
    }
}
$speaker.Rate = 0
$speaker.Volume = 100
$scenes = Get-Content -LiteralPath (Join-Path $projectRoot 'demo\storyboard.json') -Raw | ConvertFrom-Json
try {
    for ($index = 0; $index -lt $scenes.Count; $index++) {
        $audioPath = Join-Path $audioDirectory ("scene-{0}.wav" -f $index)
        $stream = New-Object -ComObject SAPI.SpFileStream
        $stream.Open($audioPath, 3, $false)
        try {
            $speaker.AudioOutputStream = $stream
            $speaker.Speak($scenes[$index].narration) | Out-Null
        } finally { $stream.Close() }
    }
} finally { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($speaker) | Out-Null }
Write-Host 'English narration generated with the installed Microsoft Zira synthetic voice.'
